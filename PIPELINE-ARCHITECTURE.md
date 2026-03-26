# Pipeline Architecture v2 — Unified Row-Source Model

## Problem with v1

In v1, each selected OPC UA node becomes a column in the DataSource table. Selecting Temperature from AC1 and AC2 produces:

| Temperature_AC1 | Humidity_AC1 | Temperature_AC2 | Humidity_AC2 |
|---|---|---|---|
| 22.5 | 45 | 23.1 | 50 |

This doesn't scale. Adding AC3 means adding more columns, modifying the DataSource class. Devices with identical structure produce redundant schemas.

## v2 Unified Model

There is no "flat mode" vs "device mode." Every pipeline uses one unified model:

**columns (attributes) x row sources (parent nodes) + NodePath column**

| NodePath | Temperature | Humidity |
|---|---|---|
| Objects/Building/AC1 | 22.5 | 45 |
| Objects/Building/AC2 | 23.1 | 50 |

- **Columns** = the attribute names (child nodes selected by the user)
- **Row sources** = the parent nodes of those children (the "devices")
- **NodePath** = always present, identifies which row source produced the row

A "flat" selection (e.g., SA1, SA2, VT5 under Objects) is the same model — just one row source:

| NodePath | SA1 | SA2 | VT5 | PRNO | PROG |
|---|---|---|---|---|---|
| Objects/Objects | 12.3 | 45.6 | 7.8 | 100 | 2 |

## Pipeline Data Model

```
Pipeline {
  name: string
  columns: [
    { name: "Temperature", browseName: "Temperature", type: "Double" },
    { name: "Humidity", browseName: "Humidity", type: "Double" }
  ]
  rowSources: [
    { nodeId: "ns=2;s=AC1", path: "Objects/Building/AC1" },
    { nodeId: "ns=2;s=AC2", path: "Objects/Building/AC2" }
  ]
}
```

Per poll cycle, the service reads: for each rowSource x column, read the child node. Write one row per row source.

## Core Algorithm

### Step 1: Selection & Auto-Expand

When a user checks nodes in the tree:

- If a node **has children** (e.g., ServerStatus): auto-expand and select all children as columns. The parent's own value is also included as a column — having children doesn't mean the parent's value is useless. User can uncheck any columns they don't want.
- If a node **is a leaf variable** (e.g., SA1): selected directly as a column.

### Step 2: Group by Parent

All selected leaf nodes are grouped by their parent node.

Example: User checks AC1 and SA1, SA2.
- Group A (parent: AC1): Temperature, Humidity (auto-expanded from AC1)
- Group B (parent: Objects): SA1, SA2

### Step 3: Compare Schemas & Merge

Compare column schemas across groups:

- **Schemas match** → merge into one pipeline with multiple row sources.
- **Schemas don't match** → separate pipelines.

The matching rule is **"matching schema = same pipeline"**, not "same parent = same pipeline."

Example: User checks AC1 and AC2. Both auto-expand to Temperature, Humidity. Schemas match → one pipeline, two row sources.

### Step 4: Wizard Confirmation

If multiple pipelines result, wizard shows:

> "You selected nodes from 2 different sources with different schemas. This will create 2 pipelines:"
> - Pipeline 1: SA1, SA2 (from Objects)
> - Pipeline 2: Temperature, Humidity (from AC1, AC2)

## Modifying Existing Pipelines

### Adding a New Row Source (Device)

User selects nodes from a new parent (e.g., AC3's Temperature, Humidity). System compares against existing pipeline schema:

- **Exact match** → AC3 added as a new row source. New rows appear in the table.
- **Partial overlap** → see "Adding New Attributes" below.
- **No match** → new pipeline created.

### Adding New Attributes (Columns)

User adds PowerConsumption from AC2 to an existing pipeline that has Temperature, Humidity with row sources AC1 and AC2.

1. PowerConsumption column is added to the schema.
2. System browses ALL existing row sources (AC1, AC2) for a child with the same browse name.
3. If found → reads it. If not found → NULL.

Result:

| NodePath | Temperature | Humidity | PowerConsumption |
|---|---|---|---|
| .../AC1 | 22.5 | 45 | 1200 |
| .../AC2 | 23.1 | 50 | 1350 |

The assumption: same-structure devices share the same children. The system verifies by browsing — no blind assumptions.

## Edge Cases

### Nodes from unrelated parents

User checks SA1, SA2 (from Objects) and Temperature, Humidity (from AC1) in one session. Forcing into one table:

| NodePath | SA1 | SA2 | Temperature | Humidity |
|---|---|---|---|---|
| Objects | 12.3 | 45.6 | NULL | NULL |
| .../AC1 | NULL | NULL | 22.5 | 45 |

Every row is half-NULL. System detects non-matching schemas → creates two separate pipelines.

### Parent node checked directly

User checks ServerStatus (which has children BuildInfo, State, CurrentTime, etc.):

- ServerStatus's own value is added as a column.
- All children are auto-selected as additional columns.
- User can uncheck any they don't want.
- ServerStatus (the node itself) becomes the row source.

| NodePath | ServerStatus | BuildInfo | State | CurrentTime | StartTime | SecondsTillShutdown |
|---|---|---|---|---|---|---|
| .../Server | {blob} | {...} | 0 | 2026-03-24T... | 2026-03-24T... | 0 |

### Sibling devices checked directly

User checks AC1 and AC2 (both children of BuildingAutomation, both with same child structure):

1. Auto-expand AC1 → Temperature, Humidity (parent: AC1)
2. Auto-expand AC2 → Temperature, Humidity (parent: AC2)
3. Schemas match → one pipeline, two row sources

## Architectural Impact on Existing Code

### DataSource Class Changes

Current: each property has a hardcoded `OPCUANODENAME = "ns=2;s=AC1.Temperature"` — one absolute node ID per column.

New: the DataSource class defines the **schema only** (column names + types + NodePath). The node-to-device mapping lives separately — a configuration store (global or table) that the service reads at runtime to resolve "for each row source, which node IDs to read for each column."

### Service Changes

Current: service reads a fixed list of node IDs and writes one row per poll.

New: service iterates row sources, reads each row source's attributes, writes one row per row source per poll cycle. The number of rows per poll = number of row sources.

### Wizard Changes

Current: user checks nodes → one pipeline, one column per node.

New: user checks nodes → system groups by parent, compares schemas, may produce one or multiple pipelines. Wizard shows grouping for confirmation. Supports adding to existing pipelines.
