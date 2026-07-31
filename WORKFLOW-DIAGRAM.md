# End-to-End Workflow — Mermaid Diagrams

> Detailed call-level trace of the IRIS OPC UA Adapter, from creating a schema to a
> running poller writing SQL rows.

The system has **three phases**. Schema creation and device binding are separate
operations — that split is the point, and it is why "add a device" is a settings edit:

- **ACT 1 — Create schema** (`POST /schemas`): generates + compiles a class. **No
  production, no device information.** Happens once per device *type*.
- **ACT 2 — Bind devices** (`POST /deploy`): **generates nothing.** Adds one production
  item whose settings name the schema and list the devices. Repeatable per schema.
- **ACT 3 — Runtime:** a background job that resolves devices **by name on every
  connect**, then polls forever.

ACT 1 hands off to ACT 3 through `^OPCUA.DataSource` (the column spec). ACT 2 hands off
through **ordinary production settings** — there is no device metadata global.

---

## 0. High-level overview (three acts + the handoffs)

```mermaid
flowchart TB
    subgraph ACT1["📐 ACT 1 — Create schema (once per device TYPE)"]
        direction TB
        A1["Schema builder<br/>POST /schemas"]
        A2["Handler.SchemasCreate()"]
        A3["SchemaService.GenerateSchemaClass()<br/>builds class via %Dictionary"]
        A4["$System.OBJ.Compile()"]
        A5["Projection.CreateProjection()<br/>fires ON COMPILE"]
        A1 --> A2 --> A3 --> A4 -.fires.-> A5
    end

    G1[("^OPCUA.DataSource(cls)<br/>column spec")]
    A5 -- writes --> G1

    subgraph ACT2["🔗 ACT 2 — Bind devices (once per PIPELINE)"]
        direction TB
        C1["Device binding screen<br/>POST /deploy {schemaClass, devices}"]
        C2["Handler.Deploy()"]
        C3["DeployService.BindExistingSchema()<br/>generates NOTHING"]
        C4["AddServiceItem()<br/>Enabled = 0 — nothing starts"]
        C1 --> C2 --> C3 --> C4
    end

    S1[["Ens.Config.Item settings<br/>DataSourceClass + DeviceNodePaths"]]
    C4 -- writes --> S1

    subgraph ACT3["🔄 ACT 3 — Runtime (background job, forever)"]
        direction TB
        B0["User presses play<br/>POST /pipelines/toggle"]
        B1["Ensemble scheduler<br/>spawns business service"]
        B2["TCP*RowSourceService.OnInit()<br/>column layout + nesting spec"]
        B3["Adapter.Connect()<br/>1. session  2. Resolver browses devices<br/>3. ReadBulkSetupC(spec)"]
        B4["Adapter.OnTask() — every CallInterval"]
        B5["OPCUA.Client → $ZF(-5) → C++ → server"]
        B6["OnProcessInput() builds $LB rows"]
        B7["SaveSourcedData() → one row per device"]
        B0 --> B1 --> B2 --> B3 --> B4 --> B5 --> B6 --> B7
        B4 -. loop .-> B4
    end

    G1 -- read by OnInit --> B2
    S1 -- read on every connect --> B3

    ENGINE["INHERITED ENGINE<br/>OPCUA.Client · $ZF(-5) · C++ lib"]
    A4 -.uses.-> ENGINE
    B5 --- ENGINE

    classDef act1 fill:#e3f2fd,stroke:#1976d2;
    classDef act2 fill:#ede7f6,stroke:#5e35b1;
    classDef act3 fill:#e8f5e9,stroke:#388e3c;
    classDef glob fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    classDef eng fill:#fce4ec,stroke:#c2185b,stroke-width:2px;
    class A1,A2,A3,A4,A5 act1;
    class C1,C2,C3,C4 act2;
    class B0,B1,B2,B3,B4,B5,B6,B7 act3;
    class G1,S1 glob;
    class ENGINE eng;
```

Because ACT 3's resolution step re-runs on **every** connect, editing `DeviceNodePaths`
in ACT 2's settings takes effect with no recompile, and a device that was unreachable at
startup begins reporting on its own.

