# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Detailed architecture, ObjectScript gotchas, C++ bridge, REST API, globals, security, and the schema + device-binding model are documented in `docs/architecture.md`. The parent `CLAUDE.md` (loaded automatically) consolidates all of that for Claude.**

## Quick Command Reference

### Docker environment
```bash
./demo/certgen/generate.sh           # Generate TLS certs (required before first build)
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

# Load sources and tests without rebuilding the image (non-zero exit on any compile error)
./demo/iris/dev-load.sh

# Run the tests: all %UnitTest. Offline = OPCUA.Tests.Unit (no server, no native
# library, no running production; CI-safe). Live = OPCUA.Tests.Live (docker plc,
# plus certified-server for the secured and type-inference tests). Each returns 1
# only if nothing failed; skipped tests (server unreachable) are listed, not passed.
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.Runner).Offline()\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.Runner).Live()\nhalt\n'    | docker exec -i iris-opcua-iris-1 iris session iris

# Check production status
printf 'zn "OPCUA"\ndo ##class(Ens.Director).GetProductionStatus(.p,.s) write p," ",s,!\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris

# Tail event log
printf 'zn "OPCUA"\nset rs=##class(%%SQL.Statement).%%ExecDirect(,"SELECT TOP 10 Type,ConfigName,$extract(Text,1,200) FROM Ens_Util.Log ORDER BY ID DESC") while rs.%%Next() { write rs.Type," | ",rs.ConfigName," | ",rs.%%GetData(3),! }\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris
```

> **Source changes in `backend/` are not hot-reloaded.** Run `./demo/iris/dev-load.sh` to load them into the running container, or rebuild the image (`docker compose build`).

## Repository Layout (what lives where)

| Path | Contents |
|------|----------|
| `backend/src/OPCUA/` | All production ObjectScript: Client, Adapters, Services, REST, DataSource, Types, Security (managed Sign & Encrypt). This is exactly what a client install ships |
| `backend/tests/OPCUA/Tests/` | `%UnitTest` classes: `Unit/` (offline, `OPCUA.Tests.Unit`) and `Live/` (docker servers, `OPCUA.Tests.Live`), run by `OPCUA.Tests.Runner`; shared fixtures, `*DS` data sources and `Production.cls` at the top level |
| `backend/examples/Examples/` | Demo Business Services (PollingExample, SubscriptionExample, SecureExample, ArrayExample, etc.) |
| `backend/native/linux-{amd64,arm64}/` | Prebuilt Unix shared objects (`.so`), picked by `TARGETARCH` |
| `backend/native/windows-x64/` | Prebuilt Windows DLLs; `IrisOPCUA.dll` is cross-built with llvm-mingw (UCRT) by `opc-ua-master/docker/build-win64.sh` |
| `installer/` | Rust terminal installer (`iris-opcua-setup`); embeds `backend/src/OPCUA/`, the Linux and Windows native libraries, the console build (`webapp/dist/webapp/`, so run `npx ng build` first) and its own `objectscript/IRISConfig/ClientInstaller.cls`. Installs the console as a file-only IRIS web app beside the REST API (`/csp/opcua/api` → `/csp/opcua/ui`) |
| `webapp/src/app/` | Angular 19 console (standalone components, signals, Tailwind) |
| `webapp/src/app/core/models/opcua.models.ts` | All TypeScript interfaces (`TreeNode`, `Schema`, `DeviceValidation`, `PipelineHealth`, etc.) |
| `webapp/src/app/pages/schema-library/`, `schema-builder/` | Schema list + creation |
| `webapp/src/app/shared/settings-modal/` | Settings tabs; `security-tab/` (OPC UA Security: instance identity) and `server-security/` (per-profile readiness rows, certificate review/trust) |
| `webapp/src/app/pages/device-binding/` | Bind devices to a schema; also serves pipeline edit |
| `webapp/src/app/shared/opcua-tree/` | Embeddable single-server address-space browser |
| `webapp/src/app/core/services/api.service.ts` | REST client (browse, deploy, editPipeline, listPipelines) |
| `demo/iris/` | IRIS image Dockerfile, install script and `IRISConfig/Installer.cls` (namespace/DB setup run during the Docker build); builds with the **repo root** as context |
| `demo/certified-server/` | OPC Foundation certified server image |
| `demo/certgen/` | OpenSSL configs, `certgen.bash`, and `generate.sh` |
| `demo/mock-data/data.csv` | Data served by the `plc` and `plc2` mock OPC UA servers |
| `legacy/windows-studio/` | Studio project XML for native Windows IRIS install |
| `docs/` | `architecture.md`, `workflow.md`, `decisions/`; plans and reviews in `docs/design/` |

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

