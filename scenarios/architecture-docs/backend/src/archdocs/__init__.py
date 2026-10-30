"""Framework-free core for the architecture documentation scenario.

Used by the Docs API (src/docs_api), the B2 MCP server (src/mcp_server) and the
custom evaluators (src/eval). Only depends on PyYAML; Azure Blob support is
imported lazily so local development needs no Azure packages.
"""

from .gaps import find_gaps
from .inventory import Inventory
from .service import DocsService, Forbidden, NotFound, ProposalRejected
from .standard import (
    ValidationResult,
    find_secrets,
    interface_ids_in_table,
    parse_document,
    validate_document,
)
from .store import DocStore, LocalStore, make_store

__all__ = [
    "DocStore",
    "DocsService",
    "Forbidden",
    "Inventory",
    "LocalStore",
    "NotFound",
    "ProposalRejected",
    "ValidationResult",
    "find_gaps",
    "find_secrets",
    "interface_ids_in_table",
    "make_store",
    "parse_document",
    "validate_document",
]
