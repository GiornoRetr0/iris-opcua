# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Detailed architecture, ObjectScript gotchas, C++ bridge, REST API, globals, security, and the schema + device-binding model are documented in `ARCHITECTURE.md` in this directory. The parent `CLAUDE.md` (loaded automatically) consolidates all of that for Claude.**

## Quick Command Reference

### Docker environment
```bash
./generate_certificates.sh          # Generate TLS certs (required before first build)
docker compose up                    # Start all containers (iris, plc, plc2, certified-server)
docker compose build                 # Rebuild iris + certified-server images after source changes
```

### Angular webapp (OPC UA console)
```bash
cd webapp
npm install                          # First time only
npx ng serve                         # Dev server at http://localhost:4200
npx tsc --noEmit                     # Type-check only
npx ng build                         # Production build → dist/webapp/
```
The webapp calls `http://localhost:52783/csp/opcua/api` by default. Docker must be running.

### IRIS terminal (ObjectScript)
```bash
# Generic: pipe commands to iris session
printf 'zn "OPCUA"\n<your commands>\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris

# Run the type-marshalling tests. NOTE: DataTest targets the OPC Foundation
# certified server and the APPINT namespace, neither of which exists in this
# compose setup — it cannot pass here. Use the local `plc` server as the
# regression baseline instead (see Key Design Constraints below).
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.ResolverTest).Run()\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.PortalPipelineTest).Run()\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris

# Check production status
printf 'zn "OPCUA"\ndo ##class(Ens.Director).GetProductionStatus(.p,.s) write p," ",s,!\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris

# Tail event log
printf 'zn "OPCUA"\nset rs=##class(%%SQL.Statement).%%ExecDirect(,"SELECT TOP 10 Type,ConfigName,$extract(Text,1,200) FROM Ens_Util.Log ORDER BY ID DESC") while rs.%%Next() { write rs.Type," | ",rs.ConfigName," | ",rs.%%GetData(3),! }\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris
```

> **Source changes in `image-iris/src/` require rebuilding the Docker image** (`docker compose build`) to take effect — edits on disk are not hot-reloaded.

## Repository Layout (what lives where)

| Path | Contents |
|------|----------|
| `image-iris/src/OPCUA/` | All production ObjectScript: Client, Adapters, Services, REST, DataSource, Types, Tests |
| `image-iris/src/Examples/` | Demo Business Services (PollingExample, SubscriptionExample, SecureExample, ArrayExample, etc.) |
| `image-iris/src/IRISConfig/` | `Installer.cls` — namespace/DB setup run during Docker build |
| `image-iris/uacbin/` | Prebuilt Unix shared objects (`.so`) |
| `webapp/src/app/` | Angular 19 console (standalone components, signals, Tailwind) |
| `webapp/src/app/core/models/opcua.models.ts` | All TypeScript interfaces (`TreeNode`, `Schema`, `DeviceValidation`, `PipelineHealth`, etc.) |
| `webapp/src/app/pages/schema-library/`, `schema-builder/` | Schema list + creation |
| `webapp/src/app/pages/device-binding/` | Bind devices to a schema; also serves pipeline edit |
| `webapp/src/app/shared/opcua-tree/` | Embeddable single-server address-space browser |
| `webapp/src/app/core/services/api.service.ts` | REST client (browse, deploy, editPipeline, listPipelines) |
| `certgen/` | OpenSSL configs + `certgen.bash` |
| `windows/bin/` | Prebuilt Windows DLLs |
| `windows/Studio/` | Studio project XML for native Windows IRIS install |
| `mocksvr-data/data.csv` | Data served by the `plc` mock OPC UA server |

## Docker Services

| Service | Internal hostname | External port | Purpose |
|---------|-------------------|---------------|---------|
| iris | iris | 52783 (portal), 51793 (superserver) | IRIS with OPC UA adapter |
| plc | plc | 10000→4840 | Mock OPC UA server (CSV data) |
| plc2 | plc2 | 10002→4840 | Second mock OPC UA server |
| certified-server | certified-server | 10001→4840 | OPC Foundation certified server (TLS) |

Management Portal: http://localhost:52783/csp/sys/UtilHome.csp (SuperUser / SYS)  
SQL Explorer: http://localhost:52783/csp/sys/exp/%25CSP.UI.Portal.SQL.Home.zen?$NAMESPACE=OPCUA

## Key Design Constraints

- **Everything runs in the `OPCUA` namespace.** There is no `APPINT` namespace in this compose setup, so `OPCUA.Tests.DataTest` (which also needs the certified server) cannot pass here. For a regression gate, poll the local `plc` server and assert rows land with real values; `OPCUA.Tests.ResolverTest` and `PortalPipelineTest` run against `plc` and do pass.
- **Schema creation and device binding are separate, deliberately.** `POST /schemas` generates a schema class with **no** production side effects; `POST /deploy` binds devices to an existing schema and **generates nothing**. Do not reintroduce a combined create-and-deploy path — the split is a requirement, not an accident.
- **A schema is reusable and outlives its pipelines.** Several pipelines may share one. Deleting a pipeline must never delete its schema; `SchemaService.Delete` is the only deletion path and it refuses while any pipeline references the schema.
- **Devices are resolved by name at connect time**, never frozen at deploy time. `DeviceNodePaths` is an ordinary production setting, so adding a device is a one-line edit with no regeneration and no recompile. Nothing about devices is stored — masks and node IDs are derived by browsing on every (re)connect.
- **Editing a pipeline changes only devices + strictness** (`POST /pipelines/rebind`). Changing a schema's *columns* is not possible anywhere; recreate the schema, which drops the table.
- **All REST endpoints accept both GET (query params) and POST (JSON body)**, except `/schemas` which uses real verbs. Connection param is `url`, not `serverUrl`.
- **Every pipeline uses the row-source services** (`TCP*RowSourceService`): columns × devices → one table, one row per device per cycle. The hand-authored Examples + `OPCUA.Tests` classes are a separate declarative path (typed `OPCUA.Types.*` properties → `TCPPollingService`/`TCPSubscriptionService`) kept for the test harness — **do not regress it**.
- **Adapters must connect before resolving.** `ResolveSpecification()` browses the server, so it needs a live session; both adapters call `##super()` first, then resolve, then prepare the query. This ordering is load-bearing.
- **`%SerialObject` subclasses** are generated for nested folder hierarchies and appear as `Property_SubProperty` columns in SQL.
- **The Projection** (`OPCUA.DataSource.Projection`) fires on every DataSource class compile, writes `^OPCUA.DataSource(className)`, and generates `SaveSourcedData()`. The runtime services depend entirely on this global.
- **Do not call `$Get(obj.prop)`** — use `obj.prop` directly or `obj.%Get("prop")` (see ObjectScript Gotchas in parent CLAUDE.md).
