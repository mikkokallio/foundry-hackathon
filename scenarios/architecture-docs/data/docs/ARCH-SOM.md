---
doc_id: ARCH-SOM
title: Service Order Management – architecture description
system_id: SYS-002
owner_team: Service Operations IT
status: published
version: "1.3"
last_reviewed: 2025-03-14
classification: Confidential
---

# Service Order Management

## Purpose

Service Order Management is the system of record for service requests, work orders and technician scheduling. Service coordinators plan work here and technicians receive their assignments through Field Service Mobile.

## Context

```mermaid
flowchart LR
    SYS002["Service Order Management"]:::this
    SYS006["Predictive Maintenance Models"]
    SYS006 -- "INT-003 via Integration Platform" --> SYS002
    SYS005["Asset Registry"]
    SYS005 -- "INT-004 via Integration Platform" --> SYS002
    SYS003["Field Service Mobile"]
    SYS002 -- "INT-005" --> SYS003
    SYS003 -- "INT-006" --> SYS002
    SYS013["Legacy Service Planner"]
    SYS002 -- "INT-007" --> SYS013
    SYS008["ERP Core"]
    SYS002 -- "INT-010 via Integration Platform" --> SYS008
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Field service platform (SaaS) – work orders, scheduling, service history.
- Extension functions – Azure Functions for integrations that the SaaS cannot do natively.
- Planning export – nightly file export to the Legacy Service Planner for capacity planning.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-003 | Predictive Maintenance Models | inbound | API | active |
| INT-004 | Asset Registry | inbound | API | active |
| INT-005 | Field Service Mobile | outbound | API | active |
| INT-006 | Field Service Mobile | inbound | API | active |
| INT-007 | Legacy Service Planner | outbound | file | active |
| INT-010 | ERP Core | outbound | event | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-002 Service Order History | produces | Confidential |
| DP-003 Installed Base | consumes | Internal |
| DP-001 Asset Health Score | consumes | Internal |

## Security and access

- Users sign in with Entra ID single sign-on; roles are managed in the SaaS platform.
- Integrations call the platform through the Integration Platform with OAuth client credentials.
- Customer names and site addresses are Confidential.

## Operations

- Monitoring: SaaS vendor status page and Integration Platform alerts.
- Support: Service Operations IT, business hours.

## Known limitations

- Capacity planning depends on the nightly export to the Legacy Service Planner.
- No real-time view of asset health; recommendations arrive hourly.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2025-03-14 | 1.3 | Added maintenance recommendations INT-003 | Service Operations IT |
| 2024-10-02 | 1.2 | Billing via Integration Platform | Service Operations IT |
