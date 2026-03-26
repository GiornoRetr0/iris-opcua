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

## Modifying Existing Pipelines (Phase 3)

The "Edit Pipeline" feature is a single flow: user opens an existing pipeline, browses the address space, selects new nodes. The system resolves what changed and classifies the result into one of three cases.

### How It Works

1. **User opens Edit Pipeline UI** for an existing pipeline (e.g., "BuildingClimate" with columns Temperature, Humidity and row sources AC1, AC2).
2. **User browses the tree** and selects new nodes.
3. **System groups new nodes by parent** and compares against the existing pipeline.

### Classification: What Did the User Add?

For each new parent group, the system checks column overlap with the existing pipeline:

**Case A: New row source with matching columns (full or partial overlap)**

User selects AC3's children. AC3 has Temperature, Humidity (matching existing columns).

1. AC3 is added as a new row source.
2. System **browses AC3 on the OPC UA server** to discover which existing columns it has.
3. Matching columns → reads them. Missing columns → NULL.
4. Update `^OPCUA.RowSource`, restart service. No DataSource class recompile needed.

**Case B: New column from an existing or new row source (partial overlap)**

User selects PowerConsumption from AC2. AC2 is already a row source, but PowerConsumption is a new column.

1. PowerConsumption is added to the DataSource class as a new property.
2. System **browses ALL existing row sources** (AC1, AC2) for a child named PowerConsumption.
3. Found → update column mask to include it, store the absolute node ID. Not found → mask stays 0 (NULL).
4. Recompile DataSource class, update `^OPCUA.RowSource` with new masks, restart service.

Result:

| NodePath | Temperature | Humidity | PowerConsumption |
|---|---|---|---|
| .../AC1 | 22.5 | 45 | 1200 |
| .../AC2 | 23.1 | 50 | 1350 |

Cases A and B can happen together — e.g., user adds AC3 which has Temperature, Humidity, and Pressure. AC3 is a new row source (Case A), Pressure is a new column (Case B). Both resolved in one operation.

**Case C: No column overlap — wrong pipeline**

User selects SA1 (child of Objects). SA1 has zero overlap with Temperature, Humidity. Adding it would produce:

| NodePath | Temperature | Humidity | SA1 |
|---|---|---|---|
| .../AC1 | 22.5 | 45 | NULL |
| .../AC2 | 23.1 | 50 | NULL |
| Objects | NULL | NULL | 12.3 |

Every row is mostly NULL — this makes no sense as one table.

System detects zero column overlap and **blocks the edit** with a message:

> "SA1 (from Objects) has no matching columns with this pipeline. This node belongs in a separate pipeline."
>
> **[Create New Pipeline]** — redirects to the wizard with SA1 pre-selected.

### The Core Operation: Browse & Resolve

Both Case A and Case B require the same underlying operation:

**Browse a parent node's children on the OPC UA server, match them against the pipeline's column list.**

- Adding a row source → browse the new parent, match its children against existing columns
- Adding a column → browse all existing row source parents, match their children against the new column name

This browse happens at edit time (not at runtime). The results are stored in `^OPCUA.RowSource` as column masks and absolute node IDs. The service reads these at startup.

### Backend Operations for Edit Pipeline

Regardless of case, the edit pipeline endpoint performs:

1. **Connect** to OPC UA server.
2. **Browse** affected parent nodes to discover/verify child nodes.
3. **Update DataSource class** if new columns are added (recompile).
4. **Update `^OPCUA.RowSource`** with new row sources and/or updated column masks.
5. **Restart the service** so it reinitializes with the new combined specification.

### UI Flow

1. Pipeline dashboard → click Edit on a pipeline → opens Edit Pipeline view.
2. Shows current schema (columns) and row sources. Tree browser on the left.
3. User selects new nodes in the tree. System shows live preview:
   - "AC3 will be added as a new row source (Temperature, Humidity match)"
   - "PowerConsumption will be added as a new column (found in AC1, AC2; not found in AC3 → NULL)"
   - Or warning: "SA1 has no matching columns — cannot add to this pipeline"
4. User confirms → system applies changes → service restarts.

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
