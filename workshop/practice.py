"""Create only prefixed exercise objects; read but never edit shared references."""

from __future__ import annotations

import json
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from urllib.error import HTTPError

from workshop.__main__ import arm, output_path, prefix_for, project_id, save_new


def gateway_id(pack: dict[str, Any]) -> str:
    backend = pack["gateway_exercises"]["model_backend_ids"]["chat-small"]
    return backend.rsplit("/backends/", 1)[0]


def add(
    pack: dict[str, Any], identity: Any, resource: str, version: str, properties: dict[str, Any]
) -> None:
    try:
        current = arm(pack, identity, resource, version)
    except HTTPError as exc:
        if exc.code != 404:
            raise
        arm(pack, identity, resource, version, method="PUT", body={"properties": properties})
        print("Created: " + resource)
        return
    actual = current["properties"]
    if any(
        actual.get(key) != value
        for key, value in properties.items()
        if key in actual or key not in ("format", "value")
    ):
        raise ValueError(f"Existing object differs; inspect it rather than overwrite: {resource}")
    print("Already present and matching: " + resource)


def practice(args: Any, pack: dict[str, Any], identity: Any) -> None:
    prefix = prefix_for(pack, args.prefix)
    service = gateway_id(pack)
    version = "2024-05-01"
    workload = pack["workload_name"]
    base = pack["docs_url"].split("/" + workload + "/")[0]
    if args.kind == "status":
        for name in ("docs-api", "docs-mcp", "models-requests", "models-tokens"):
            resource = f"{service}/apis/{prefix}-{name}"
            try:
                found = arm(pack, identity, resource, version)
            except HTTPError as exc:
                if exc.code != 404:
                    raise
                print("Missing: " + resource)
                continue
            print(f"Present: {resource}, path={found['properties'].get('path')}")
        return
    if args.kind == "docs":
        source = arm(pack, identity, f"{service}/apis/{workload}-docs-api", version)["properties"]
        api = f"{service}/apis/{prefix}-docs-api"
        spec = json.loads((args.pack.parent / "openapi.json").read_text("utf-8-sig"))
        add(
            pack,
            identity,
            api,
            version,
            {
                "displayName": prefix + " documentation practice",
                "path": prefix + "/docs-api",
                "protocols": ["https"],
                "subscriptionRequired": False,
                "serviceUrl": source["serviceUrl"],
                "format": "openapi+json",
                "value": json.dumps(spec),
            },
        )
        copy_policy(pack, identity, service, workload + "-docs-api", prefix + "-docs-api")
        mcp = f"{service}/apis/{prefix}-docs-mcp"
        add(
            pack,
            identity,
            mcp,
            "2025-09-01-preview",
            {
                "type": "mcp",
                "displayName": prefix + " documentation MCP",
                "path": prefix + "/docs-mcp",
                "protocols": ["https"],
                "subscriptionRequired": False,
                "mcpProperties": {"transportType": "streamable"},
            },
        )
        for methods in spec["paths"].values():
            for method, operation in methods.items():
                if method not in ("get", "post") or operation["operationId"] in (
                    "health",
                    "publishProposal",
                ):
                    continue
                name = operation["operationId"]
                add(
                    pack,
                    identity,
                    f"{mcp}/tools/{name}",
                    "2025-09-01-preview",
                    {
                        "displayName": name,
                        "description": operation.get("description", "")[:1000],
                        "operationId": f"{api}/operations/{name}",
                    },
                )
        copy_policy(
            pack,
            identity,
            service,
            workload + "-docs-mcp",
            prefix + "-docs-mcp",
            replace_path=(f"/{workload}/docs-api", f"/{prefix}/docs-api"),
        )
        resource = f"{project_id(pack)}/connections/{prefix}-docs"
        add(
            pack,
            identity,
            resource,
            "2025-04-01-preview",
            {
                "category": "RemoteTool",
                "authType": "ProjectManagedIdentity",
                "target": f"{base}/{prefix}/docs-mcp/mcp",
                "audience": pack["gateway_scope"].split("/")[2],
                "isSharedToAll": False,
            },
        )
        print(
            "Practice created. Test real REST, MCP GET and POST validation; creation is not acceptance."
        )
    else:
        for kind in ("requests", "tokens"):
            name = prefix + "-models-" + kind
            api = f"{service}/apis/{name}"
            source = arm(pack, identity, f"{service}/apis/{workload}-models", version)["properties"]
            add(
                pack,
                identity,
                api,
                version,
                {
                    "displayName": name,
                    "path": prefix + "/models-" + kind,
                    "protocols": ["https"],
                    "subscriptionRequired": False,
                    "serviceUrl": source["serviceUrl"],
                },
            )
            add(
                pack,
                identity,
                api + "/operations/chat-completions",
                version,
                {
                    "displayName": "Governed model request",
                    "method": "POST",
                    "urlTemplate": "/chat/completions",
                    "templateParameters": [],
                },
            )
            copy_policy(pack, identity, service, workload + "-models", name, limiter=kind)
    source_name = workload + ("-docs-mcp" if args.kind == "docs" else "-models")
    diagnostic = arm(
        pack, identity, f"{service}/apis/{source_name}/diagnostics/applicationinsights", version
    )
    names = (
        [prefix + "-docs-api", prefix + "-docs-mcp"]
        if args.kind == "docs"
        else [
            prefix + "-models-requests",
            prefix + "-models-tokens",
        ]
    )
    for name in names:
        add(
            pack,
            identity,
            f"{service}/apis/{name}/diagnostics/applicationinsights",
            version,
            diagnostic["properties"],
        )


