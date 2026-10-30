---
doc_id: ARCH-IPAAS
title: Integration Platform – architecture description
system_id: SYS-010
owner_team: Integration Services
status: published
version: "2.1"
last_reviewed: 2024-11-30
classification: Internal
---

# Integration Platform

## Purpose

The Integration Platform connects business systems through APIs, events and scheduled transfers so that systems do not integrate point to point.

## Context

```mermaid
flowchart LR
    SYS010["Integration Platform"]:::this
    SYS006["Predictive Maintenance Models"]
    SYS002["Service Order Management"]
    SYS006 -- "INT-003" --> SYS002
    SYS005["Asset Registry"]
    SYS005 -- "INT-004" --> SYS002
    SYS008["ERP Core"]
    SYS004["Spare Parts Catalogue"]
    SYS008 -- "INT-009" --> SYS004
    SYS002 -- "INT-010" --> SYS008
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- iPaaS runtime with API, event and batch connectors.
- Shared monitoring dashboard for all integrations.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-003 | Predictive Maintenance Models → Service Order Management | via | API | active |
| INT-004 | Asset Registry → Service Order Management | via | API | active |
| INT-009 | ERP Core → Spare Parts Catalogue | via | batch | active |
| INT-010 | Service Order Management → ERP Core | via | event | active |

## Data

The Integration Platform does not own data products; it transports them.

## Security and access

- Each integration uses its own client credentials stored in the platform's vault.
- Inbound APIs require OAuth tokens; IP restrictions for on-premises connectors.

## Operations

- Monitoring: platform dashboard; alerts to Integration Services on failed runs.
- Support: Integration Services, 24/7 for critical flows.

## Known limitations

- Event replay is limited to 3 days.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2024-11-30 | 2.1 | Added service billing INT-010 | Integration Services |
