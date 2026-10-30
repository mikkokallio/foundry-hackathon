"""HTTP layer over DocsService; operation IDs are the APIM MCP tool names."""

import logging
import re
import threading
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from html import escape
from typing import Annotated, Any, Literal

import jwt
from archdocs import DocsService, Forbidden, Inventory, NotFound, ProposalRejected
from archdocs.store import StoreConflict, seed_published
from fastapi import APIRouter, Depends, FastAPI, Path, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from .auth import GatewayVerifier
from .config import Settings, build_store, log_event, resolve_team

API_VERSION = "1.0.0"
API_DESCRIPTION = (
    "Shared architecture documentation for {organization_name}. All lab business data is synthetic. "
    "Read the system inventory and published architecture documents, find documentation gaps, "
    "validate drafts against the documentation standard and submit proposals for librarian review. "
    "Agents never publish directly."
)

SYSTEM_ID_PATTERN = r"^SYS-\d{3}$"
DOC_ID_PATTERN = r"^ARCH-[A-Z]{2,6}$"
TEAM_PATTERN = r"^[a-z0-9][a-z0-9-]{0,31}$"
PROPOSAL_ID_PATTERN = r"^P-\d{14}-[a-z0-9][a-z0-9-]{0,31}-[0-9a-f]{4}$"

DocStatus = Literal["draft", "published", "archived"]
SystemStatus = Literal["active", "pilot", "decommissioned"]
InterfaceStatus = Literal["active", "planned", "decommissioned"]
ProposalStatus = Literal["pending-review", "needs-changes", "published"]
AuthorType = Literal["agent", "human", "coding-agent"]


# ----- request models ------------------------------------------------------------
class ValidateRequest(BaseModel):
    markdown: str = Field(
        min_length=1,
        max_length=200_000,
        description="Complete document markdown, starting with the YAML front matter block (--- ... ---).",
    )


class ProposalRequest(BaseModel):
    system_id: str = Field(
        pattern=SYSTEM_ID_PATTERN,
        description="System the document describes, format SYS-NNN (e.g. SYS-011). Must exist in the inventory "
        "and match system_id in the front matter.",
    )
    doc_id: str | None = Field(
        default=None,
        pattern=DOC_ID_PATTERN,
        description="Document ID, format ARCH-XXX (2-6 capital letters). Optional: taken from the front matter "
        "when omitted. Reuse the existing doc_id to update a published document.",
    )
    markdown: str = Field(
        min_length=1,
        max_length=200_000,
        description="Complete document markdown with YAML front matter, following the template from "
        "getDocumentationStandard. Never include credentials.",
    )
    summary: str = Field(
        min_length=1,
        max_length=1000,
        description="One or two sentences for the librarian: what changed and why.",
    )
    author_type: AuthorType = Field(
        default="agent",
        description="Who produced the draft: agent (Foundry agent), coding-agent (e.g. a GitHub Copilot skill) "
        "or human.",
    )
    source: str | None = Field(
        default=None,
        max_length=200,
        description="Agent, tool or skill that produced the draft, e.g. docs-steward-team1.",
    )
    team: str | None = Field(
        default=None,
        max_length=32,
        description="Submitting team. Ignored behind the API gateway, which sets the team from your "
        "signed Entra team role. Defaults to local in test-scoped local mode.",
    )


# ----- service wiring -------------------------------------------------------------
_init_lock = threading.Lock()


def build_service(settings: Settings) -> DocsService:
    """Create the store (seeding it if configured), load the inventory and build the service."""
    settings.check()
    store = build_store(settings)
    if settings.seed_on_start:
        seeded = seed_published(store, settings.seed_dir)
        log_event(
            "store_seeded",
            documents=seeded,
            seed_dir=settings.seed_dir,
            storage_mode=settings.storage_mode,
        )
    inventory = Inventory(settings.inventory_dir)
    return DocsService(
        store,
        inventory,
        settings.standard_dir,
        settings.reference_date,
        settings.review_max_age_days,
        organization_name=settings.organization_name,
    )


def ensure_service(app: FastAPI) -> DocsService:
    """Build the service once per app (at startup, or lazily on the first request)."""
    service = getattr(app.state, "service", None)
    if service is None:
        with _init_lock:
            service = getattr(app.state, "service", None)
            if service is None:
                service = build_service(app.state.settings)
                app.state.service = service
    return service


def get_service(request: Request) -> DocsService:
    return ensure_service(request.app)


ServiceDep = Annotated[DocsService, Depends(get_service)]
router = APIRouter()