- **Everything runs in the `OPCUA` namespace.** There is no `APPINT` namespace in this compose setup, and the public server `OPCUA.Tests.Live.DataTest` needs (`opc.tcp://opcuaserver.com:48010`) fails the OPC UA handshake from here, so DataTest reports *skipped*. The test suite is `%UnitTest` in two packages: `OPCUA.Tests.Unit` (offline; `Runner.Offline()`) and `OPCUA.Tests.Live` (docker `plc`, plus `certified-server` for `SecuredPipelineTest` and `TypeInferenceTest`; `Runner.Live()`). A test whose server is unreachable calls `$$$AssertSkipped`, never passes. The declarative regression gate is still: poll the local `plc` server through `PollingExample` / `SubscriptionExample` and assert rows land with real values.
- **The OPC UA Console is for SuperUser-level developer accounts.** An account with only the installer's `OPCUA_API_<NS>` role can manage schemas and anonymous pipelines (`OPCUA.Tests.Live.ApiRoleTest`), because the console's queries need no SQL privilege: keep it that way (embedded SQL or direct dictionary reads, not `%ExecDirect`, on any path the role uses; a remaining -99 in `Utils.ExecQuery` becomes a 403). It cannot read or write credentials (`%Ens_Credentials`, 403), so pipelines for servers that need a username are out of its reach; row counts show as unknown.
- **Schema creation and device binding are separate, deliberately.** `POST /schemas` generates a schema class with **no** production side effects; `POST /deploy` binds devices to an existing schema and **generates nothing**. Do not reintroduce a combined create-and-deploy path — the split is a requirement, not an accident.
- **A schema is reusable and outlives its pipelines.** Several pipelines may share one. Deleting a pipeline must never delete its schema; `SchemaService.Delete` is the only deletion path and it refuses while any pipeline references the schema.
- **Devices are resolved by name at connect time**, never frozen at deploy time. `DeviceNodePaths` is an ordinary production setting, so adding a device is a one-line edit with no regeneration and no recompile. Nothing about devices is stored — masks and node IDs are derived by browsing on every (re)connect.
- **Editing a pipeline changes only devices + strictness** (`POST /pipelines/rebind`). Changing a schema's *columns* is not possible anywhere; recreate the schema, which drops the table.
- **All REST endpoints accept both GET (query params) and POST (JSON body)**, except `/schemas`, `/credentials` and `/security`, which use real verbs. Connection param is `url`, not `serverUrl`.
- **The console stores no password.** It signs in to IRIS once through the REST app's JWT `POST /login` (installer and demo switch JWT on) and keeps only the tokens, in sessionStorage; `AuthService` refreshes them single-flight, since IRIS revokes a refresh-token chain on replay. Without JWT on the app it falls back to Basic held in memory. Do not put the IRIS password back into localStorage.
- **OPC UA passwords live only in IRIS credentials entries.** A console server profile stores a `credentials` ID, never a username or password; `ClientManager.ExtractConnectionParams` reads the entry on the server, and deploy puts the same ID in the pipeline, so the console and its pipelines share one entry. Inline `username`/`password` remain only for testing an unsaved login. Older consoles' stored OPC UA passwords are dropped on load, not migrated. `/credentials` never returns a password.
- **Every pipeline uses the row-source services** (`TCP*RowSourceService`): columns × devices → one table, one row per device per cycle. The hand-authored Examples + `OPCUA.Tests` classes are a separate declarative path (typed `OPCUA.Types.*` properties → `TCPPollingService`/`TCPSubscriptionService`) kept for the test harness — **do not regress it**.
- **Adapters must connect before resolving.** `ResolveSpecification()` browses the server, so it needs a live session; both adapters call `##super()` first, then resolve, then prepare the query. This ordering is load-bearing.
- **A measurement is value + status + source timestamp + server timestamp**, and generated schemas store all four per column by typing each column as an `OPCUA.Types.*DataValue`. SQL therefore exposes `Temperature_Value`, `Temperature_Status`, `Temperature_SourceTS`, `Temperature_ServerTS` (the timestamps' `SqlFieldName`s; the properties keep their long names). There is no row-level timestamp pair. Do not map columns back to plain IRIS types — that is what made the two storage models disagree.
- **The server timestamp is optional per schema.** `POST /schemas` with `includeServerTimestamp: false` (default `true`; a checkbox in the schema builder) types every column, flat or nested, as its `OPCUA.Types.NoServerTS.*` counterpart: a separate `%SerialObject` family without a `ServerTimeStamp` property, so no `*_ServerTS` column exists. The native layer still returns the full DataValue (projection code 2), and `RowWriter` removes element 2 before storing. That makes these types valid only in RowWriter-backed schemas, never in hand-authored Definitions. `Resolver.IsMeasurementType()` recognises both families. Keep the two families in step: a new `OPCUA.Types.X` needs an `OPCUA.Types.NoServerTS.X` with the same payload properties in the same order.
- **Column types come from the node's declared DataType + ValueRank**, not from its value (`Generator.InferType()`). The native single-attribute read supports only Value (and returns arrays as null), so these attributes are read with a one-shot `ReadBulkSetupC` / `ReadBulkPollC` / `ReadBulkClear`. Keep the Value out of that query: an unconvertible value (Guid, ExtensionObject) fails the whole poll. The value-pattern guess is only the fallback for unknown DataTypes.
- **Status is stored raw, and quality is reported on change.** Each column's `Status` holds the server's 32-bit StatusCode unchanged; there is no derived severity column. `RowWriter.BuildRow` tracks Good/Uncertain/Bad per device and column and returns what changed; `LogQualityChanges` writes one event-log line per device per change (warning when worse, info on recovery). A Bad reading has no value: it arrives as `$LB(srcTS, srvTS, status, <null>)`, so read element 4 with `$ListGet`, never `$List`. Polling delivers Bad readings only with a native library built from the `readBulkPollC` change that stops dropping value-less DataValues; subscriptions always did.
- **Row assembly has exactly one implementation**, `OPCUA.DataSource.RowWriter`. Polling and subscription services both delegate to it. Do not fork it back into the services.
- **`%SerialObject` subclasses** are generated for nested folder hierarchies and appear as `Property_SubProperty` columns in SQL. A folder serial object holds DataValue serial objects, so a nested measurement reads as `row.Motor.Temperature.Value`.
- **The Projection** (`OPCUA.DataSource.Projection`) fires on every DataSource class compile, writes `^OPCUA.DataSource(className)`, and generates `SaveSourcedData()`. The runtime services depend entirely on this global.
- **Sign & Encrypt is managed by default, manual if paths are given.** SecurityMode 3 with no `certPath`/`keyPath` (adapter `PublicCertificate`/`PrivateKey`) uses `OPCUA.Security.*`: one client identity per IRIS instance (`<mgr>/opcua-pki/own/`, config in `^%OPCUA.Security`, shared by every namespace) and per-server trust keyed by the normalised URL. Explicit paths keep the old behaviour exactly (demo `SecureExample`, `/usr/irissys/uac/certs/*`). Never mix the two.
- **Empty trust list = trust everything** (open62541 1.2.1). Managed connects must refuse *before* the native setup call when a server has no trusted certificate, no pin, or a CA-issued certificate without issuer + CRL (`Trust.Pin`), and must never fall back to SecurityMode 1.
- **Managed connections are pinned** (SHA-256 of the reviewed certificate, ordinal 52 `SetServerPin`, plus SAN host check) on top of normal chain/CRL/expiry checks. Trust stores only a certificate IRIS fetched itself whose fingerprint equals the one the user confirmed. A changed certificate is shown for approval, never accepted silently.
- **Approval is external.** The server administrator trusts IRIS's certificate; IRIS only offers the DER/PEM download and fingerprint, and `Diagnose` explains `clientNotApproved`. `/security/*` needs `%Admin_Secure:USE` (403 otherwise). No private key in a REST response, log, error or exported global.
- **Native ordinals are appended**: 1–52; 48–52 (PKI + `zfSetServerPin`) arrive with connector 0.5.0; `OPCUA.Utils.SupportsPki()` gates them. Installer 0.5.0 embeds `backend/src/OPCUA/**` (including `Security/`) and the 0.5.0 natives automatically.
- **Security tests never touch the real store**: set `^%OPCUA.Security.Override` (root + global) and kill it in `OnAfterAllTests`. `./demo/iris/secure-e2e.sh` runs the end-to-end approval flow against `certified-server` (phases via `OPCUA.Tests.Runner.Run("Class:Method")`). Docker volume `iris-opcua-pki` → `/usr/irissys/mgr/opcua-pki` keeps the identity across rebuilds.
- **Do not call `$Get(obj.prop)`** — use `obj.prop` directly or `obj.%Get("prop")` (see ObjectScript Gotchas in parent CLAUDE.md).
