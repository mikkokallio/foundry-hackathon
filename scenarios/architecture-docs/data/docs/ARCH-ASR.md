---
doc_id: ARCH-ASR
title: Asset Registry – architecture description
system_id: SYS-005
owner_team: Installed Base Data
status: published
version: "3.0"
last_reviewed: 2026-02-10
classification: Internal
---

# Asset Registry

## Purpose

The Asset Registry is the master for the installed base: every delivered machine, its configuration, location, current owner and service contract.

## Context

The Asset Registry provides equipment master data to Service Order Management (INT-004) through the Integration Platform, the customer equipment list to the Customer Portal (INT-012) and a daily snapshot to the Analytics Lakehouse (INT-017). A diagram is maintained in the team's drawing tool.

## Components

- Registry database on Azure SQL.
- Change feed functions that publish equipment changes to the Integration Platform.

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-004 | Service Order Management | outbound | API | active |
| INT-012 | Customer Portal | outbound | API | active |
| INT-017 | Analytics Lakehouse | outbound | batch | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-003 Installed Base | produces | Internal |

## Security and access

- Read access through APIs only; no direct database access for consumers.
- Customer Portal calls are scoped to the signed-in customer's equipment.

## Operations

- Monitoring: Azure Monitor alerts on change feed failures.
- Support: Installed Base Data, business hours.

## Known limitations

- Ownership changes after resale are often reported late.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-02-10 | 3.0 | Moved to Azure SQL and change feed | Installed Base Data |
