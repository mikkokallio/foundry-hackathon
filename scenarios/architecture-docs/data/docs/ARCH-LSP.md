---
doc_id: ARCH-LSP
title: Legacy Service Planner – architecture description
system_id: SYS-013
owner_team: Service Operations IT
status: published
version: "1.2"
last_reviewed: 2025-09-01
classification: Internal
---

# Legacy Service Planner

## Purpose

The Legacy Service Planner calculates technician capacity per region from open work orders and sends resource costs to ERP Core.

## Context

```mermaid
flowchart LR
    SYS013["Legacy Service Planner"]:::this
    SYS002["Service Order Management"]
    SYS002 -- "INT-007" --> SYS013
    SYS008["ERP Core"]
    SYS013 -- "INT-020" --> SYS008
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Planning application on an on-premises application server.
- Nightly batch jobs.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-007 | Service Order Management | inbound | file | active |
| INT-020 | ERP Core | outbound | file | active |

## Data

No data products.

## Security and access

- Windows authentication; access restricted to service planners.

## Operations

- Support: Service Operations IT, business hours.

## Known limitations

- Runs only nightly; no intraday re-planning.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2025-09-01 | 1.2 | Review, no changes | Service Operations IT |
