# PRD — Decoupling Schema from Device Binding

**Branch:** `feature/schema-device-decoupling`
**Status:** Draft for review
**Date:** 2026-07-30
**Source:** Supervisor report (post-meeting, ~June 2026) + meeting notes

---

## 1. Background

The supervisor's report defines two reusable building blocks ("Bausteine") plus a usage pattern:

| | Requirement | Meaning |
|---|---|---|
| **Baustein 1** | **Schema** | Generate a structure describing one device type, reusable across N identical devices. Frontend can mostly do this today. Generated under `OPCUA.DS.<DeviceStructureClass>`. |
| **Baustein 2** | **Device → Schema assignment** | Binding a device to a schema is essentially *just the OPC UA nodepath*. Because schema property names (or their `OPCUANODENAME` parameters) match the OPC UA node names, the binding can be resolved **dynamically**. |
| **Usage** | **Generic Business Service** | A simple Setting holds the schema class name. The setting is enriched so the Production Configuration UI shows a **dropdown** of available schema classes — discoverable because they share a **common superclass**. |

Meeting note (independently recorded): *"Don't create business services immediately. Split the functionality of schema creation and business service/connection building."* — this is the same requirement, stated as the architectural consequence: Baustein 1 must be usable without Baustein 2 existing.

### Goal in one sentence

Turn a pipeline from *"one monolithic wizard-generated artifact"* into *"a reusable schema class + a list of device nodepaths, wired together by an ordinary IRIS production setting."*

---

## 2. Current State

### 2.1 Schema creation and service creation are coupled

