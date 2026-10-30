---
doc_id: ARCH-FSM
title: Field Service Mobile – architecture description
system_id: SYS-003
owner_team: Service Operations IT
status: published
version: "1.1"
last_reviewed: 2026-05-20
classification: Internal
---

# Field Service Mobile

## Purpose

Field Service Mobile is the technicians' app for receiving work orders, looking up spare parts on site and reporting completed work, time and parts used.

## Context

```mermaid
flowchart LR
    SYS003["Field Service Mobile"]:::this
    SYS002["Service Order Management"]
    SYS002 -- "INT-005" --> SYS003
    SYS003 -- "INT-006" --> SYS002
    SYS004["Spare Parts Catalogue"]
    SYS004 -- "INT-008" --> SYS003
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Mobile app for iOS and Android, distributed through the company app store.
- Backend for frontend on Azure App Service that caches work orders for offline use.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-005 | Service Order Management | inbound | API | active |
| INT-006 | Service Order Management | outbound | API | active |
| INT-008 | Spare Parts Catalogue | inbound | API | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-004 Spare Parts Availability | consumes | Internal |

## Operations

- Monitoring: Application Insights on the backend; crash reporting in the app.
- Support: Service Operations IT, extended hours 06–22.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-05-20 | 1.1 | Offline cache for work orders | Service Operations IT |
| 2025-08-30 | 1.0 | First version | Service Operations IT |
