# {{organization_name}} – Architecture documentation standard (v2.1)

> Synthetic material for this lab. The organization name is chosen by the deployer; all systems, people and business facts described here are fictional.

Every system in the system inventory that is **active** or in **pilot** must have one published architecture description in the shared documentation store. Documents are reviewed at least once every **12 months**.

## 1. Front matter

Every document starts with a YAML front matter block containing these fields:

| Field | Format | Notes |
|---|---|---|
| `doc_id` | `ARCH-XXX` (2–6 capital letters) | Stable identifier; never reused |
| `title` | text | "<System name> – architecture description" |
| `system_id` | `SYS-NNN` | Must exist in the system inventory |
| `owner_team` | text | Must match the owner team in the system inventory |
| `status` | `draft`, `published` or `archived` | Documents of decommissioned systems are `archived` |
| `version` | `major.minor`, e.g. `1.4` | Minor for content updates, major for re-architecture |
| `last_reviewed` | `YYYY-MM-DD` | Date of the latest review |
| `classification` | `Public`, `Internal` or `Confidential` | Highest classification of the content |

## 2. Sections

Use these level-2 headings, in this order. Sections may be short, but none may be missing.

1. **Purpose** – what the system does and for whom, in 2–4 sentences.
2. **Context** – the system and its neighbours. Must contain a Mermaid diagram (` ```mermaid ` block) generated from the interface inventory.
3. **Components** – main building blocks and hosting.
4. **Interfaces** – a table with the columns `ID | Counterpart | Direction | Pattern | Status`. `ID` uses the inventory interface ID (`INT-NNN`). List every **active** interface where the system is source, target or the integration route (`via`). Planned interfaces may be listed with status `planned`. Decommissioned interfaces are removed from the table and mentioned in the change log instead.
5. **Data** – data products produced or consumed (`DP-NNN`), with their classification from the inventory.
6. **Security and access** – authentication, authorisation, network exposure and secrets handling. Never include credentials, keys or connection strings.
7. **Operations** – monitoring, support model, SLAs.
8. **Known limitations** – honest list of current limitations and technical debt.
9. **Change log** – table or list: date, version, change, author (person, team or agent).

## 3. Diagrams

Context diagrams use Mermaid `flowchart LR`. Nodes are systems (use the system name; the system ID may be added in brackets), edges are interfaces labelled with the interface ID. The documented system is highlighted with a class or a different shape.

## 4. Process

1. Anyone (person, team or AI agent) may submit a **proposal** for a new or updated document.
2. Proposals are validated automatically against this standard. Proposals that fail validation are stored as `needs-changes`.
3. The architecture librarian reviews `pending-review` proposals and publishes them. AI agents never publish directly.
4. Proposals created by AI agents state `author_type: agent` (or `coding-agent`) and the tool that produced them.

## 5. Things that are always wrong

- Credentials, API keys, passwords or connection strings anywhere in a document.
- Interfaces that are decommissioned shown as active.
- An owner team that does not match the inventory.