ACT 2 ends at a config item, not at a running job. A pipeline is created **stopped**, so
ACT 3 begins only when the operator presses play — deploying and collecting are separate
decisions.

---

## 1. ACTS 1 & 2 — Create schema, then bind devices (detailed call sequence)

```mermaid
sequenceDiagram
    autonumber
    participant UI as webapp
    participant H as REST.Handler
    participant SS as REST.SchemaService
    participant DS as REST.DeployService
    participant DICT as %Dictionary + OBJ.Compile
    participant PROJ as DataSource.Projection
    participant GD as ^OPCUA.DataSource
    participant ENS as Ens production

    rect rgb(227, 242, 253)
    Note over UI,ENS: ACT 1 — create the schema. No production is touched.
    UI->>H: POST /schemas  {name, packagePath, columns[{displayName, relativePath, nodeNs, inferredType}]}
    activate H
    H->>H: GetRequestParams(.tBody)  (JSON body → %DynamicObject)
    H->>SS: Create(tBody, .tResult)
    activate SS
    Note over SS: validate name / columns — refuse if the class already exists
    SS->>SS: GenerateSchemaClass(class, dsName, columns, defaultNS, .colNS, .serialClasses)
    activate SS
    opt has nested folders
        SS->>SS: GenerateSerialClasses(class, ns, .folders, .out)
        SS->>DICT: %Dictionary.ClassDefinition (%SerialObject)<br/>%Save + OBJ.Compile  (per folder)
    end
    Note over SS: build main class extending<br/>(%Persistent, OPCUA.DataSource.DeviceSchema):<br/>NodePath, ServerTimeStamp, SourceTimeStamp<br/>+ one column each (MapToPlainType: Integer→%Integer,<br/>Double→%Double, array→%String JSON, unset→%String)
    SS->>DICT: tClassDef.%Save()
    SS->>DICT: $System.OBJ.Compile(class, "ck-d")
    activate DICT
    Note over DICT,PROJ: compiling a subclass of OPCUA.DataSource.Definition<br/>auto-fires its Projection (see diagram 3)
    DICT->>PROJ: CreateProjection(cls)
    activate PROJ
    PROJ->>GD: write ^OPCUA.DataSource(cls) = $LB(name, global, colSpec)
    PROJ-->>DICT: SaveSourcedData() generated on class
    deactivate PROJ
    DICT-->>SS: compiled (SQL table now exists)
    deactivate DICT
    deactivate SS
    SS-->>H: {created, schemaClass, tableName, columnCount}
    deactivate SS
    H-->>UI: 200 JSON
    deactivate H
    Note over UI,ENS: The schema now exists on its own. It can be listed,<br/>inspected, deleted — or bound any number of times.
    end

    rect rgb(237, 231, 246)
    Note over UI,ENS: ACT 2 — bind devices. Generates nothing.
    loop per device, as it is added
        UI->>H: POST /schemas/:name/validate  {devices, url}
        H-->>UI: matched / missing columns, browsed, usable
        Note over UI: unusable → flagged in the list, Deploy stays locked
    end
    UI->>H: POST /deploy  {schemaClass, devices, mode, url, callInterval}
    activate H
    H->>DS: Deploy(tBody, .tResult)
    activate DS
    Note over DS: schemaClass is REQUIRED → BindExistingSchema()
    DS->>DS: BindExistingSchema(pBody, .pResult)
    activate DS
    Note over DS: verify the class exists, is compiled,<br/>and is a DeviceSchema subclass
    DS->>DS: Resolver.ParseDeviceNodePaths(devices, .parsed, .errors)
    Note over DS: reject an unusable list here, per line,<br/>rather than failing at connect time
    Note over DS: refuse a duplicate config-item name
    DS->>DS: EnsureProductionExists()
    DS->>DS: AddServiceItem(pBody, schemaClass, itemName, mode, devices)
    Note over DS,ENS: Ens.Config.Item ClassName = TCPPollingRowSourceService<br/>(or TCPSubscriptionRowSourceService) — Enabled = 0 — AddSetting<br/>DataSourceClass / DeviceNodePaths / URL /<br/>CallInterval
    DS->>ENS: tProd.Items.Insert() + %Save() + SaveToClass()
    Note over DS,ENS: the production is NOT started and the item stays off:<br/>a deploy is a pure configuration write
    deactivate DS
    DS-->>H: {deployed, compiled, started: 0, tableName, deviceCount}
    deactivate DS
    H->>H: SendOK(tResult)  → {"status":"ok","data":{...}}
    H-->>UI: 200 JSON
    deactivate H
    end

    rect rgb(232, 245, 233)
    Note over UI,ENS: ACT 2b — start it, when the operator decides to
    UI->>H: POST /pipelines/toggle {name}
    H->>ENS: PipelineService.Toggle() → Enabled = 1<br/>+ UpdateProduction() / StartProduction()
    H-->>UI: {name, enabled: 1}
    end

    Note over UI,ENS: HTTP requests END here. REST connection gone.<br/>Pipeline now lives as a background job → ACT 3.

```