# ----- routes -----------------------------------------------------------------------
@router.get(
    "/health",
    operation_id="health",
    tags=["health"],
    summary="Health check",
    description="Liveness probe for the Docs API. Returns status ok, the API version, the storage mode and the "
    "reference date used for review-age checks. Not intended as an agent tool.",
)
def health(request: Request) -> dict[str, Any]:
    settings: Settings = request.app.state.settings
    return {
        "status": "ok",
        "version": API_VERSION,
        "storage_mode": settings.storage_mode,
        "reference_date": settings.reference_date.isoformat() if settings.reference_date else None,
    }


@router.get(
    "/documents",
    operation_id="listDocuments",
    tags=["documents"],
    summary="List published architecture documents",
    description="Returns metadata of the documents in the shared store (doc_id, title, system_id, owner_team, "
    "status, version, last_reviewed, classification), without the markdown. Use it to find which "
    "document covers a system, then call getDocument for the full text.",
)
def list_documents(
    service: ServiceDep,
    system_id: Annotated[
        str | None,
        Query(
            pattern=SYSTEM_ID_PATTERN,
            description="Only documents for this system, format SYS-NNN (e.g. SYS-002).",
        ),
    ] = None,
    status: Annotated[
        DocStatus | None, Query(description="Only documents with this front-matter status.")
    ] = None,
) -> list[dict[str, Any]]:
    return service.list_documents(system_id=system_id, status=status)


@router.get(
    "/documents/{doc_id}",
    operation_id="getDocument",
    tags=["documents"],
    summary="Get one architecture document with its markdown",
    description="Returns the metadata, the list of H2 sections and the full markdown of a published document. "
    "Use it to answer questions from the documentation or before drafting an update. "
    "Find the doc_id with listDocuments or getSystem.",
)
def get_document(
    service: ServiceDep,
    doc_id: Annotated[
        str,
        Path(
            pattern=DOC_ID_PATTERN,
            description="Document ID, format ARCH-XXX (2-6 capital letters), e.g. ARCH-SOM.",
        ),
    ],
) -> dict[str, Any]:
    return service.get_document(doc_id)


@router.get(
    "/systems",
    operation_id="listSystems",
    tags=["inventory"],
    summary="List systems in the inventory",
    description="Returns the systems of the system inventory (system_id SYS-NNN, name, domain, owner_team, status, "
    "hosting, criticality, description) with the doc_ids of their published documents. The inventory "
    "is the source of truth for owners and lifecycle status.",
)
def list_systems(
    service: ServiceDep,
    domain: Annotated[
        str | None,
        Query(
            max_length=100,
            description="Only systems in this domain (case-insensitive), e.g. Service Operations, Equipment Data, "
            "Parts & Logistics.",
        ),
    ] = None,
    status: Annotated[
        SystemStatus | None, Query(description="Only systems with this lifecycle status.")
    ] = None,
) -> list[dict[str, Any]]:
    return service.list_systems(domain=domain, status=status)


@router.get(
    "/systems/{system_id}",
    operation_id="getSystem",
    tags=["inventory"],
    summary="Get one system with its interfaces, data products and documents",
    description="Returns the inventory record of a system with owner contact, every interface where it is source, "
    "target or integration route (via), the data products it produces or consumes, "
    "expected_interface_ids (active interfaces its document must list) and doc_ids. Use it for "
    "ownership and integration questions and before drafting a document.",
)
def get_system(
    service: ServiceDep,
    system_id: Annotated[
        str, Path(pattern=SYSTEM_ID_PATTERN, description="System ID, format SYS-NNN, e.g. SYS-002.")
    ],
) -> dict[str, Any]:
    return service.get_system(system_id)


@router.get(
    "/interfaces",
    operation_id="listInterfaces",
    tags=["inventory"],
    summary="List interfaces between systems",
    description="Returns interfaces (interface_id INT-NNN) with source, target and via (integration route) system "
    "IDs and names, pattern, protocol, data, data_product, frequency and status.",
)
def list_interfaces(
    service: ServiceDep,
    system_id: Annotated[
        str | None,
        Query(
            pattern=SYSTEM_ID_PATTERN,
            description="Only interfaces where this system (SYS-NNN) is source, target or via.",
        ),
    ] = None,
    status: Annotated[
        InterfaceStatus | None, Query(description="Only interfaces with this status.")
    ] = None,
) -> list[dict[str, Any]]:
    return service.list_interfaces(system_id=system_id, status=status)


@router.get(
    "/data-products",
    operation_id="listDataProducts",
    tags=["inventory"],
    summary="List data products",
    description="Returns data products (data_product_id DP-NNN) with name, domain, owner_team, source_systems, "
    "consumers (system IDs), classification, refresh rate and description.",
)
def list_data_products(
    service: ServiceDep,
    domain: Annotated[
        str | None,
        Query(
            max_length=100,
            description="Only data products in this domain (case-insensitive), e.g. Equipment Data.",
        ),
    ] = None,
) -> list[dict[str, Any]]:
    return service.list_data_products(domain=domain)


