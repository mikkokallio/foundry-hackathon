---
doc_id: ARCH-RDA
title: Remote Diagnostics Agent – architecture description
system_id: SYS-012
owner_team: Connected Services Platform
status: draft
version: "0.1"
last_reviewed: 2026-10-22
classification: Internal
---

# Remote Diagnostics Agent

## Purpose

The Remote Diagnostics Agent analyses recent telemetry for a reported fault and attaches diagnostic findings and suggested checks to the service order before the technician leaves for the site. It is in pilot in two service regions.

## Context

```mermaid
flowchart LR
    SYS012["Remote Diagnostics Agent"]:::this
    SYS002["Service Order Management"]
    SYS012 -- "INT-015 (planned)" -.-> SYS002
    SYS001["Equipment Telemetry Hub"]
    SYS001 -- "INT-016 (planned)" -.-> SYS012
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Foundry prompt agent with tools for telemetry lookup and service order updates.
- Tools exposed as MCP servers through the AI gateway.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-015 | Service Order Management | outbound | API | planned |
| INT-016 | Equipment Telemetry Hub | inbound | API | planned |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-005 Telemetry Aggregates | consumes | Internal |

## Security and access

- The agent runs with its own agent identity; tool calls go through the AI gateway.
- Service order updates require a technician's approval in the pilot.

## Operations

- Monitoring: Foundry traces and evaluation runs; gateway token metrics per region.
- Diagnostics API key used in the pilot: api_key=rda-test-9f8e7d6c5b4a3f2e1d0c
- Support: Connected Services Platform, business hours.

## Known limitations

- Pilot covers drive motors only.