def copy_policy(
    pack: dict[str, Any],
    identity: Any,
    service: str,
    source: str,
    target: str,
    replace_path: tuple[str, str] | None = None,
    limiter: str | None = None,
) -> None:
    value = arm(pack, identity, f"{service}/apis/{source}/policies/policy", "2024-05-01")
    xml = value["properties"]["value"]
    if replace_path:
        if replace_path[0] not in xml:
            raise ValueError(
                "Expected reference POST-adapter path is missing; refuse a guessed policy."
            )
        xml = xml.replace(*replace_path)
    if limiter:
        document = ET.fromstring(xml)
        rate = document.find(".//rate-limit-by-key")
        token = document.find(".//azure-openai-token-limit")
        inbound = document.find("inbound")
        metric = document.find(".//azure-openai-emit-token-metric")
        if rate is None or token is None or inbound is None or metric is None:
            raise ValueError("Reference limiter/metric policy shape differs; no guessed fallback.")
        rate.set("calls", "2" if limiter == "requests" else "30")
        token.set("tokens-per-minute", "50000" if limiter == "requests" else "256")
        inbound.remove(metric)
        ET.SubElement(metric, "dimension", {"name": "Project", "value": pack["team"]})
        ET.SubElement(
            metric,
            "dimension",
            {
                "name": "Model",
                "value": '@((string)context.Variables["modelDeployment"])',
            },
        )
        inbound.append(metric)
        xml = ET.tostring(document, encoding="unicode")
    add(
        pack,
        identity,
        f"{service}/apis/{target}/policies/policy",
        "2024-05-01",
        {"format": "rawxml", "value": xml},
    )


def catalog(args: Any, pack: dict[str, Any], identity: Any) -> None:
    resource = pack.get("catalog_resource_id")
    if not resource:
        raise ValueError("This older pack lacks catalog_resource_id. Export a fresh pack.")
    base = resource + "/workspaces/default/apis"
    version = "2024-03-01"
    if args.action == "list":
        print(json.dumps(arm(pack, identity, base, version), indent=2))
    elif args.action == "register":
        prefix = prefix_for(pack, args.prefix)
        endpoint = pack["docs_url"].split("/" + pack["workload_name"] + "/")[0]
        add(
            pack,
            identity,
            base + "/" + prefix + "-docs",
            version,
            {
                "title": prefix + " documentation MCP discovery",
                "kind": "rest",
                "description": "Development; synthetic Internal lab data; owner "
                + prefix
                + "; read/validate and human-approved proposals; never agent publication.",
                "externalDocumentation": [
                    {
                        "title": "Authenticated MCP endpoint",
                        "url": endpoint + "/" + prefix + "/docs-mcp/mcp",
                    }
                ],
            },
        )
        print("REST catalog record with MCP discovery metadata; not native MCP-kind registration.")
        api = base + "/" + prefix + "-docs"
        add(
            pack,
            identity,
            api + "/versions/version-1",
            version,
            {"title": "1.0", "lifecycleStage": "development"},
        )
        definition = api + "/versions/version-1/definitions/openapi"
        add(pack, identity, definition, version, {"title": "Practice documentation OpenAPI"})
        specification = json.loads((args.pack.parent / "openapi.json").read_text("utf-8-sig"))
        arm(
            pack,
            identity,
            definition + "/importSpecification",
            version,
            method="POST",
            body={
                "format": "inline",
                "value": json.dumps(specification),
                "specification": {"name": "openapi", "version": specification["openapi"]},
            },
        )
        print(
            "Version and actual OpenAPI imported. Add environment/deployment metadata in the portal."
        )
    else:
        if not args.output:
            raise ValueError("Catalog export requires --output under out.")
        destination = output_path(args.output)
        if destination.exists():
            raise ValueError("Export output already exists.")
        definition = base + "/" + pack["workload_name"] + "/versions/version-1/definitions/openapi"
        result = arm(pack, identity, definition + "/exportSpecification", version, method="POST")
        link = result.get("value")
        if result.get("format") != "inline" or not isinstance(link, str):
            raise ValueError(
                "Export was not inline. Use the documented az apic export path; no source substitute."
            )
        save_new(destination, json.loads(link))
        print(Path(destination))
