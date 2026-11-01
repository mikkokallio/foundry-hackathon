import json
import logging
import os
from contextlib import asynccontextmanager

from docs_api.config import Settings
from docs_api.main import _add_gateway_identity_check
from fastapi import FastAPI
from server import build_server, get_inventory
from starlette.types import ASGIApp, Message, Receive, Scope, Send

PROTOCOL_LOG = logging.getLogger("uvicorn.error.mcp_protocol")
DIAGNOSTIC_BODY_LIMIT = 16384


class _ProtocolDiagnostics:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["path"] not in ("/mcp", "/mcp/"):
            await self.app(scope, receive, send)
            return

        status: int | None = None
        json_response = False
        complete = False
        truncated = False
        body = bytearray()

        async def observe(message: Message) -> None:
            nonlocal status, json_response, complete, truncated
            if message["type"] == "http.response.start":
                status = message["status"]
                json_response = any(
                    name.lower() == b"content-type"
                    and value.split(b";", 1)[0].strip().lower() == b"application/json"
                    for name, value in message.get("headers", [])
                )
            elif message["type"] == "http.response.body" and json_response:
                chunk = message.get("body", b"")
                if len(body) + len(chunk) <= DIAGNOSTIC_BODY_LIMIT and not truncated:
                    body.extend(chunk)
                else:
                    truncated = True
                    body.clear()
            await send(message)
            if message["type"] == "http.response.body" and not message.get("more_body", False):
                complete = True

        try:
            await self.app(scope, receive, observe)
        finally:
            metadata: dict[str, bool | int | str] = {
                "response_started": status is not None,
                "response_complete": complete,
                "json_response": json_response,
                "body_truncated": truncated,
            }
            category = {
                400: "bad-request", 401: "unauthorized", 403: "forbidden",
                404: "not-found", 405: "method-not-allowed", 406: "accept-mismatch",
                415: "content-type-mismatch", 429: "throttled",
            }.get(status, "http-response")
            if status is not None:
                metadata["http_status"] = status
            if json_response and complete and not truncated:
                try:
                    payload = json.loads(body)
                except (ValueError, UnicodeDecodeError, RecursionError):
                    metadata["json_valid"] = False
                else:
                    metadata["json_valid"] = True
                    error = payload.get("error") if isinstance(payload, dict) else None
                    code = error.get("code") if isinstance(error, dict) else None
                    if isinstance(code, int) and not isinstance(code, bool) and -(2**31) <= code < 2**31:
                        metadata["jsonrpc_error_code"] = code
                        category = {
                            -32700: "parse-error", -32600: "invalid-request",
                            -32601: "method-not-found", -32602: "invalid-params",
                            -32603: "internal-error",
                        }.get(code, "jsonrpc-error")
            metadata["category"] = category if complete else "transport-incomplete"
            PROTOCOL_LOG.info("mcp_protocol %s", json.dumps(metadata, sort_keys=True))


def create_app():
    settings = Settings.from_env()
    settings.check()
    diagnostics = os.environ.get("MCP_PROTOCOL_DIAGNOSTICS", "false")
    if diagnostics not in ("true", "false"):
        raise ValueError("MCP_PROTOCOL_DIAGNOSTICS must be true or false.")
    get_inventory()
    server = build_server()
    transport = server.streamable_http_app()

    @asynccontextmanager
    async def lifespan(app):
        async with server.session_manager.run():
            yield

    app = FastAPI(lifespan=lifespan)

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "architecture-toolkit"}

    app.mount("/", transport)
    if settings.auth_mode == "entra":
        _add_gateway_identity_check(app, settings)
    if diagnostics == "true":
        app.add_middleware(_ProtocolDiagnostics)
    return app
