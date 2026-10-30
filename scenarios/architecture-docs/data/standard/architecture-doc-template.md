---
doc_id: ARCH-XXX
title: <System name> – architecture description
system_id: SYS-NNN
owner_team: <Owner team from inventory>
status: draft
version: "0.1"
last_reviewed: YYYY-MM-DD
classification: Internal
---

# <System name>

## Purpose

<What the system does and for whom, in 2–4 sentences.>

## Context

```mermaid
flowchart LR
    THIS["<System name> (SYS-NNN)"]:::this
    OTHER["<Neighbour system>"]
    OTHER -- "INT-NNN" --> THIS
    classDef this fill:#0078D4,color:#ffffff
```

## Components

- <Component> – <role, hosting>

## Interfaces

| ID | Counterpart | Direction | Pattern | Status |
|---|---|---|---|---|
| INT-NNN | <System> | inbound / outbound / via | API / event / batch / file | active |

## Data

| Data product | Role | Classification |
|---|---|---|
| DP-NNN <name> | produces / consumes | Internal |

## Security and access

- Authentication: <…>
- Authorisation: <…>
- Network exposure: <…>
- Secrets: stored in <…>; never in documentation.

## Operations

- Monitoring: <…>
- Support: <team, hours>

## Known limitations

- <…>

## Change log

| Date | Version | Change | Author |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | First draft | <person / team / agent> |