`OPCUA.REST.DeployService.DeployV2()` ([DeployService.cls:210](image-iris/src/OPCUA/REST/DeployService.cls#L210)) does all of the following in one non-resumable transaction:

1. Validates columns + rowSources
2. Generates `%SerialObject` classes for nested folders → `GenerateSerialClasses()`
3. Generates and compiles the DataSource class → `GenerateDataSourceTextV2()`
4. Writes device binding metadata → `StoreRowSourceMetadata()` → `^OPCUA.RowSource`
5. Ensures the shared production exists → `EnsureProductionExists()`
6. Adds a business service item → `AddServiceItem()`
7. Starts/updates the production → `StartOrUpdateProduction()`

There is **no way to do step 3 alone**. A schema cannot exist without a running pipeline.

### 2.2 Device binding is frozen at deploy time

`StoreRowSourceMetadata()` ([DeployService.cls:496](image-iris/src/OPCUA/REST/DeployService.cls#L496)) writes:

```
^OPCUA.RowSource(className) = $LB(rsCount, colCount, rsList, columnPaths, nestingSpec)
```

where each entry of `rsList` is:

```
$LB(path, nodeNs, nodeId, nodeIdType, columnMask, absNodeRefs)
                                                  ^^^^^^^^^^^
                                     absolute ns+nodeId for EVERY column of THIS device
```

Consequences:
- Adding a device requires re-running the wizard so it can browse and capture that device's absolute node IDs.
- The device list is invisible in the IRIS Management Portal — it lives in a `$LB`-encoded global.
- `columnMask` must be precomputed to record which columns each device lacks.

### 2.3 `OPCUANODENAME` is written but unused at runtime (v2)

`GenerateDataSourceTextV2()` sets `OPCUANODENAME` on every generated property ([DeployService.cls:421](image-iris/src/OPCUA/REST/DeployService.cls#L421)), and `OPCUA.DataSource.Projection` faithfully carries it into `^OPCUA.DataSource(className)` as position 4 of each spec entry ([Projection.cls:189](image-iris/src/OPCUA/DataSource/Projection.cls#L189)):

```
specEntry = $LB(entryType, propertyPath, namespace, nodeName, attributeId)
```

But `TCPPollingRowSourceService.OnInit()` **overwrites position 4 with the stored absolute node ID** ([TCPPollingRowSourceService.cls:158](image-iris/src/OPCUA/Service/TCPPollingRowSourceService.cls#L158)):

```objectscript
set tNewEntry = $LB(2, $LI(tColEntry,2)_"_RS"_iRS, tAbsNS, tAbsNodeId, $LI(tColEntry,5))
                                                          ^^^^^^^^^^^ replaces nodeName
```

**This is the key enabler.** The name-based information the supervisor wants to resolve against is *already generated and already persisted* — it is simply discarded in favour of the frozen absolute IDs. The v1 declarative path (`TCPPollingService`, Examples, Tests) does use `OPCUANODENAME` for real. So the mechanism exists and is proven; v2 just bypasses it.

### 2.4 `DataSourceClass` is a plain string setting

[Common.cls:7](image-iris/src/OPCUA/Adapter/Common.cls#L7):

```objectscript
Parameter SETTINGS = "URL:Connection,...,DataSourceClass:Data,...";
```

No selector → free-text field in the Production Configuration UI. Typos surface only at runtime as `"No row source metadata found for ..."`.

### 2.5 There is no device-list setting at all

The service knows *which* schema to use (`DataSourceClass`) but never *which devices* — that is implied by the global. So a generic, hand-configurable service is currently impossible.

---

## 3. Target Architecture

```
┌─ Baustein 1: SCHEMA ────────────────────────────────────────┐
│  OPCUA.DS.AirConditioner  extends OPCUA.DataSource.DeviceSchema │
│    Temperature   As %Double   (OPCUANODENAME = "Temperature")   │
│    Humidity      As %Double   (OPCUANODENAME = "Humidity")      │
│    FanSpeed      As %Integer  (OPCUANODENAME = "FanSpeed")      │
│  → no device references, no absolute node IDs                   │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │  DataSourceClass setting (dropdown)
                              │
┌─ Baustein 2 + generic service ──────────────────────────────┐
│  Ens.Config.Item "PlantACs"  →  TCPPollingRowSourceService      │
│    Adapter.URL             = opc.tcp://plc:4840                 │
│    Adapter.DataSourceClass = OPCUA.DS.AirConditioner  ▾         │
│    Adapter.DeviceNodePaths = ns=2;s=Plant.AC1                   │
│                              ns=2;s=Plant.AC2                   │
│                              ns=2;s=Plant.AC3                   │
└─────────────────────────────────────────────────────────────┘
                              │
                     at connect time: Browse each device root,
                     match children by BrowseName/DisplayName
                     against OPCUANODENAME → absolute node IDs
```

### Design principles

1. **Schemas are standalone, first-class, listable artifacts.** Creating one touches no production.
2. **A device is a nodepath and nothing else.** No node IDs, no masks, no per-device column lists.
3. **Resolution happens at connect time, by name.** Missing child node → NULL column, logged as a warning.
4. **A pipeline is ordinary IRIS configuration.** Fully creatable and editable from the Management Portal, with no webapp involved.
5. **The wizard becomes a convenience, not a gatekeeper.**

---

## 4. Required Changes

### 4.1 New common superclass — `OPCUA.DataSource.DeviceSchema`

**New file:** `image-iris/src/OPCUA/DataSource/DeviceSchema.cls`

```objectscript
/// Common superclass for row-source device schemas (Baustein 1).
/// Every schema generated by the wizard or by /schemas extends this class.
/// Its sole purpose beyond inheriting Definition is to give the
/// DataSourceClass setting a precise, filterable class family for its dropdown.
Class OPCUA.DataSource.DeviceSchema Extends OPCUA.DataSource.Definition [ Abstract, NoExtent ]
{
}
```

Why a new class rather than reusing `OPCUA.DataSource.Definition`: `Definition` is also the base of the hand-authored Examples and `OPCUA.Tests` classes ([Definition.cls:11](image-iris/src/OPCUA/DataSource/Definition.cls#L11)). A dropdown built on `Definition` would list `OPCUA.Tests.DataTestDS`, `Examples.OPCUADS.*` etc. — classes that would fail in a row-source service. `DeviceSchema` narrows this to exactly the classes the generic service can consume, while still satisfying the supervisor's "gemeinsame Superklasse" requirement.

`GenerateDataSourceTextV2()` must change its `Super` from `"%Persistent,OPCUA.DataSource.Definition"` to `"%Persistent,OPCUA.DataSource.DeviceSchema"` ([DeployService.cls:363](image-iris/src/OPCUA/REST/DeployService.cls#L363)).

### 4.2 Schema properties must carry resolvable names

Already true for flat columns (`OPCUANODENAME` is set). Two gaps to close:

- **`%SerialObject` folder properties** get `OPCUANODENAME` set to the folder name ([DeployService.cls:405](image-iris/src/OPCUA/REST/DeployService.cls#L405)) — good, this is what lets the resolver descend one level.
- **BrowseName vs DisplayName.** The wizard populates `OPCUANODENAME` from the browse result's `displayName`, which `BrowseService.ParseBrowseResults()` prefers over `browseName` ([BrowseService.cls:96](image-iris/src/OPCUA/REST/BrowseService.cls#L96)). These are usually identical but are not guaranteed to be — DisplayName is localized, BrowseName is the stable identifier. **See open question Q3.**

### 4.3 New setting — `DeviceNodePaths`

**File:** `image-iris/src/OPCUA/Adapter/Common.cls`

```objectscript
/// Newline-separated list of OPC UA device root nodes, one per row.
/// Each entry produces one row per poll cycle, tagged with NodePath.
/// Accepted forms per line:
///   ns=2;s=Plant.AC1          → explicit NodeId (recommended)
///   ns=2;i=1047               → numeric NodeId
///   /Plant/AC1                → browse path from the Objects folder
/// An optional label may be appended after a pipe:
///   ns=2;s=Plant.AC1|AC1      → NodePath column will read "AC1"
Property DeviceNodePaths As %String(MAXLEN = 32000);
```

Registered in `SETTINGS` with a multiline editor so the Portal renders a textarea rather than a single-line input.

### 4.4 Dropdown for `DataSourceClass`

**File:** `image-iris/src/OPCUA/Adapter/Common.cls`

The IRIS Interoperability settings syntax is `Name:Category:editorType`. The intended value:

```objectscript
Parameter SETTINGS = "URL:Connection,ConnectionRetryTimeout:Connection,AlwaysConnect:Connection,"
    _ "DataSourceClass:Data:selector?context={Ens.ContextSearch/SubclassOf?super=OPCUA.DataSource.DeviceSchema},"
    _ "DeviceNodePaths:Data:textarea,"
    _ "Username:User,Password:User,SecurityMode:Security,...";
```

> **⚠️ Needs empirical verification — Docker was not running when this PRD was written.** Both the `Ens.ContextSearch/SubclassOf` context provider and the `textarea` editor keyword must be confirmed against the IRIS version in `image-iris/Dockerfile`. Fallback if `SubclassOf` is unavailable or cannot be filtered: implement a small custom context provider, e.g. `OPCUA.DataSource.Registry.SchemaList()`, referenced as `selector?context={OPCUA.DataSource.Registry/SchemaList}`. A custom provider is arguably preferable regardless, since it can exclude abstract classes and schemas whose compile is stale. **Resolve this before implementing 4.4** — it is the one requirement whose mechanism is unproven.

Note this setting lives on the *adapter*, which is shared with the v1 declarative path used by Examples and Tests. Narrowing the dropdown to `DeviceSchema` means the Examples services would show an empty dropdown for their own `Definition`-based classes. **See open question Q4.**

### 4.5 New runtime resolver — `OPCUA.DataSource.Resolver`

**New file:** `image-iris/src/OPCUA/DataSource/Resolver.cls`

Single responsibility: given a connected client, a schema class, and a device list, produce the combined `%List` specification that `ReadBulkSetupC` / `CreateSubscriptionSetB` expect — plus a per-device coverage mask discovered by browsing.

```objectscript
/// Resolve a schema + device list into a concrete adapter specification by
/// browsing each device and matching children by name against OPCUANODENAME.
ClassMethod ResolveSpecification(
    pClient      As OPCUA.Client,
    pSchemaClass As %String,
    pDevices     As %List,        // $LB($LB(ns,id,idType,label), ...)
    Output pSpec As %List,        // combined spec for the C++ layer
    Output pMasks As %List,       // $LB($LB(1,0,1,...), ...) — discovered, not stored
    Output pDiagnostics As %List  // unmatched columns, for logging
) As %Status
```

Algorithm per device:

1. `pClient.Browse()` the device root → child list (reuse `BrowseService.ParseBrowseResults()`, or better: extract the raw-list walk into a shared helper so REST and runtime cannot drift apart).
2. Build a case-sensitive map `name → $LB(ns, id, idType)` from BrowseName, plus a DisplayName fallback map.
3. Walk the schema's column spec from `^OPCUA.DataSource(schemaClass)` in storage order (same order `Projection.ProcessObj()` used, so mask index ↔ column index alignment is preserved).
4. For each column, look up its `OPCUANODENAME` (spec position 4). Found → mask bit 1, emit spec entry with the resolved absolute node ID. Not found → mask bit 0, record in diagnostics.
5. For `%SerialObject` folder columns, Browse one level deeper from the matched folder node and repeat for the inner properties.

This subsumes the mask-building loops currently inlined in both row-source services and eliminates `absNodeRefs` entirely.

### 4.6 Resolution must happen after Connect, not in OnInit

**This is the main structural obstacle and the highest-risk part of the work.**

Current sequence:

| Step | Where | Client connected? |
|---|---|---|
| `Service.OnInit()` reads `^OPCUA.RowSource`, builds spec, calls `Adapter.Configure(spec)` | [TCPPollingRowSourceService.cls:54](image-iris/src/OPCUA/Service/TCPPollingRowSourceService.cls#L54) | **No** |
| `Adapter.Connect()` calls `ReadBulkSetupC(..Specification)` | [TCPPollingInboundAdapter.cls:30](image-iris/src/OPCUA/Adapter/TCPPollingInboundAdapter.cls#L30) | Yes — connects inside `##super()` |
| `Adapter.OnTask()` polls, calls `BusinessHost.ProcessInput()` | [TCPPollingInboundAdapter.cls:61](image-iris/src/OPCUA/Adapter/TCPPollingInboundAdapter.cls#L61) | Yes |

Browsing requires a live session, so the spec can no longer be built in `OnInit()`. Note also that `##super()` (which establishes the session) currently runs *after* `ReadBulkSetupC` — so the ordering inside `Connect()` itself has to change.

Proposed shape — a resolve callback the adapter invokes once a session exists:

```objectscript
// OPCUA.Adapter.Common — new overridable hook, default no-op
Method ResolveSpecification() As %Status
{
    Quit $$$OK
}

// TCPPollingInboundAdapter.Connect() — reordered
set tSC = ##super()                    // establish session FIRST
Quit:$$$ISERR(tSC)
set tSC = ..ResolveSpecification()     // browse + build spec (row-source services only)
Quit:$$$ISERR(tSC)
set tSC = ..Client.ReadBulkSetupC(.tmp, ..Specification)
```

The row-source service overrides the hook by delegating to `Resolver`, then stores the discovered masks on itself for `OnProcessInput()` to consume.

Requirements this creates:
- **Re-resolution on reconnect.** After a disconnect the query handle is rebuilt, so the spec must be rebuilt too. Cheap correctness win: a device that came online since the last connect gets picked up automatically.
- **Resolution caching.** Browsing N devices × M columns on every reconnect costs round-trips. Cache keyed by `(schemaClass, deviceList, URL)`, invalidated on schema recompile. Measure before optimizing.
- **`##super()` reordering must not regress the v1 path.** `TCPSubscriptionInboundAdapter` (417 lines) has its own connect/setup sequence and needs the same treatment, verified independently.

### 4.7 Row-source services become thin

`TCPPollingRowSourceService` (304 lines) and `TCPSubscriptionRowSourceService` (256 lines) currently carry ~130 lines each of metadata decoding, mask counting and spec assembly. After the change:

- **Delete:** `^OPCUA.RowSource` loading, mask counting, `absNodeRefs` handling, combined-spec construction (moves to `Resolver`).
- **Keep:** the compiled-storage position discovery (`RowSize`, `NodePathPos`, `DataColumnPositions`) — still needed, still correct, and independent of how nodes are resolved.
- **Keep:** `BuildNestedValues()` and `NestingSpec`. **But** `nestingSpec` is currently *stored* in `^OPCUA.RowSource` position 5; it must instead be *derived* from the schema class at `OnInit()` by walking the compiled class for `%SerialObject`-typed properties. This is a real piece of work, not a rename.
- **Change:** read `DeviceNodePaths` instead of the global; obtain masks from `Resolver` output.

### 4.8 `^OPCUA.RowSource` is retired

Once devices live in settings and masks/nesting are derived, the global has no remaining purpose.

Touch points to clean up:
- `DeployService.StoreRowSourceMetadata()` — delete ([DeployService.cls:496](image-iris/src/OPCUA/REST/DeployService.cls#L496))
- `PipelineService.GetRowSourceInfo()` — reimplement from settings ([PipelineService.cls:365](image-iris/src/OPCUA/REST/PipelineService.cls#L365))
- `PipelineService.Delete()` — drop the `Kill ^OPCUA.RowSource` ([PipelineService.cls:257](image-iris/src/OPCUA/REST/PipelineService.cls#L257))
- `PipelineService.Edit()` — no longer rewrites the global ([PipelineService.cls:333](image-iris/src/OPCUA/REST/PipelineService.cls#L333))
- `Projection.RemoveProjection()` — drop the `Kill ^OPCUA.RowSource` ([Projection.cls:245](image-iris/src/OPCUA/DataSource/Projection.cls#L245))

**Migration — not required.** The repo is still under active development with no important pipelines deployed anywhere, so there is nothing to migrate. The global can be retired outright: delete the write/read paths in the same commit, no migration utility, no fallback-read grace period. If a stale `^OPCUA.RowSource` happens to exist in a dev instance, just `Kill` it manually.

### 4.9 REST API — separate schema and pipeline lifecycles

New endpoints in `OPCUA.REST.Handler`, backed by a new `OPCUA.REST.SchemaService`:

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/schemas` | Create a schema from `columns[]`. No production side effects. |
| `GET` | `/schemas` | List schemas (subclasses of `DeviceSchema`) with column counts and table names. |
| `GET` | `/schemas/:name` | Column detail for one schema — drives device-binding validation in the UI. |
| `DELETE` | `/schemas/:name` | Delete a schema. **Must refuse** if any config item references it. |
| `POST` | `/schemas/:name/validate` | Given a schema and a device nodepath, browse and report which columns resolve. Powers a pre-deploy dry run. |

Changes to existing endpoints:

- `POST /deploy` — accept `{schemaClass, devices[], url, mode, ...}` as the new preferred body: bind an *existing* schema to devices, generating nothing. Keep accepting the current `{columns[], rowSources[]}` body as a compatibility shim that internally calls `/schemas` then `/deploy`.
- `POST /pipelines/edit` — editing a device list becomes a settings update, not a class regeneration. Substantially simpler than today's regenerate-and-recompile path.

`/schemas/:name/validate` is the mitigation for the deferred-failure risk in §7 and should not be treated as optional polish.

### 4.10 Webapp — split the wizard

Current wizard is a single 1400-line component that ends in one deploy call.

| Change | Detail |
|---|---|
| **Mode split** | Two entry points: *Create Schema* (tree → columns → save) and *Create Pipeline* (pick schema → add devices → connection settings → deploy). |
| **Schema library view** | List/inspect/delete schemas via `/schemas`. |
| **Device binding step** | Add devices by browsing *or* by pasting nodepaths. Live per-device coverage via `/schemas/:name/validate`, showing matched / missing columns before deploy. |
| **Reuse flow** | "Add devices to existing schema" — the flow that currently requires a full wizard re-run. |
| **Simplify** | The connected-components schema-merge and nested-merge post-processing in `pipelineGroups()` exists to reconcile heterogeneous selections into one class. With schema creation as an explicit, separate act, much of this heuristic can go. Confirm against the existing edit-mode overlap validation before deleting. |
| **Keep** | `packagePath` already defaults to `'OPCUA.DS'` ([pipeline-wizard.component.ts:879](webapp/src/app/pages/pipeline-wizard/pipeline-wizard.component.ts#L879)) — matches the supervisor's required convention, no change needed. |

### 4.11 Documentation

- `ARCHITECTURE.md` — replace the "v2 Pipeline Architecture (Row-Source Model)" section; the `^OPCUA.RowSource` description becomes historical.
- `CLAUDE.md` (both root and `iris-opcua/`) — update the globals table and the "Key Design Constraints" bullet asserting wizard-only deploy.
- `CHANGELOG.md` — note the breaking change and the migration command.

---

## 5. Data Model Before / After

| Concern | Today | Target |
|---|---|---|
| Schema definition | Generated class + `^OPCUA.DataSource` | **Unchanged** |
| Device list | `^OPCUA.RowSource` position 3 | `DeviceNodePaths` setting on the config item |
| Absolute node IDs | Frozen in `absNodeRefs` at deploy | Resolved by Browse at connect |
| Column coverage mask | Precomputed, stored | Discovered per connect |
| Nesting layout | Stored in `^OPCUA.RowSource` position 5 | Derived from the compiled schema class |
| `OPCUANODENAME` | Written, then discarded at runtime | **The matching key** |
| Creating a schema alone | Impossible | `POST /schemas` |
| Adding a device | Re-run wizard | Add one line to a setting |
| Hand-configurable in Portal | No | Yes |

---

## 6. Open Questions

Q1–Q4 block implementation of their respective sections; Q5–Q6 can be settled during implementation.

**Q1. Device nodepath syntax.** Support `ns=2;s=Plant.AC1` only, or also browse paths like `/Plant/AC1`? NodeId form maps directly onto `Client.Browse(types, namespaces, ids)` with zero extra round-trips. Browse-path form is far friendlier to hand-editing but needs a hop-by-hop walk from the Objects folder (85). *Recommendation: ship NodeId form first, add browse-path resolution second.*

**Q2. Behaviour when a column does not resolve.** Options: (a) store NULL + log warning — matches today's mask semantics; (b) refuse to start the service; (c) per-pipeline `StrictSchemaMatch` boolean setting. *Recommendation: (c), defaulting to (a),* so the loose default preserves current behaviour and strictness is opt-in for production.

**Q3. Match on BrowseName or DisplayName?** OPC UA treats BrowseName as the stable identifier and DisplayName as localized presentation. The wizard currently writes DisplayName into `OPCUANODENAME` (§4.2). Matching on BrowseName is more correct but could fail against schemas generated today. *Recommendation: try BrowseName, fall back to DisplayName, log when only the fallback matched — and separately consider storing BrowseName in `OPCUANODENAME` going forward.*

**Q4. Which superclass backs the dropdown?** `DeviceSchema` gives a clean list but leaves the Examples/Tests services (sharing the same adapter, §4.4) with an empty dropdown. Options: (a) accept it — Examples are demo-only and rarely reconfigured; (b) point the selector at `Definition` and accept extra entries; (c) split the adapter hierarchy so v1 and v2 paths carry different `SETTINGS`. *Recommendation: (a) first, (c) if the Examples become awkward.*

**Q5. Resolution caching.** Is per-reconnect browsing fast enough at realistic scale (say 50 devices × 20 columns)? Measure before adding a cache and its invalidation bugs.

**Q6. Heterogeneous devices.** Today's union-with-masks model lets one pipeline serve devices with differing column sets. Name-based resolution handles this for free — but should the UI *encourage* it, or steer users toward one schema per device type? Affects how hard §4.10 pushes the auto-discovery flow.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Deferred failure.** A renamed/missing node now fails at runtime rather than at deploy, when the wizard verified every node up front. | **High** | `/schemas/:name/validate` dry run (§4.9); `StrictSchemaMatch` (Q2); explicit event-log warnings listing unresolved columns per device. |
| **Connect-sequence regression.** Reordering `##super()` inside `Connect()` touches the shared v1 path used by Examples and the `OPCUA.Tests` harness. | **High** | Default no-op `ResolveSpecification()` hook keeps v1 behaviour byte-identical; run `OPCUA.Tests.DataTest.Run()` before and after; treat `TCPSubscriptionInboundAdapter` as separate work. |
| **Browse overhead per reconnect.** N devices × M columns of round-trips on every reconnect. | Medium | Measure (Q5); cache if warranted; batch the browse calls. |
| **Name collisions.** Two children with the same BrowseName under one device. | Low | Resolver logs a warning and takes the first match deterministically. |
| **Unverified selector syntax.** §4.4 rests on `Ens.ContextSearch/SubclassOf` and a `textarea` editor keyword that were not confirmed against a running instance. | Medium | Verify in Docker before implementing; custom context provider as documented fallback. |

---

## 8. Suggested Phasing

Each phase is independently shippable and leaves the system working.

**Phase 1 — Foundation (no behaviour change).**
`DeviceSchema` superclass; generated classes extend it; `Resolver` implemented and unit-tested against the `plc` container, but not yet wired into any service. Verify the selector syntax in Docker (Q4/§4.4) and settle Q1–Q3.

**Phase 2 — Standalone schema creation.**
`SchemaService` + `/schemas` endpoints. `DeployV2` refactored to call `CreateSchema()` then `BindDevices()` internally. External behaviour and payloads unchanged — this is the "split the functionality" note, done invisibly.

**Phase 3 — Generic service.**
`DeviceNodePaths` setting; `DataSourceClass` dropdown; `ResolveSpecification()` hook and `Connect()` reordering; row-source services switched to settings + `Resolver`; nesting spec derived from the class. **Acceptance test: build a working pipeline entirely from the Management Portal, with the webapp closed.**

**Phase 4 — Retire `^OPCUA.RowSource`.**
Delete `StoreRowSourceMetadata()` and all read paths; clean up the touch points in §4.8. No migration needed (no deployed pipelines).

**Phase 5 — Webapp split.**
Schema library, device-binding step, per-device validation, reuse flow.

**Phase 6 — Docs.**
`ARCHITECTURE.md`, both `CLAUDE.md` files, `CHANGELOG.md`.

Phases 1–4 deliver everything the supervisor asked for. Phase 5 is the ergonomic payoff; Phase 6 keeps the docs honest.

---

## 9. Out of Scope

- Any change to the C++ library (`opc-ua-master`) — `Browse` and `ReadBulkSetupC` already provide everything needed.
- The v1 declarative path (Examples, `OPCUA.Tests`) keeps working unchanged; it is the type-marshalling test harness and must not regress.
- Write support, subscription semantics, and security/certificate handling.
- Chrome extension. *(Since deleted from the repo, along with the `/generate` endpoint it was the only consumer of.)*

---

## 10. Acceptance Criteria

1. A schema can be created via `POST /schemas` with no production, service item, or global side effects.
2. `GET /schemas` lists it; `OPCUA.DS.<Name>` is the package convention.
3. In the Production Configuration UI, `DataSourceClass` renders as a dropdown populated from the common superclass.
4. A pipeline can be created **entirely from the Management Portal** — add service item, pick schema from dropdown, type device nodepaths, start — with no webapp involvement.
5. Adding a fourth device is a one-line edit to `DeviceNodePaths`, requiring no regeneration and no recompile.
6. A device missing a column stores NULL for it and logs a warning naming the device and the column.
7. `^OPCUA.RowSource` is gone, with no read or write paths remaining anywhere in the codebase.
8. `OPCUA.Tests.DataTest.Run()` passes unchanged.
