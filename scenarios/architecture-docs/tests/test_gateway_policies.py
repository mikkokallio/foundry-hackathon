import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

POLICIES = Path(__file__).resolve().parents[1] / "infra" / "policies"


@pytest.fixture(scope="module")
def policies(tmp_path_factory):
    def template(name, variables):
        return f"templatefile({json.dumps(str(POLICIES / name))}, {variables})"

    identity = template(
        "identity.xml",
        json.dumps(
            {
                "tenant_id": "00000000-0000-0000-0000-000000000001",
                "client_id": "00000000-0000-0000-0000-000000000002",
                "team_roles": "&quot;Team.alpha&quot;, &quot;Team.beta&quot;",
            }
        ),
    )
    json_body = template("mcp-json-body.xml", '{"docs_path": "scenario-a/docs-api"}')
    query = f"file({json.dumps(str(POLICIES / 'mcp-query-encoding.xml'))})"
    expressions = {
        "identity": identity,
        "backend": template(
            "backend.xml", f'{{auth = {identity}, audience = "api://test-workload"}}'
        ),
        "mcp": template(
            "docs-mcp.xml",
            f"{{auth = {identity}, json_body = {json_body}, query_encoding = {query}}}",
        ),
        "models": template(
            "models.xml",
            f'{{auth = {identity}, deployments = {{"chat-small" = "scenario-a-chat-small", "chat-medium" = "scenario-a-chat-medium", "judge" = "scenario-a-judge"}}, '
            'request_limit = 30, token_limit = 10000}',
        ),
        "models-tight": template(
            "models.xml",
            f'{{auth = {identity}, deployments = {{"chat-small" = "scenario-a-chat-small", "chat-medium" = "scenario-a-chat-medium", "judge" = "scenario-a-judge"}}, '
            'request_limit = 2, token_limit = 256}',
        ),
    }
    expression = "jsonencode({" + ", ".join(
        f'"{name}" = {value}' for name, value in expressions.items()
    ) + "})"
    result = subprocess.run(
        ["terraform", "console", "-no-color"],
        input=expression + "\n",
        capture_output=True,
        text=True,
        cwd=tmp_path_factory.mktemp("policy-render-only"),
        timeout=60,
        check=True,
    )
    rendered = json.loads(json.loads(result.stdout))
    assert all("${" not in value for value in rendered.values())
    return {
        name: ET.fromstring(f"<fragment>{value}</fragment>" if name == "identity" else value)
        for name, value in rendered.items()
    }


def test_identity_accepts_configured_teams_not_a_fixed_team_number(policies):
    identity = policies["identity"]
    expression = identity.find("set-variable").attrib["value"]
    assert 'new string[] {"Team.alpha", "Team.beta"}' in expression
    assert "teams.Length == 1" in expression
    assert 'teams.Length == 0 && roles.Contains("Librarian")' in expression
    assert "team1" not in expression
    for header in ("X-Team-Id", "X-Publisher-Role", "X-Reviewer"):
        assert identity.find(f"set-header[@name='{header}']").attrib["exists-action"] == "override"
    assert identity.find("validate-jwt").attrib["require-signed-tokens"] == "true"


def test_backend_authenticates_with_identity_and_gates_publication(policies):
    inbound = policies["backend"].find("inbound")
    assert inbound.find("authentication-managed-identity").attrib["resource"] == "api://test-workload"
    publication_checks = [
        when
        for when in inbound.findall("choose/when")
        if 'context.Operation.Id == "publishProposal"' in when.attrib["condition"]
    ]
    assert len(publication_checks) == 1
    assert publication_checks[0].find("return-response/set-status").attrib["code"] == "403"


def test_native_mcp_posts_keep_the_workload_namespace_and_real_errors(policies):
    inbound = policies["mcp"].find("inbound")
    requests = inbound.findall(".//send-request")
    assert len(requests) == 1
    assert '"/scenario-a/docs-api" + path' in requests[0].findtext("set-url")
    assert requests[0].attrib["ignore-error"] == "false"
    assert requests[0].find("set-header[@name='Authorization']") is not None
    body = inbound.findtext(".//return-response/set-body")
    assert '"isError", response.StatusCode >= 400' in body
    assert "response.Body.As<string>()" in body


@pytest.mark.parametrize("name, requests, tokens", [("models", "30", "10000"), ("models-tight", "2", "256")])
def test_model_policies_have_real_namespaced_routes_and_distinct_limits(
    policies, name, requests, tokens
):
    inbound = policies[name].find("inbound")
    assert inbound.find("rate-limit-by-key").attrib["calls"] == requests
    assert inbound.find("azure-openai-token-limit").attrib["tokens-per-minute"] == tokens
    assert "context.Api.Id" in inbound.find("rate-limit-by-key").attrib["counter-key"]
    routing = inbound.find("set-variable[@name='modelDeployment']").attrib["value"]
    assert '{"chat-small", "scenario-a-chat-small"}' in routing
    assert '{"chat-medium", "scenario-a-chat-medium"}' in routing
    assert '{"judge", "scenario-a-judge"}' in routing
    assert "allowed.ContainsKey(model)" in routing
    assert any(node.attrib["code"] == "400" for node in inbound.findall("choose/when/return-response/set-status"))
    assert 'context.Variables["modelDeployment"]' in inbound.find("rewrite-uri").attrib["template"]
    assert 'body["model"] = (string)context.Variables["modelDeployment"]' in inbound.findtext("set-body")
    assert inbound.find("authentication-managed-identity").attrib["resource"] == (
        "https://cognitiveservices.azure.com"
    )
