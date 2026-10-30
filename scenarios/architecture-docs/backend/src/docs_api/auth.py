from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from uuid import UUID

import jwt
from jwt import PyJWKClient


@dataclass(frozen=True)
class GatewayIdentity:
    principal_id: str
    audience: str


class GatewayVerifier:
    def __init__(self, tenant_id: str, audience: str, principal_id: str):
        self.tenant_id = str(UUID(tenant_id))
        self.principal_id = str(UUID(principal_id))
        self.audience = audience
        self.keys = PyJWKClient(
            f"https://login.microsoftonline.com/{self.tenant_id}/discovery/v2.0/keys",
            cache_keys=True,
        )

    def verify(self, authorization: str) -> GatewayIdentity:
        if not authorization.startswith("Bearer "):
            raise jwt.InvalidTokenError("A gateway Entra bearer token is required")
        token = authorization.removeprefix("Bearer ")
        key = self.keys.get_signing_key_from_jwt(token)
        claims: dict[str, Any] = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            audience=self.audience,
            options={"require": ["exp", "iss", "aud", "tid", "oid"]},
        )
        if claims["iss"] not in (
            f"https://sts.windows.net/{self.tenant_id}/",
            f"https://login.microsoftonline.com/{self.tenant_id}/v2.0",
        ):
            raise jwt.InvalidIssuerError("Unexpected token issuer")
        if claims["tid"] != self.tenant_id or claims["oid"] != self.principal_id:
            raise jwt.InvalidTokenError("Caller is not the permitted gateway identity")
        return GatewayIdentity(claims["oid"], self.audience)