---

## 2. ACT 3 — Runtime (detailed call sequence, repeats forever)

```mermaid
sequenceDiagram
    autonumber
    participant ENS as Ensemble scheduler
    participant SVC as TCPPollingRowSourceService
    participant AD as TCPPollingInboundAdapter
    participant CMN as Adapter.Common
    participant CL as OPCUA.Client
    participant CPP as $ZF(-5) → C++ → server
    participant RES as DataSource.Resolver
    participant CFG as Ens.Config.Item settings
    participant GD as ^OPCUA.DataSource
    participant SQL as SQL table

    Note over ENS: job startup (once)
    ENS->>CMN: Adapter.OnInit()
    activate CMN
    CMN->>CL: %New() + Initialize()  (loads C++ lib via Utils)
    CMN->>CL: SetLogFile() + SetupClient(securityMode, certs...)
    deactivate CMN

    ENS->>SVC: OnInit()
    activate SVC
    SVC->>SVC: %Dictionary.CompiledClass.%OpenId(class)<br/>→ discover alphabetical storage positions
    SVC->>GD: Projection.GetOPCUAConfigSpec(class)<br/>(returns ^OPCUA.DataSource(cls))
    SVC->>RES: DeriveNestingSpec(class)<br/>walks storage order — nothing stored
    Note over SVC: devices are NOT resolved here — that needs a<br/>live session, so it happens in Connect() below
    deactivate SVC

    loop every CallInterval seconds (OnTask)
        ENS->>AD: OnTask()
        activate AD
        alt not connected yet
            AD->>AD: Connect()
            AD->>CL: ReadBulkClear(QueryHandle)  (if reconnect)
            Note over AD,CMN: session FIRST — resolution below needs one
            AD->>CMN: ##super() = Common.Connect()
            CMN->>CL: Connect(URL, user, pass)
            CL->>CPP: $ZF(-5, lib, ord=13/38)
            AD->>AD: ResolveSpecification()
            AD->>CFG: read DeviceNodePaths
            AD->>RES: ParseDeviceNodePaths() then ResolveSpecification(client, class, devices)
            RES->>CPP: Browse() per device root
            Note over RES: match children BY NAME against schema columns<br/>→ combined spec + per-device masks + NodePath labels<br/>unmatched → NULL + warning (or refuse if strict)
            AD->>CL: ReadBulkSetupC(.tmp, ..Specification)
            CL->>CPP: $ZF(-5, lib, ord=17, spec)
            Note over AD: if setup fails, DROP the session so the next<br/>OnTask retries Connect() — and so re-resolves
        end
        AD->>CL: ReadBulkPollC(.tList, QueryHandle)
        CL->>CPP: $ZF(-5, lib, ord=20)  → snapshot all nodes
        CPP-->>CL: $LB(meta, DataValue1, DataValue2, ...)
        AD->>SVC: BusinessHost.ProcessInput(.tList)
        activate SVC
        loop each device (row source)
            Note over SVC: walk columns by mask, extract leaf values<br/>+ capture serverTS / sourceTS from first DataValue
            opt nestingSpec present
                SVC->>SVC: BuildNestedValues(nestingSpec, .leafValues)<br/>(recursive: leaf vs serial sub-$LB)
            end
            Note over SVC: place values at compiled storage positions →<br/>$LB("", nodePath, serverTS, sourceTS, v1, v2, ...)
            SVC->>SQL: $CLASSMETHOD(class, "SaveSourcedData", .tRowData)
            Note over SQL: $Increment(global) → one row per device
        end
        deactivate SVC
        Note over AD: on error: classify via Utils.AreSimilarOpcuaDisconnectErrors,<br/>refresh GetClientState, apply ConnectionRetry deadline
        deactivate AD
    end

    Note over ENS,SQL: on stop/delete (a separate short REST call):<br/>Adapter.OnTearDown() → ReadBulkClear() → Client.Disconnect()
```

