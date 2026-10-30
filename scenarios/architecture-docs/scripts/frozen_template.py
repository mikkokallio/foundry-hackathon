"""Inherited TemplateComplianceEvaluator and its document-selection helpers.

Source: foundry-agents-ai-gateway-lab/scenarios/architecture-docs/eval/evaluators.py.
The rubric, precedence, fence handling and draft-only applicability are unchanged.
Only the unused evaluators and their imports have been omitted.
"""
from __future__ import annotations

import json
import math
import re
from typing import Any

from archdocs import validate_document

DOCUMENT_TOOLS = ("submitProposal", "validateDocument")


def as_list(value: Any) -> list:
    if value is None or isinstance(value, float):
        return []
    if hasattr(value, "tolist"):
        value = value.tolist()
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return []
        if text.startswith("["):
            try:
                return list(json.loads(text))
            except json.JSONDecodeError:
                pass
        return [text]
    if isinstance(value, dict):
        return [value]
    return list(value)


def _is_missing(value: Any) -> bool:
    return (
        value is None
        or (isinstance(value, float) and math.isnan(value))
        or (isinstance(value, str) and not value.strip())
    )


def normalise_tool_name(name: Any) -> str:
    return re.split(r"[./:]|__", str(name or ""))[-1].strip().lower()


def _call_name(call: Any) -> str | None:
    if isinstance(call, dict):
        return call.get("name") or (call.get("function") or {}).get("name")
    return getattr(call, "name", None)


def _call_arguments(call: Any) -> Any:
    args = call.get("arguments") if isinstance(call, dict) else getattr(call, "arguments", None)
    if args is None and isinstance(call, dict):
        args = (call.get("function") or {}).get("arguments")
    if isinstance(args, str):
        try:
            return json.loads(args)
        except json.JSONDecodeError:
            return args
    return args


def _find_key(value: Any, key: str) -> Any:
    if isinstance(value, dict):
        if key in value:
            return value[key]
        for v in value.values():
            found = _find_key(v, key)
            if found is not None:
                return found
    elif isinstance(value, list):
        for v in value:
            found = _find_key(v, key)
            if found is not None:
                return found
    return None


def documents_in_tool_calls(tool_calls: Any, tools: tuple[str, ...] = DOCUMENT_TOOLS) -> list[str]:
    wanted = {normalise_tool_name(t) for t in tools}
    docs = []
    for call in as_list(tool_calls):
        if normalise_tool_name(_call_name(call)) in wanted:
            md = _find_key(_call_arguments(call), "markdown")
            if isinstance(md, str) and md.strip():
                docs.append(md)
    return docs


_FENCE = re.compile(r"^(`{3,}|~{3,})\s*([\w+-]*)\s*$")


def _front_matter_bounds(lines: list[str]) -> tuple[int, int] | None:
    for i, line in enumerate(lines):
        if line.strip() != "---":
            continue
        for j in range(i + 1, min(i + 40, len(lines))):
            if lines[j].strip() == "---":
                if any(re.match(r"\s*doc_id\s*:", line) for line in lines[i + 1:j]):
                    return i, j
                break
    return None


def extract_markdown_document(text: Any) -> str | None:
    if not isinstance(text, str) or "doc_id" not in text:
        return None
    lines = text.replace("\r\n", "\n").split("\n")
    bounds = _front_matter_bounds(lines)
    if not bounds:
        return None
    start, fm_end = bounds
    wrapper = None
    k = start - 1
    while k >= 0 and not lines[k].strip():
        k -= 1
    if k >= 0:
        match = _FENCE.match(lines[k].strip())
        if match and match.group(2).lower() in ("", "markdown", "md"):
            wrapper = match.group(1)
    out = lines[start:fm_end + 1]
    inner = None
    for line in lines[fm_end + 1:]:
        stripped = line.strip()
        match = _FENCE.match(stripped)
        if inner:
            out.append(line)
            if match and not match.group(2) and match.group(1)[0] == inner[0] and len(match.group(1)) >= len(inner):
                inner = None
            continue
        if match:
            fence, lang = match.group(1), match.group(2)
            if wrapper and not lang and fence[0] == wrapper[0] and len(fence) >= len(wrapper):
                break
            inner = fence
            out.append(line)
            continue
        if wrapper is None and stripped in ("---", "***", "___"):
            break
        out.append(line)
    return "\n".join(out).strip() + "\n"


def find_document(response: Any, tool_calls: Any = None) -> tuple[str | None, str | None]:
    submitted = documents_in_tool_calls(tool_calls, ("submitProposal",))
    if submitted:
        return submitted[-1], "submitProposal"
    doc = extract_markdown_document(response)
    if doc:
        return doc, "response"
    validated = documents_in_tool_calls(tool_calls, ("validateDocument",))
    if validated:
        return validated[-1], "validateDocument"
    return None, None


def _text(response: Any) -> str:
    return "" if _is_missing(response) else str(response)


def _na(name: str, reason: str) -> dict[str, Any]:
    return {name: None, f"{name}_result": "n/a", f"{name}_reason": reason}


def _scored(name: str, score: float, threshold: float, reason: str, **details: Any) -> dict[str, Any]:
    out = {
        name: round(score, 4),
        f"{name}_result": "pass" if score >= threshold else "fail",
        f"{name}_threshold": threshold,
        f"{name}_reason": reason,
    }
    out.update({f"{name}_{key}": value for key, value in details.items()})
    return out


class TemplateComplianceEvaluator:
    """Inherited draft-only standard validation, not a replacement LLM judge."""

    def __init__(self, threshold: float = 1.0):
        self.threshold = threshold

    def __call__(self, *, response=None, tool_calls=None, category=None) -> dict[str, Any]:
        name = "template_compliance"
        doc, source = find_document(_text(response), tool_calls)
        if not _is_missing(category) and category != "draft":
            return _na(name, f"not a draft row ({category})")
        if doc is None:
            if _is_missing(category):
                return _na(name, "no document in the response")
            return _scored(
                name, 0.0, self.threshold, "no document found in the response or tool calls",
                errors="no document", source=None,
            )
        result = validate_document(doc)
        reason = "valid" if result.valid else f"{len(result.errors)} error(s)"
        return _scored(
            name, 1.0 if result.valid else 0.0, self.threshold, reason,
            errors="; ".join(result.errors), warnings="; ".join(result.warnings), source=source,
        )
