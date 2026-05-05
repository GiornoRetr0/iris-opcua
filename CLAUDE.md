# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Detailed architecture, ObjectScript gotchas, C++ bridge, REST API, globals, and security are documented in `ARCHITECTURE.md` and `PIPELINE-ARCHITECTURE.md` in this directory. The parent `CLAUDE.md` (loaded automatically) consolidates all of that for Claude.**

## Quick Command Reference

### Docker environment
```bash
./generate_certificates.sh          # Generate TLS certs (required before first build)
docker compose up                    # Start all containers (iris, plc, plc2, certified-server)
docker compose build                 # Rebuild iris + certified-server images after source changes
```

### Angular webapp (pipeline wizard)
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

# Run tests
printf 'zn "APPINT"\nw ##class(OPCUA.Tests.DataTest).Run()\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris

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
| `webapp/src/app/` | Angular 19 pipeline wizard (standalone components, signals, Tailwind) |
| `webapp/src/app/core/models/opcua.models.ts` | All TypeScript interfaces (`TreeNode`, `V2Selection`, `DeployV2Request`, etc.) |
| `webapp/src/app/pages/pipeline-wizard/` | Single 1400-line wizard component + models/services subdirs |
| `webapp/src/app/core/services/api.service.ts` | REST client (browse, deploy, editPipeline, listPipelines) |
| `chrome-extension/` | Chrome extension — auto-detects API URL from page URL |
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

- **Pipelines run in the `OPCUA` namespace**, not `APPINT`. Tests run in `APPINT`.
- **All REST endpoints accept both GET (query params) and POST (JSON body).** Connection param is `url`, not `serverUrl`.
- **v2 pipelines** use the row-source model (columns × devices → one table). v1 is legacy single-device.
- **`%SerialObject` subclasses** are generated for nested folder hierarchies and appear as `Property_SubProperty` columns in SQL.
- **The Projection** (`OPCUA.DataSource.Projection`) fires on every DataSource class compile, writes `^OPCUA.DataSource(className)`, and generates `SaveSourcedData()`. The runtime services depend entirely on this global.
- **Do not call `$Get(obj.prop)`** — use `obj.prop` directly or `obj.%Get("prop")` (see ObjectScript Gotchas in parent CLAUDE.md).