---

## 3. The compile-time "magic": Projection (zoom into ACT 1, step ~12)

This fires automatically whenever a `OPCUA.DataSource.Definition` subclass compiles — it's
the seam where the **new** DeployService reuses the **inherited** Projection engine.

```mermaid
flowchart TB
    START["$System.OBJ.Compile(cls)"] --> CHK{"cls = OPCUA.DataSource.Definition?"}
    CHK -- yes --> SKIP["do nothing (abstract base)"]
    CHK -- no --> OPEN["%Dictionary.CompiledClass.%OpenId(cls)"]
    OPEN --> PARAM["GetParameterValue(OPCUADATASOURCE)<br/>GetParameterValue(OPCUDEFAULTANAMESPACE)"]
    PARAM --> PO["ProcessObj(class, defaultNS, '', '[dsName]', .spec)"]

    subgraph PROCESS["ProcessObj() — walks STORAGE order (alphabetical, not property order)"]
        direction TB
        LOOP["for each storage data entry"] --> SKIPMETA{"% / NodePath /<br/>ServerTimeStamp /<br/>SourceTimeStamp?"}
        SKIPMETA -- yes --> NEXT["skip"]
        SKIPMETA -- no --> FINDPROP["find matching property def<br/>read OPCUANAMESPACE / OPCUANODENAME / OPCUAATTRIBUTEID"]
        FINDPROP --> TYPE{"property type?"}
        TYPE -- "%DataType (primitive)" --> C1["CreateConfigSpecEntry(code 1)"]
        TYPE -- "OPCUA.Types.* / OPCUA.Structure.*" --> C2["CreateConfigSpecEntry(code 2)"]
        TYPE -- "%SerialObject (nested folder)" --> REC["ProcessObj(subclass, ...)<br/>↩ RECURSE, append entries flat"]
        TYPE -- "other" --> ERR["error: invalid type"]
        C1 --> APPEND["append entry to spec"]
        C2 --> APPEND
        REC --> APPEND
    end

    PO --> PROCESS
    PROCESS --> COMMIT["CommitOPCUAConfigSpec()"]
    COMMIT --> WRITE[("write ^OPCUA.DataSource(cls)<br/>= $LB(dsName, storageGlobal, $LB('') _ spec)")]

    classDef glob fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    class WRITE glob;
```

---

## Key takeaways

- **One global plus two settings are the entire contract.** `^OPCUA.DataSource` is written by
  the Projection at *compile* time and read in `OnInit()`. Everything about *devices* lives in
  the config item's `DataSourceClass` + `DeviceNodePaths` settings and is re-read on every
  connect. There is deliberately no device-metadata global — an earlier design stored one
  (`^OPCUA.RowSource`), and removing it is what made "add a device" a settings edit.
- **Resolution happens at connect, not deploy.** Column masks and node IDs are derived by
  browsing each device and matching children by name, so the session must be established
  before the spec is built. That ordering is load-bearing in both adapters.
- **The seam to the inherited engine is `$System.OBJ.Compile`** (which fires the inherited
  Projection) and **`OPCUA.Client`** (the `$ZF(-5)` C++ bridge) — both used unchanged.
- **Storage order is alphabetical**, and *both* the Projection (compile) and the service
  (runtime, via `%Dictionary.CompiledClass`) independently rely on that ordering — which is
  why renaming a property silently shifts the spec.
- **`$ZF(-5)` ordinals** (17 = ReadBulkSetupC, 20 = ReadBulkPollC, 13/38 = Connect) come from
  `OPCUA/Constants.inc` and must match the closed-source C++ dispatch table.

