---
doc_id: ARCH-TEL
title: Equipment Telemetry Hub – architecture description
system_id: SYS-001
owner_team: Connected Services Platform
status: published
version: "2.3"
last_reviewed: 2026-09-15
classification: Internal
---

# Equipment Telemetry Hub

## Purpose

The Equipment Telemetry Hub receives sensor telemetry from connected machines, validates and normalises it, and streams it to the Analytics Lakehouse and the Predictive Maintenance Models. It is the single entry point for equipment data from the field.

## Context

```mermaid
flowchart LR
    SYS001["Equipment Telemetry Hub"]:::this
    SYS009["Analytics Lakehouse"]
    SYS001 -- "INT-001" --> SYS009
    SYS006["Predictive Maintenance Models"]
    SYS001 -- "INT-002" --> SYS006
    SYS012["Remote Diagnostics Agent"]
    SYS001 -- "INT-016 (planned)" -.-> SYS012
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- Device gateway – IoT Hub with per-device identities and X.509 certificates.
- Stream normaliser – Azure Functions that map vendor payloads to the common telemetry schema.
- Event backbone – Event Hubs namespace with one hub per consumer group.
- Aggregator – stream job producing 5-minute windows (data product DP-005).

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-001 | Analytics Lakehouse | outbound | event stream | active |
| INT-002 | Predictive Maintenance Models | outbound | event stream | active |
| INT-016 | Remote Diagnostics Agent | outbound | API | planned |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-005 Telemetry Aggregates | produces | Internal |

## Security and access

- Devices authenticate with X.509 certificates issued per device; certificates are rotated yearly.
- Consumers read Event Hubs with managed identities and the Azure Event Hubs Data Receiver role.
- No public consumer endpoints; ingestion endpoint is public but device-authenticated.
- Secrets and certificates are stored in Key Vault.

## Operations

- Monitoring: Azure Monitor alerts on ingestion lag above 2 minutes and dead-letter growth.
- Support: Connected Services Platform, business hours; P1 incidents 24/7 via the service desk.

## Known limitations

- Older machine controllers send data only every 15 minutes, so their aggregates are sparse.
- Replay of more than 7 days of raw telemetry requires a manual restore from cold storage.

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-09-15 | 2.3 | Added planned diagnostics interface INT-016 | Connected Services Platform |
| 2026-03-02 | 2.2 | Moved aggregates to 5-minute windows | Connected Services Platform |
| 2025-06-11 | 2.0 | Re-architecture on Event Hubs | Connected Services Platform |
