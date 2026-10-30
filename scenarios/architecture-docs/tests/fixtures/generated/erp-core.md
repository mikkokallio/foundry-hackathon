---
doc_id: ARCH-ERP
title: ERP Core – architecture description
system_id: SYS-008
status: draft
version: "0.1"
last_reviewed: 2026-10-23
---

# ERP Core

## Purpose

ERP Core is the enterprise resource planning system for finance, procurement, inventory, sales orders and invoicing.

## Context

```mermaid
flowchart LR
    SYS008["ERP Core"]:::this
    SYS004["Spare Parts Catalogue"]
    SYS008 -- "INT-009 via Integration Platform" --> SYS004
    SYS002["Service Order Management"]
    SYS002 -- "INT-010 via Integration Platform" --> SYS008
    SYS013["Legacy Service Planner"]
    SYS013 -- "INT-020" --> SYS008
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- On-premises ERP with private connectivity to Azure.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-009 | Spare Parts Catalogue | outbound | batch | active |
| INT-010 | Service Order Management | inbound | event | active |
| INT-020 | Legacy Service Planner | inbound | file | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-004 Spare Parts Availability | produces | Internal |

## Security and access

- Access managed by the ERP Competence Center; integrations only through the Integration Platform.

## Operations

- Support: ERP Competence Center, 24/7 for month-end closing.

## Known limitations

- No real-time events for inventory changes.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-10-23 | 0.1 | Generated from a spreadsheet export | coding-agent skill "erp-doc" |
