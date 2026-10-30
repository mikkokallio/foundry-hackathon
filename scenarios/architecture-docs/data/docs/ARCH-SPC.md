---
doc_id: ARCH-SPC
title: Spare Parts Catalogue – architecture description
system_id: SYS-004
owner_team: Aftermarket IT
status: published
version: "1.4"
last_reviewed: 2025-12-01
classification: Internal
---

# Spare Parts Catalogue

## Purpose

The Spare Parts Catalogue lets technicians, customers and sales find the right spare part for a given machine, with compatibility, price and availability.

## Context

```mermaid
flowchart LR
    SYS004["Spare Parts Catalogue"]:::this
    SYS003["Field Service Mobile"]
    SYS004 -- "INT-008" --> SYS003
    SYS008["ERP Core"]
    SYS008 -- "INT-009 via Integration Platform" --> SYS004
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Catalogue web application on Azure App Service.
- Catalogue database on Azure SQL with nightly compatibility rebuild.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-008 | Field Service Mobile | outbound | API | active |
| INT-009 | ERP Core | inbound | batch | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-004 Spare Parts Availability | produces | Internal |

## Security and access

- Internal users sign in with Entra ID; customers reach the catalogue only through the Customer Portal.
- Database access with managed identity only.

## Operations

- Monitoring: Application Insights availability tests every 5 minutes.
- Support: Aftermarket IT, business hours.

## Known limitations

- Compatibility data for machines older than 1995 is incomplete.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2025-12-01 | 1.4 | Hourly price updates | Aftermarket IT |