@router.get(
    "/gaps",
    operation_id="findDocumentationGaps",
    tags=["governance"],
    summary="Find documentation gaps",
    description="Compares the published documents with the inventory and the documentation standard. Returns one "
    "item per gap with gap_type (missing_document, stale_review, decommissioned_system_documented, "
    "interface_missing_in_doc, decommissioned_interface_in_doc, owner_mismatch, "
    "template_noncompliance), system_id, doc_id, severity (high, medium, low), interface_id when "
    "relevant, and detail. Omit system_id to check all systems.",
)
def find_documentation_gaps(
    service: ServiceDep,
    system_id: Annotated[
        str | None,
        Query(pattern=SYSTEM_ID_PATTERN, description="Check only this system, format SYS-NNN."),
    ] = None,
) -> list[dict[str, Any]]:
    return service.find_gaps(system_id=system_id)


@router.get(
    "/standard",
    operation_id="getDocumentationStandard",
    tags=["governance"],
    summary="Get the documentation standard and document template",
    description="Returns the documentation standard and the architecture document template as markdown, plus the "
    "required front-matter fields and the required H2 sections in order. Read it before drafting or "
    "fixing a document.",
)
def get_documentation_standard(service: ServiceDep) -> dict[str, Any]:
    return service.get_standard()


@router.post(
    "/validate",
    operation_id="validateDocument",
    tags=["governance"],
    summary="Validate a document against the standard (stores nothing)",
    description="Checks a markdown document against the documentation standard and the inventory: front matter, "
    "required sections and order, Mermaid diagram in Context, Interfaces table with INT-NNN IDs, "
    "missing active interfaces, decommissioned or unknown interfaces, owner team and credentials. "
    "Returns valid, errors, warnings and the parsed metadata. Call it before submitProposal and fix "
    "every error.",
)
def validate_document(body: ValidateRequest, service: ServiceDep) -> dict[str, Any]:
    return service.validate(body.markdown)


@router.post(
    "/proposals",
    operation_id="submitProposal",
    tags=["proposals"],
    summary="Submit a document proposal for librarian review",
    description="Stores a new or updated architecture document as a proposal; it never publishes. The document is "
    "validated: valid becomes pending-review, invalid is stored as needs-changes with the errors. "
    "Documents containing credentials are rejected with 422 and not stored. Returns proposal_id "
    "(P-<yyyymmddHHMMSS>-<team>-<4 hex>), status, validation and stored_at. Call validateDocument first.",
)
def submit_proposal(body: ProposalRequest, request: Request, service: ServiceDep) -> dict[str, Any]:
    team = resolve_team(
        request.headers.get("X-Team-Id"),
        body.team if request.app.state.settings.auth_mode == "local" else None,
    )
    try:
        result = service.submit_proposal(
            system_id=body.system_id,
            markdown=body.markdown,
            summary=body.summary,
            author_type=body.author_type,
            doc_id=body.doc_id,
            source=body.source,
            team=team,
        )
    except ProposalRejected as exc:
        log_event(
            "proposal_rejected",
            level=logging.WARNING,
            team=team,
            proposal_id=None,
            status="rejected",
            system_id=body.system_id,
            author_type=body.author_type,
            findings=len(exc.findings),
        )
        raise
    log_event(
        "proposal_submitted",
        team=result["team"],
        proposal_id=result["proposal_id"],
        status=result["status"],
        system_id=body.system_id,
        doc_id=result["doc_id"],
        author_type=body.author_type,
        source=body.source,
    )
    return result


@router.get(
    "/proposals",
    operation_id="listProposals",
    tags=["proposals"],
    summary="List submitted proposals",
    description="Returns proposals, newest first, with proposal_id, team, system_id, doc_id, summary, author_type, "
    "source, status (pending-review, needs-changes, published), created_at and valid. Check it before "
    "submitting to avoid duplicates.",
)
def list_proposals(
    service: ServiceDep,
    team: Annotated[
        str | None,
        Query(pattern=TEAM_PATTERN, description="Only proposals from this team, e.g. team1."),
    ] = None,
    status: Annotated[
        ProposalStatus | None, Query(description="Only proposals with this status.")
    ] = None,
) -> list[dict[str, Any]]:
    return service.list_proposals(team=team, status=status)


@router.get(
    "/proposals/{proposal_id}",
    operation_id="getProposal",
    tags=["proposals"],
    summary="Get one proposal with its validation result",
    description="Returns the full proposal record: team, system_id, doc_id, summary, author_type, source, status, "
    "created_at, the validation result (errors, warnings) and the submitted markdown.",
)
def get_proposal(
    service: ServiceDep,
    proposal_id: Annotated[
        str,
        Path(
            pattern=PROPOSAL_ID_PATTERN,
            description="Proposal ID returned by submitProposal, format P-<yyyymmddHHMMSS>-<team>-<4 hex>, "
            "e.g. P-20261103101500-team1-a1b2.",
        ),
    ],
) -> dict[str, Any]:
    return service.get_proposal(proposal_id)


