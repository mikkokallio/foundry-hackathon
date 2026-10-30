from contextlib import asynccontextmanager

from docs_api.config import Settings
from docs_api.main import _add_gateway_identity_check
from fastapi import FastAPI
from server import build_server, get_inventory


def create_app():
    settings = Settings.from_env()
    settings.check()
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
    return app
