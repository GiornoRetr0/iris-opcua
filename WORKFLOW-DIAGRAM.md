# End-to-End Workflow — Mermaid Diagrams

> Detailed call-level trace of the IRIS OPC UA Adapter, from clicking "Deploy" in the
> wizard to a running poller writing SQL rows. Method names and globals verified against
> `image-iris/src/` on 2026-06-29. Covers the **v2 row-source** path.

The system has **two phases** that never call each other directly — they hand off through
two IRIS globals (`^OPCUA.DataSource` and `^OPCUA.RowSource`):

- **ACT 1 — Deploy:** one short HTTP request. Generates + compiles a class, writes globals, adds a production item.
- **ACT 2 — Runtime:** a background job that connects once and polls forever.

---

## 0. High-level overview (the two acts + the handoff)

```mermaid
flowchart TB
    subgraph ACT1["🛠 ACT 1 — Deploy (one HTTP request, < 1s)"]
        direction TB
        A1["Angular webapp / Chrome ext<br/>POST /deploy"]
        A2["Handler.Deploy()"]
        A3["DeployService.DeployV2()"]
        A4["GenerateDataSourceTextV2()<br/>builds class via %Dictionary"]
        A5["$System.OBJ.Compile()"]
        A6["Projection.CreateProjection()<br/>fires ON COMPILE"]
        A7["StoreRowSourceMetadata()"]
        A8["AddServiceItem() +<br/>StartOrUpdateProduction()"]
        A1 --> A2 --> A3 --> A4 --> A5 -.fires.-> A6
        A3 --> A7
        A3 --> A8
    end

    G1[("^OPCUA.DataSource(cls)<br/>column spec")]
    G2[("^OPCUA.RowSource(cls)<br/>row sources + masks")]
    A6 -- writes --> G1
    A7 -- writes --> G2

    subgraph ACT2["🔄 ACT 2 — Runtime (background job, forever)"]
        direction TB
        B1["Ensemble scheduler<br/>spawns business service"]
        B2["TCPPollingRowSourceService.OnInit()"]
        B3["Adapter.Configure(spec)"]
        B4["Adapter.OnTask() — every CallInterval"]
        B5["OPCUA.Client → $ZF(-5) → C++ → server"]
        B6["OnProcessInput() builds $LB rows"]
        B7["SaveSourcedData() → SQL row"]
        B1 --> B2 --> B3 --> B4 --> B5 --> B6 --> B7
        B4 -. loop .-> B4
    end

    G1 -- read by OnInit --> B2
    G2 -- read by OnInit --> B2

    ENGINE["INHERITED ENGINE<br/>OPCUA.Client · $ZF(-5) · C++ lib"]
    A5 -.uses.-> ENGINE
    B5 --- ENGINE

    classDef act1 fill:#e3f2fd,stroke:#1976d2;
    classDef act2 fill:#e8f5e9,stroke:#388e3c;
    classDef glob fill:#fff3e0,stroke:#f57c00,stroke-width:2px;
    classDef eng fill:#fce4ec,stroke:#c2185b,stroke-width:2px;
    class A1,A2,A3,A4,A5,A6,A7,A8 act1;
    class B1,B2,B3,B4,B5,B6,B7 act2;
    class G1,G2 glob;
    class ENGINE eng;
```

---

## 1. ACT 1 — Deploy (detailed call sequence)

```mermaid
sequenceDiagram
    autonumber
    participant UI as webapp / chrome-ext
    participant H as REST.Handler
    participant DS as REST.DeployService
    participant DICT as %Dictionary + OBJ.Compile
    participant PROJ as DataSource.Projection
    participant GD as ^OPCUA.DataSource
    participant GR as ^OPCUA.RowSource
    participant ENS as Ens production

    UI->>H: POST /deploy  {columns, rowSources, mode, pipelineVersion:2}
    activate H
    H->>H: GetRequestParams(.tBody)  (JSON body → %DynamicObject)
    H->>DS: Deploy(tBody, .tResult)
    activate DS
    Note over DS: Deploy() requires rowSources → forwards to DeployV2()
    DS->>DS: DeployV2(pBody, .pResult)
    activate DS

    Note over DS: validate columns / rowSources / className

    DS->>DS: GenerateDataSourceTextV2(...)
    activate DS
    DS->>DS: FindDefaultNamespace(childNodes)
    opt has nested folders
        DS->>DS: GenerateSerialClasses(class, ns, .folders, .out)
        DS->>DICT: %Dictionary.ClassDefinition (%SerialObject)<br/>%Save + OBJ.Compile  (per folder)
    end
    Note over DS: build main class: NodePath, ServerTimeStamp,<br/>SourceTimeStamp + one column per union col<br/>(MapToPlainType: Double→%Double, array→%String JSON)
    DS->>DICT: tClassDef.%Save()
    DS->>DICT: $System.OBJ.Compile(class, "ck-d")
    activate DICT
    Note over DICT,PROJ: compiling a subclass of OPCUA.DataSource.Definition<br/>auto-fires its Projection (see diagram 3)
    DICT->>PROJ: CreateProjection(cls)
    activate PROJ
    PROJ->>GD: write ^OPCUA.DataSource(cls) = $LB(name, global, colSpec)
    PROJ-->>DICT: SaveSourcedData() generated on class
    deactivate PROJ
    DICT-->>DS: compiled (SQL table now exists)
    deactivate DICT
    deactivate DS

    DS->>DS: StoreRowSourceMetadata(class, rowSources, columns)
    DS->>GR: write ^OPCUA.RowSource(cls) = $LB(rsCount, colCount, rsList, paths, nesting)

    DS->>DS: EnsureProductionExists()
    DS->>DS: AddServiceItem(pBody, class, dsName, mode)
    Note over DS,ENS: Ens.Config.Item ClassName = TCPPollingRowSourceService<br/>(or TCPSubscriptionRowSourceService); AddSetting DataSourceClass, URL, CallInterval...
    DS->>ENS: tProd.Items.Insert() + %Save() + SaveToClass()
    DS->>DS: StartOrUpdateProduction()
    DS->>ENS: Ens.Director.UpdateProduction() / StartProduction()
    deactivate DS

    DS-->>H: tResult {deployed, compiled, started, tableName}
    deactivate DS
    H->>H: SendOK(tResult)  → {"status":"ok","data":{...}}
    H-->>UI: 200 JSON
    deactivate H
    Note over UI,ENS: HTTP request ENDS here. REST connection gone.<br/>Pipeline now lives as a background job → ACT 2.
```