@router.post(
    "/proposals/{proposal_id}/publish",
    operation_id="publishProposal",
    tags=["librarian"],
    summary="Publish a proposal (librarian only)",
    description="Librarian-only governance operation; never expose it as an agent tool. Publishes a pending-review "
    "proposal: archives the current version to archive/<doc_id>/<version>.md, writes "
    "published/<doc_id>.md and marks the proposal published. Requires header X-Publisher-Role: "
    "librarian (overwritten by the API gateway from the signed Entra Librarian role), otherwise 403. "
    "The gateway also overwrites X-Reviewer with the signed caller identity.",
)
def publish_proposal(
    request: Request,
    service: ServiceDep,
    proposal_id: Annotated[
        str,
        Path(
            pattern=PROPOSAL_ID_PATTERN,
            description="Proposal ID to publish, format P-<yyyymmddHHMMSS>-<team>-<4 hex>.",
        ),
    ],
) -> dict[str, Any]:
    role = request.headers.get("X-Publisher-Role")
    reviewer = request.headers.get("X-Reviewer")
    caller = request.headers.get("X-Team-Id")
    try:
        result = service.publish_proposal(proposal_id, publisher_role=role, reviewer=reviewer)
    except Forbidden:
        log_event(
            "publish_forbidden",
            level=logging.WARNING,
            team=caller,
            proposal_id=proposal_id,
            status="forbidden",
        )
        raise
    log_event(
        "proposal_published",
        team=caller,
        proposal_id=proposal_id,
        status=result["status"],
        doc_id=result["doc_id"],
        reviewer=reviewer,
        archived_previous=result["archived_previous"],
    )
    return result


# ----- error mapping ------------------------------------------------------------------
async def _not_found(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=404, content={"detail": str(exc)})


async def _forbidden(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=403, content={"detail": str(exc)})


async def _rejected(request: Request, exc: Exception) -> JSONResponse:
    findings = getattr(exc, "findings", [])
    return JSONResponse(status_code=422, content={"detail": str(exc), "findings": findings})


async def _bad_request(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": str(exc)})


async def _conflict(request: Request, exc: Exception) -> JSONResponse:
    log_event("publication_conflict", level=logging.WARNING, path=request.url.path)
    return JSONResponse(status_code=409, content={"detail": str(exc)})


def _add_gateway_identity_check(app: FastAPI, settings: Settings) -> None:
    verifier = GatewayVerifier(
        settings.tenant_id, settings.gateway_audience, settings.gateway_principal_id
    )

    @app.middleware("http")
    async def require_gateway_identity(request: Request, call_next):  # type: ignore[no-untyped-def]
        content_length = request.headers.get("content-length")
        if content_length and (not content_length.isdigit() or int(content_length) > 250_000):
            return JSONResponse(status_code=413, content={"detail": "Payload exceeds lab limit"})
        if request.url.path != "/health":
            try:
                verifier.verify(request.headers.get("Authorization", ""))
            except jwt.PyJWTError:
                log_event("gateway_identity_rejected", level=logging.WARNING, path=request.url.path)
                return JSONResponse(
                    status_code=401, content={"detail": "Gateway identity required"}
                )
            team = request.headers.get("X-Team-Id", "")
            if not team or not re.fullmatch(TEAM_PATTERN, team):
                return JSONResponse(status_code=403, content={"detail": "Verified team required"})
        return await call_next(request)


# ----- application factory ------------------------------------------------------------
def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the FastAPI app. Settings default to the environment (see app/config.py)."""
    settings = settings or Settings.from_env()
    settings.check()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        ensure_service(app)
        log_event(
            "startup",
            storage_mode=settings.storage_mode,
            inventory_dir=settings.inventory_dir,
            reference_date=settings.reference_date,
            auth_mode=settings.auth_mode,
        )
        yield

    app = FastAPI(
        title=f"{settings.organization_name} Architecture Docs API",
        version=API_VERSION,
        description=API_DESCRIPTION.format(organization_name=escape(settings.organization_name)),
        servers=[{"url": "/"}],
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.service = None
    app.include_router(router)
    app.add_exception_handler(NotFound, _not_found)
    app.add_exception_handler(Forbidden, _forbidden)
    app.add_exception_handler(ProposalRejected, _rejected)
    app.add_exception_handler(ValueError, _bad_request)
    app.add_exception_handler(StoreConflict, _conflict)
    if settings.auth_mode == "entra":
        _add_gateway_identity_check(app, settings)
    return app