---

## 2. ACT 2 — Runtime (detailed call sequence, repeats forever)

```mermaid
sequenceDiagram
    autonumber
    participant ENS as Ensemble scheduler
    participant SVC as TCPPollingRowSourceService
    participant AD as TCPPollingInboundAdapter
    participant CMN as Adapter.Common
    participant CL as OPCUA.Client
    participant CPP as $ZF(-5) → C++ → server
    participant GR as ^OPCUA.RowSource
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
    SVC->>GR: $Get(^OPCUA.RowSource(DataSourceClass))
    Note over SVC: parse rsCount, colCount, rsList, nestingSpec
    SVC->>SVC: %Dictionary.CompiledClass.%OpenId(class)<br/>→ discover alphabetical storage positions
    SVC->>GD: Projection.GetOPCUAConfigSpec(class)<br/>(returns ^OPCUA.DataSource(cls))
    Note over SVC: build combined spec — one entry per active<br/>(row source × column), FORCE type=2 (full DataValue)
    SVC->>AD: Adapter.Configure(.tCombinedSpec)
    AD->>AD: store ..Specification
    deactivate SVC

    loop every CallInterval seconds (OnTask)
        ENS->>AD: OnTask()
        activate AD
        alt not connected yet
            AD->>AD: Connect()
            AD->>CL: ReadBulkClear(QueryHandle)  (if reconnect)
            AD->>CL: ReadBulkSetupC(.tmp, ..Specification)
            CL->>CPP: $ZF(-5, lib, ord=17, spec)
            AD->>CMN: ##super() = Common.Connect()
            CMN->>CL: Connect(URL, user, pass)
            CL->>CPP: $ZF(-5, lib, ord=13/38)
        end
        AD->>CL: ReadBulkPollC(.tList, QueryHandle)
        CL->>CPP: $ZF(-5, lib, ord=20)  → snapshot all nodes
        CPP-->>CL: $LB(meta, DataValue1, DataValue2, ...)
        AD->>SVC: BusinessHost.ProcessInput(.tList)
        activate SVC
        loop each row source
            Note over SVC: walk columns by mask, extract leaf values<br/>+ capture serverTS / sourceTS from first DataValue
            opt nestingSpec present
                SVC->>SVC: BuildNestedValues(nestingSpec, .leafValues)<br/>(recursive: leaf vs serial sub-$LB)
            end
            Note over SVC: place values at compiled storage positions →<br/>$LB("", nodePath, serverTS, sourceTS, v1, v2, ...)
            SVC->>SQL: $CLASSMETHOD(class, "SaveSourcedData", .tRowData)
            Note over SQL: $Increment(global) → one row per row source
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

- **The two globals are the entire contract between deploy and runtime.** `^OPCUA.DataSource`
  is written by the Projection at *compile* time; `^OPCUA.RowSource` by DeployService at
  *deploy* time. The runtime service reads both in `OnInit()`.
- **The seam to the inherited engine is `$System.OBJ.Compile`** (which fires the inherited
  Projection) and **`OPCUA.Client`** (the `$ZF(-5)` C++ bridge) — both used unchanged.
- **Storage order is alphabetical**, and *both* the Projection (compile) and the service
  (runtime, via `%Dictionary.CompiledClass`) independently rely on that ordering — which is
  why renaming a property silently shifts the spec.
- **`$ZF(-5)` ordinals** (17 = ReadBulkSetupC, 20 = ReadBulkPollC, 13/38 = Connect) come from
  `OPCUA/Constants.inc` and must match the closed-source C++ dispatch table.
```

