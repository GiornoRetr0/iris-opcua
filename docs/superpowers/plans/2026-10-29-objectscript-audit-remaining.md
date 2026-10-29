# ObjectScript audit — remaining items: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every open item in `docs/design/objectscript-audit.md` (10–19, Smaller issues, AI-pattern sweep, Test suite) so the adapter can go to its first client.

**Architecture:** Fixes land in the existing ObjectScript services (`backend/src/OPCUA/REST`, `Adapter`, `Types`, `Utils`), the Angular console, the installer's `ClientInstaller.cls` and the demo `Installer.cls`. Two small new pieces carry the cross-cutting work: `OPCUA.REST.ProductionEdit` (one locked, stale-checked read-modify-save of the pipeline production) and `OPCUA.REST.Error` (statuses that carry their HTTP code). Tests move to `%UnitTest.TestCase`: `OPCUA.Tests.Unit.*` (offline, CI) and `OPCUA.Tests.Live.*` (docker `plc`).

**Tech Stack:** InterSystems IRIS 2025.3 (ObjectScript, Interoperability), Angular 19 (signals, standalone), Docker compose, GitHub Actions, Rust installer (unchanged except for its embedded `ClientInstaller.cls`).

**Spec:** `docs/superpowers/specs/2026-10-29-objectscript-audit-remaining-design.md`. Read it before starting a task. Its decisions are binding, and the "When to stop and ask" list applies to every task.

## Global Constraints

- All work on branch `docs/objectscript-audit`. One commit per task, or one per audit item where a task covers several. Concise conventional-prefix messages, **no Co-Authored-By trailer** (user memory).
- No backwards compatibility: setting names, SQL types, HTTP codes and response shapes may change. The webapp changes in the **same commit** as the API it depends on.
- Never change, stop or delete anything the client owns: other productions, other classes, credentials entries we didn't create, web apps we didn't create.
- Architecture rules in both CLAUDE.md files hold: schema creation ≠ deploy, `RowWriter` is the only row assembler, adapters connect before resolving, no device-metadata global, and the two type families stay in step.
- Verification runs in the Linux docker stack only (`iris-opcua-iris-1`, `plc`, `plc2`, `certified-server`), on IRIS 2025.3. Windows is out of scope.
- **Regression gate after every task:** `OPCUA`, `Examples` and the test packages compile clean. The old harnesses `MeasurementMetadataTest`, `PortalPipelineTest` and `ResolverTest` pass against `plc` until Task 14 replaces them, and the Task 0 runners pass after that. The declarative `PollingExample` path stores real values (check in Task 9 and Task 16, where `Common` changes).
- Every fix comes with a test that fails on the old code and passes on the new one. Run it red before the fix.
- Every task that closes an audit item updates `docs/design/objectscript-audit.md` the way 1–9 were written up: ✅, strike-through title, **Fixed YYYY-MM-DD**, **Fix:**, **Verified:** (with suite counts). It also notes any "my call" from the spec it overturned.
- **Stop and ask the user** (`AskUserQuestion`) when: a fix needs a C++ change; a fix would touch anything outside our namespace, classes, productions or web apps; a spec "my call" turns out wrong or impossible; the Portal race (#10) can't be closed; CI can't run offline tests without the native library.

## Review Focus

1. **Pipeline and schema names with dots, spaces, hyphens or mixed case.** The credentials ID, the lock, table names and `usedBy` all derive from names. Expected: deploy, rebind, delete and schema delete all work, and the credentials ID is a valid `Ens.Config.Credentials` ID. Tests in Task 3 (lock/save) and Task 9 (credentials ID).
2. **Bad StatusCodes (≥ `0x80000000`) in SQL.** `WHERE Temperature_Status >= 2147483648` and `ORDER BY` must behave numerically, not as strings or negatives. Test in Task 8.
3. **Production not in Running state** (Stopped, Troubled, Suspended) during toggle and rebind. Expected: the device list is saved, and the response says the restart didn't happen and why. It never claims `restarted=1`. Test in Task 3.
4. **The IRIS session goes bad mid-use in the hosted console** (password changed, account disabled). Expected: the next call gets 401, and the console shows "sign-in failed" and opens Settings, rather than a generic error or a browser pop-up. Test in Task 6.
5. **Deploy with a username and an empty password, or neither** (anonymous servers). Expected: with neither, no credentials entry is created. With a username only, an entry is created with an empty password. A secured rebind still validates. Test in Task 9.

---

## Dev loop (used by every task)

Task 0 creates `demo/iris/dev-load.sh`. After that, every "load" step means:

```bash
docker compose up -d                       # once per session
./demo/iris/dev-load.sh                    # copies backend/src, tests, examples into the container; LoadDir "ck"; non-zero exit on any compile error
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.Runner).Offline()\nhalt\n' | docker exec -i iris-opcua-iris-1 iris session iris
printf 'zn "OPCUA"\nw ##class(OPCUA.Tests.Runner).Live()\nhalt\n'    | docker exec -i iris-opcua-iris-1 iris session iris
```

Old harnesses run as in `iris-opcua/CLAUDE.md` until Task 14.

---

### Task 0: Dev loop and `%UnitTest` scaffolding

**Files:**
- Create: `demo/iris/dev-load.sh`
- Create: `backend/tests/OPCUA/Tests/Runner.cls`
- Create: `backend/tests/OPCUA/Tests/Unit/SmokeTest.cls`, `backend/tests/OPCUA/Tests/Live/SmokeTest.cls`

**Interfaces:**
- Produces: `OPCUA.Tests.Runner.Offline() As %Boolean`, which runs every `%UnitTest.TestCase` in package `OPCUA.Tests.Unit`, prints a pass/fail summary with each failed assertion, and returns 1 only if all pass. `OPCUA.Tests.Runner.Live(pURL As %String = "opc.tcp://plc") As %Boolean` does the same for `OPCUA.Tests.Live`, and exposes the URL to tests as `^||OPCUA.Tests("url")`. `OPCUA.Tests.Runner.Exit(pOK As %Boolean)` ends the process with exit code 0/1 (for CI).
- Produces: the convention that new tests go into `OPCUA.Tests.Unit.<Area>Test` (no server, no native library) or `OPCUA.Tests.Live.<Area>Test` (needs `plc`).

- [ ] **Step 1:** Write `dev-load.sh`. It runs from any cwd (resolve the repo from the script's own location, like `demo/certgen/generate.sh`), `docker cp`s `backend/src`, `backend/tests` and `backend/examples` into `/tmp/opcua-dev/`, loads `Constants.inc` first, runs `$System.OBJ.LoadDir(dir,"ck",.err,1)` for each, prints the errors, and exits non-zero if any. The container name defaults to `iris-opcua-iris-1`, overridable with `IRIS_CONTAINER`.
- [ ] **Step 2:** Write the two `SmokeTest` classes, each with one passing `TestTruth` and one deliberately failing `TestFailureIsReported` (temporary, removed in Step 5).
- [ ] **Step 3:** Implement `Runner` on `%UnitTest.Manager` with already-loaded classes (`/noload/nodelete`). Read results from `%UnitTest.Result.*` for the run's `LogIndex`, not by parsing output.
- [ ] **Step 4:** Run `Offline()` and `Live()`. Expected: each reports 1 passed and 1 failed, names the failing assertion, and returns 0. `Exit(0)` from `iris session` gives shell `$?` = 1.
- [ ] **Step 5:** Delete the failing methods. Rerun: both return 1, and `$?` = 0.
- [ ] **Step 6:** Commit: `test: add %UnitTest runner and dev load script`.

### Task 1: #19 Deleting a pipeline leaves its config item row

**Files:**
- Modify: `backend/src/OPCUA/REST/PipelineService.cls` (`Delete`, around `:365`)
- Modify: `backend/tests/OPCUA/Tests/PortalPipelineTest.cls` (`Cleanup`)
- Create: `backend/tests/OPCUA/Tests/Live/PipelineLifecycleTest.cls`

- [ ] **Step 1: Failing test** `TestDeleteThenRecreateSameName`: deploy pipeline `TmpLifecycle` through `DeployService.Deploy` (schema built offline as in `PortalPipelineTest.BuildSchema`), enable it, delete it through `PipelineService.Delete`, deploy again under the same name, then `Toggle` it.
  - `$$$AssertStatusOK` on the toggle.
  - `$$$AssertEquals` on the count of `Ens_Config.Item` rows `WHERE Name='TmpLifecycle'` after the delete: 0.
- [ ] **Step 2:** Run red. Expected: toggle fails with "Pipeline 'TmpLifecycle' not found", and the row count is 1.
- [ ] **Step 3:** After `RemoveAt` + `%Save` + `SaveToClass`, `##class(Ens.Config.Item).%DeleteId(id)` (capture the ID before `RemoveAt`), with its status checked. Same in `PortalPipelineTest.Cleanup`.
- [ ] **Step 4:** Run green, plus the regression gate.
- [ ] **Step 5:** Update audit #19, commit `fix(pipelines): delete a removed pipeline's config item row`.

### Task 2: Small contained fixes

One commit per bullet group, each with its own test.

**Files:**
- Modify: `backend/src/OPCUA/DateTimeUtils.cls:94,113`; `backend/src/OPCUA/Utils.cls:15-60`; `backend/src/OPCUA/REST/Handler.cls` (`GetRequestParams`); `backend/src/OPCUA/REST/SchemaService.cls:772` (`TableName`), `PipelineService.cls:78,221`; `backend/src/OPCUA/Client.cls` header; `../CLAUDE.md`, `CLAUDE.md`, `docs/architecture.md` (drop `StrictSchemaMatch`)
- Create: `backend/tests/OPCUA/Tests/Unit/UtilsTest.cls`, `Unit/SchemaNamingTest.cls`, `Live/RestBodyTest.cls`

**Interfaces:**
- Produces: `OPCUA.REST.SchemaService.TableName(pClassName As %String) As %String`, which returns the compiled class's `SqlQualifiedNameQ`-equivalent unquoted `Schema.Table` (honours `SqlTableName` / `SqlSchemaName`). Every table-name site calls it.

- [ ] **2a — DateTimeUtils typo.** Test `UtilsTest.TestDateConvVariables`: run a static check that both methods compile without `tRetVal` (search `%Dictionary.MethodDefinition` implementation for `tRetVal`, case-sensitive; expect 0). Red, then rename to `tRetval`, then green.
- [ ] **2b — Library-not-found keeps its reason.** Test `UtilsTest.TestMissingLibraryReason`: point `GetLibPathname` at a non-existent file (use the override it reads; if none exists, add `^||OPCUA.LibPathOverride` for tests only). Call `Initialize()` and `$$$AssertTrue` that the error text contains the missing path and does **not** contain "Invalid status code structure". Fix: keep the first `tSC` (don't reset to `$$$OK` after a failure), and replace both `CreateFromStatus(0)` throws with a real `$$$ERROR($$$GeneralError,"IrisOPCUA library is not loaded: "_reason)`.
- [ ] **2c — Large bodies.** Test `RestBodyTest.TestLargeBody`: POST a 1.5 MB JSON body (a `devices` string padded with comment lines) to `/schemas/<tmp>/validate` via `%Net.HttpRequest` to `localhost:52773/csp/opcua/api` (SuperUser/SYS). Assert the response is a validation result, not "Invalid request". Fix: `pBody = {}.%FromJSON(%request.Content)` when `Content` is a stream; keep the string branch.
- [ ] **2d — Table names.** Test `SchemaNamingTest.TestTableNameHonoursSqlTableName`: generate a tmp schema class with `SqlTableName = "Custom_T"`, and assert `TableName()` returns `<schema>.Custom_T`, and that `PipelineService.List`'s `tableName` for an item on it matches. Fix: implement `TableName` from `%Dictionary.CompiledClass` (`SqlSchemaName`, `SqlTableName`). Replace the two hand-built sites in `PipelineService`.
- [ ] **2e — Stale docs.** Remove `StrictSchemaMatch` from both CLAUDE.md files and `docs/architecture.md` (the device-binding text: unresolved columns store NULL and log a warning, and that's the whole behaviour). Fix the `Client.cls` header to describe SecurityMode 1 and 3 as implemented. No test.
- [ ] **Step final:** Regression gate. Update the audit "Smaller issues" bullets these close. Commits: `fix(utils): …`, `fix(rest): read the whole request body`, `fix(rest): one table-name helper that honours SqlTableName`, `docs: drop StrictSchemaMatch and the stale security note`.

### Task 3: #10 Production edits locked, rebind in one save, honest restart reporting

**Files:**
- Create: `backend/src/OPCUA/REST/ProductionEdit.cls`
- Modify: `backend/src/OPCUA/REST/DeployService.cls` (`AddServiceItem`, `StartOrUpdateProduction`), `PipelineService.cls` (`Toggle`, `Delete`, `Rebind`, `UpdateDeviceNodePaths`, `UpdateCategories`, `UpdateItemField`)
- Create: `backend/tests/OPCUA/Tests/Unit/ProductionEditTest.cls`, `Live/PipelineConcurrencyTest.cls`

**Interfaces:**
- Produces, in `OPCUA.REST.ProductionEdit`:
  - `Parameter LockTimeout = 10;` (seconds)
  - `ClassMethod Begin(Output pProd As Ens.Config.Production, Output pStamp As %String) As %Status`: takes `Lock +^OPCUA.ProductionEdit:..#LockTimeout`, opens `OPCUA.Pipeline.Production` fresh (`%OpenId(..., 0)` or after `%Reload`), and records the production's change stamp. On timeout it returns an `OPCUA.REST.Error` 409 with "Another change to the pipelines is in progress; try again." (until Task 6 exists, a plain `$$$GeneralError` with the same text).
  - `ClassMethod Commit(pProd As Ens.Config.Production, pStamp As %String) As %Status`: refuses (409, "The pipeline production was changed by someone else (for example in the Management Portal); reload and try again.") if the stamp changed since `Begin`. Otherwise `%Save` then `SaveToClass`, with both statuses checked.
  - `ClassMethod End()`: `Lock -^OPCUA.ProductionEdit`. Always called (Try/Catch-safe).
  - `ClassMethod UpdateItem(pItemName As %String, pSettings As %DynamicObject = "", pFields As %DynamicObject = "") As %Status`: `Begin`, then find the item, apply `pSettings` (`{"Adapter":{"DeviceNodePaths":"…"}}`, inserting missing settings) and `pFields` (`{"Category":"…"}`), then `Commit` and `End`.
- Rebind response: `restarted` is `1` only if `UpdateProduction` returned OK. Otherwise the whole call returns an error: "Device list saved, but the running pipeline could not be restarted: <reason>" (the save is not rolled back).

- [ ] **Step 1: Investigate the Portal race** before writing code. In the container, open the production in the Portal's config page (or simulate it: `%OpenId` copy A, then copy B; change and save B through `SaveToClass`; then save A). Record what IRIS does (silent overwrite, or an error) and which stamp is reliable: the production class's `%Dictionary.ClassDefinition.TimeChanged`, or `Ens.Config.Production` storage, or both. Put the finding in the audit #10 write-up. If no reliable stamp exists, **stop and ask**.
- [ ] **Step 2: Failing tests** in `ProductionEditTest` (offline, tmp production `OPCUA.Tests.Tmp.EditProduction`, using a `Parameter ProductionClass` override hook on `ProductionEdit` for tests):
  - `TestLockBusy`: hold `^OPCUA.ProductionEdit` from a `JOB`bed process, call `Begin` with a 1-second timeout override, and assert the error text contains "in progress". Release the lock in teardown.
  - `TestStaleCommitRefused`: `Begin`, change the production through a second `%OpenId` + `SaveToClass`, `Commit`, and assert the error contains "changed by someone else". Assert the second change survived.
  - `TestUpdateItemOneSave`: `UpdateItem` with both a setting and a field. Assert both landed, and `TimeChanged` moved once (one `SaveToClass`).
  - `TestNamesWithPunctuation` (Review Focus 1): `UpdateItem` on item `"Line 3.Press-A"`.
- [ ] **Step 3: Failing live test** `PipelineConcurrencyTest.TestParallelRebinds`: `JOB` two rebinds of the same pipeline with different device lists, then wait for both. Assert the final `DeviceNodePaths` equals exactly one of the two lists, and the other call returned "in progress" or succeeded before it (never both "succeeded" with one lost). Plus `TestRebindWhenProductionNotRunning` (Review Focus 3): stop the production, rebind, and assert the response has no `restarted=1` and the device list was saved. Then mark the production `Troubled` (or stub `GetProductionStatus` via a test hook if Troubled can't be forced), rebind, and assert the error text starts "Device list saved, but".
- [ ] **Step 4:** Run red.
- [ ] **Step 5:** Implement `ProductionEdit`. Route every production read-modify-save in `DeployService` and `PipelineService` through it. Replace `UpdateDeviceNodePaths` / `UpdateCategories` / `UpdateItemField` with one `UpdateItem` call per rebind. Check every ignored status the audit names on these paths (`UpdateProduction`, `EnableConfigItem`, `GetProductionStatus`).
- [ ] **Step 6:** Green, plus the regression gate. Update audit #10 and the "Ignored statuses" bullet (the production-path part). Commit `fix(pipelines): lock production edits and refuse stale saves`.

### Task 4: #11 Schema delete checks every production

**Files:**
- Modify: `backend/src/OPCUA/REST/SchemaService.cls` (`MapSchemaUsage`, `UsageArray`, `Delete`, `DescribeSchema`), `PipelineService.cls` (its `MapSchemaUsage` caller)
- Modify: `webapp/src/app/core/models/opcua.models.ts` (`Schema.usedBy`), `webapp/src/app/pages/schema-library/*`
- Create: `backend/tests/OPCUA/Tests/Unit/SchemaUsageTest.cls`

**Interfaces:**
- Produces: `SchemaService.MapSchemaUsage(Output pUsage) As %Status`, with `pUsage(schemaClass, production, itemName) = ""`. It covers every row of `Ens_Config.Production`, and any failure is a returned error.
- Produces: `usedBy` JSON is an array of `{ "name": item, "production": prod, "managed": true|false }`, where `managed` = (`production` = `OPCUA.Pipeline.Production`).
- TS: `usedBy: { name: string; production: string; managed: boolean }[]`.

- [ ] **Step 1: Failing tests:**
  - `TestUsageInHandBuiltProduction`: create tmp production `OPCUA.Tests.Tmp.ClientProd` with an item whose `DataSourceClass` is a tmp schema, then call `Delete`. Assert the error names both the item and `OPCUA.Tests.Tmp.ClientProd`, and that the class still exists.
  - `TestUsageFailureRefusesDelete`: force `MapSchemaUsage` to fail (test hook `^||OPCUA.Tests("failUsage")=1`, read only by `MapSchemaUsage`). Assert `Delete` returns an error and the class still exists.
  - `TestUsedByShape`: `DescribeSchema` returns `usedBy[0].managed = 0` for the hand-built item.
- [ ] **Step 2:** Run red.
- [ ] **Step 3:** Implement. Iterate `Ens_Config.Production` (SQL), open each, scan items. No empty `Catch {}`. Delete's message: "Schema 'X' is still used by: Item (Production), …".
- [ ] **Step 4:** Webapp: the schema library shows managed usages as links to the edit page (as now), and unmanaged ones as plain text "Item (in production P, managed in the Management Portal)". Delete stays disabled while `usedBy` is non-empty. `npx tsc --noEmit` and `npx ng build` clean.
- [ ] **Step 5:** Green, plus the regression gate. Update audit #11. Commit `fix(schemas): refuse delete while any production uses the schema`.

### Task 5: #12 Schema creation leaves no debris; serial-class delete stays in its lane

**Files:**
- Modify: `backend/src/OPCUA/REST/SchemaService.cls` (`Create`, `GenerateSchemaClass`, `GenerateSerialClasses`), `PipelineService.cls` (`DeleteSerialSubclasses`)
- Create: `backend/tests/OPCUA/Tests/Unit/SchemaCreateTest.cls`

**Interfaces:**
- `GenerateSchemaClass` and `GenerateSerialClasses` keep their signatures. On any error, they leave no class they created.
- `DeleteSerialSubclasses(pClassName)` deletes a property's serial type only if its name equals `SerialClassName(pClassName, <OPCUANODENAME>)` **and** no other compiled class (outside `pClassName`) has a property of that type. Returns `%Status` (errors now propagate to `SchemaService.Delete`).

- [ ] **Step 1: Failing tests:**
  - `TestNameTakenRefusedUpfront`: pre-create the serial class name a nested schema would use. Assert `Create` fails with "already exists" naming that class, and that the main class does **not** exist afterwards.
  - `TestFailedCompileCleansUp`: make the main class fail to compile (test hook that injects an invalid property type). Assert every serial class created by the call is gone, and an immediate retry without the hook succeeds.
  - `TestSharedSerialClassKept`: a hand-written class `OPCUA.Tests.Tmp.HandWritten` with a property typed as schema S's serial class. Delete S, and assert the serial class still exists.
- [ ] **Step 2:** Run red.
- [ ] **Step 3:** Implement: check all target names upfront, keep a local list of created classes, and in `Catch` (and on error status) `$System.OBJ.Delete` each, with `-d`. Return the original error, plus a note if the cleanup itself failed.
- [ ] **Step 4:** Green, plus the regression gate. Update audit #12 and the "Schema delete can remove a shared class" bullet. Commit `fix(schemas): roll back a failed schema creation`.

### Task 6: HTTP status mapping and #16 (401 on bad login)

**Files:**
- Create: `backend/src/OPCUA/REST/Error.cls`
- Modify: `backend/src/OPCUA/REST/Handler.cls` (every route method, `Login`, `SendError`); services that produce not-found / conflict errors (`SchemaService`, `PipelineService`, `DeployService`, `ProductionEdit`)
- Modify: `webapp/src/app/core/services/api.service.ts`, the settings / sign-in flow in hosted mode
- Create: `backend/tests/OPCUA/Tests/Unit/ErrorMappingTest.cls`, `Live/RestStatusTest.cls`

**Interfaces:**
- Produces in `OPCUA.REST.Error`:
  - `ClassMethod Make(pHttp As %Integer, pMessage As %String) As %Status`, which builds `$$$ERROR($$$GeneralError, pMessage, pHttp)` (the HTTP code rides as the status's second parameter).
  - `ClassMethod NotFound(pMessage)`, `Conflict(pMessage)`, `BadRequest(pMessage)`: thin wrappers for 404 / 409 / 400.
  - `ClassMethod HttpCode(pSC As %Status) As %Integer`: the carried code, else 400 for a plain `$$$GeneralError`, else 500.
- `Handler.Respond(pSC As %Status, pData) As %Status`: OK → `SendOK`. Otherwise it sets `%response.Status` from `HttpCode`. For 500 it logs the full status to the application error log (`##class(%Exception.StatusException).CreateFromStatus(pSC).Log()`) and returns `{"status":"error","error":"Internal error. Reference <ref>","ref":"<ref>"}`, where `<ref>` is `$ZDateTime($Horolog,8)_"-"_$Job`, which is also written into the logged text. All route methods end with `Quit ..Respond(tSC, tResult)`.
- Mapping (from the spec): bad input 400, not found 404, conflict (in use, another production, lock busy, stale save, name taken) 409, failed login 401, anything else 500.
- `Login`: returns 401 with the envelope `{"status":"error","error":"Sign-in failed"}` and **no** `WWW-Authenticate` header.
- Webapp: one `apiErrorMessage(err: unknown): string` in `api.service.ts`, which reads the envelope from `HttpErrorResponse.error` for any status. On 401 in hosted mode, the console shows "Sign-in failed" and opens Settings.

- [ ] **Step 1: Failing tests:**
  - Offline `ErrorMappingTest`: `HttpCode(Make(409,"x"))=409`; `HttpCode($$$ERROR($$$GeneralError,"x"))=400`; `HttpCode` of a status from a caught `<UNDEFINED>` = 500.
  - Live `RestStatusTest` via `%Net.HttpRequest`:
    - `GET /schemas/NoSuch` → 404.
    - Delete of an in-use schema → 409.
    - Rebind while `^OPCUA.ProductionEdit` is held → 409.
    - Wrong password → 401, no `WWW-Authenticate` header, and the body's `error` is "Sign-in failed".
    - A forced internal error (test-only route parameter `forceError=1` on `/ping` that runs `set x = y` with `y` undefined) → 500, and the body contains `Reference` but not `<UNDEFINED>`.
- [ ] **Step 2:** Run red.
- [ ] **Step 3:** Implement `Error`, `Respond`, and `Login`. Convert services' not-found / conflict errors to `Error.*`. Take the 409 for "another production running" from `DeployService.CheckNoOtherProduction`.
- [ ] **Step 4:** Webapp: replace the per-call envelope handling with `apiErrorMessage`, and wire the 401 behaviour (Review Focus 4). Manual check with `ng serve` against the container: a wrong IRIS password in Settings shows "Sign-in failed", with no browser pop-up. `tsc --noEmit` and `ng build` clean.
- [ ] **Step 5:** Green, plus the regression gate. Update audit #16 and the "Every error returns HTTP 400" bullet. Commit `fix(rest): real HTTP statuses and no internal detail in responses`.

### Task 7: #13 String columns no longer capped at 50

**Files:**
- Modify in both `backend/src/OPCUA/Types/` and `Types/NoServerTS/`: `StringDataValue.cls` (`Value`), `LocalizedTextDataValue.cls` (`Locale`), `QualifiedNameDataValue.cls` (`Name`), `NodeIdDataValue.cls` (`Identifier`, currently untyped, hence `%String` with MAXLEN 50), `ArrayDataValue/String.cls` (`Values` element)
- Create: `backend/tests/OPCUA/Tests/Unit/TypeWidthTest.cls`

- [ ] **Step 1: Failing tests:**
  - `TestLongStringSaves`: generate a tmp schema with a String column. `%New` a row with a 5,000-character value, plus a non-ASCII 200-character value (`"Ünïcødé…"`), and assert `%Save` returns OK. A SQL `UPDATE` setting the column to a 5,000-character value gives SQLCODE 0.
  - `TestProjectedWidth`: `%Library.SQLCatalog` / `INFORMATION_SCHEMA.COLUMNS` for `X_Value` reports no 50 limit.
  - `TestFamiliesInStep`: for every class in `OPCUA.Types` with a counterpart in `OPCUA.Types.NoServerTS`, the payload properties have identical names, types and `MAXLEN`.
- [ ] **Step 2:** Run red.
- [ ] **Step 3:** `MAXLEN = ""` on each listed property. Type `Identifier` as `%String(MAXLEN = "")`.
- [ ] **Step 4:** Green, plus the regression gate. Update audit #13. Commit `fix(types): no 50-character cap on string payloads`.

### Task 8: #14 Status holds every 32-bit code

**Files:**
- Modify: `backend/src/OPCUA/Types/AbstractDataValue.cls:10`, `Types/NoServerTS/AbstractDataValue.cls:20`; `backend/src/OPCUA/DataSource/RowWriter.cls` only if the sign check requires it
- Create: `backend/tests/OPCUA/Tests/Unit/StatusWidthTest.cls`, `Live/StatusSignTest.cls`

- [ ] **Step 1: Investigate** what the native poll returns for a Bad reading. Live, poll `plc` with one node that doesn't exist on a device, and read element 3 of its DataValue. Record whether it's `2149580800` (`0x80340000`) or negative. Put it in the audit write-up.
- [ ] **Step 2: Failing tests:**
  - `StatusWidthTest.TestBadCodeRoundTrip`: save rows with Status `2147483648`, `2155085824` (`0x80740000`) and `0`, read them back by SQL, and assert they're equal.
  - `TestBadCodeSqlCompare` (Review Focus 2): `SELECT COUNT(*) … WHERE X_Status >= 2147483648` = 2, and `ORDER BY X_Status DESC` puts `2155085824` first.
  - `TestProjectedType`: the column's ODBC type is BIGINT.
  - `StatusSignTest.TestStoredUnsigned` (live): a row from the Step 1 poll stores the unsigned code, and `RowWriter`'s severity says Bad.
- [ ] **Step 3:** Run red.
- [ ] **Step 4:** `Status As %BigInt` in both families. If Step 1 showed negative values, convert to unsigned in `RowWriter.BuildRow` (add 4294967296 when < 0) and say so in the audit.
- [ ] **Step 5:** If a JDBC/ODBC client is easy to run from the host (for example `jaydebeapi`, or the IRIS JDBC jar with `jshell`), read the value with `getLong`, and `getInt` to show the old overflow. Otherwise note "verified by SQL metadata".
- [ ] **Step 6:** Green, plus the regression gate. Update audit #14. Commit `fix(types): store StatusCode as BIGINT`.

### Task 9: #15 Credentials instead of plain-text passwords (backend)

**Files:**
- Modify: `backend/src/OPCUA/Adapter/Common.cls` (`SETTINGS`, remove `Username`/`Password` properties, `Connect` call at `:180`); `backend/src/OPCUA/REST/DeployService.cls` (`AddServiceItem` `:259-260`); `PipelineService.cls` (`DescribeItem`, `Delete`); every `backend/examples/` production or service that sets `Username`/`Password`; `demo/iris/IRISConfig/Installer.cls` (`CreateCredentials`) if it relates
- Create: `backend/tests/OPCUA/Tests/Unit/CredentialsTest.cls`, `Live/SecuredPipelineTest.cls`

**Interfaces:**
- Adapter: uses `Ens.Adapter`'s own `Credentials` setting / `CredentialsObj`, and connects with `..CredentialsObj.Username`, `..CredentialsObj.Password` (empty when `Credentials` is unset).
- `DeployService.CredentialsId(pItemName As %String) As %String`: `"OPCUA-"_pItemName`, with characters invalid in an `Ens.Config.Credentials` ID replaced by `_`.
- Deploy body: `credentials` (existing ID; must exist, else 400) **or** `username` (+ optional `password`). With `username`, it creates `CredentialsId(name)` through `Ens.Config.Credentials.SetCredential(id, user, pwd, 0)`, refuses with 409 if the ID exists, and records ownership in `^OPCUA.OwnedCredentials(id) = itemName`. With neither, it sets no `Credentials` setting.
- Pipeline delete: if `^OPCUA.OwnedCredentials(id)` names this item, delete the entry and the marker. Otherwise leave the entry alone.
- `DescribeItem`: maps `Credentials` → `username`/`password` from the entry for the coverage check.

- [ ] **Step 1: Failing tests:**
  - `CredentialsTest.TestCredentialsIdSanitised` (Review Focus 1): `CredentialsId("Line 3.Press-A")` is a valid ID, and `SetCredential` with it succeeds.
  - `TestNoPlainPasswordInProductionClass`: deploy a tmp pipeline with `username`/`password`. Assert the production class source (`%Dictionary.XDataDefinition` for `ProductionDefinition`) does **not** contain the password, and contains `Credentials`.
  - `TestExistingIdNeverOverwritten`: pre-create `OPCUA-TmpCred` with a different password, then deploy `TmpCred` with `username`. Assert 409 and the stored password is unchanged.
  - `TestDeleteRemovesOnlyOwned`: delete pipeline A (owned entry) and B (`credentials` pointing at a pre-existing entry). A's entry is gone, B's survives.
  - `TestAnonymousAndUserOnly` (Review Focus 5): deploy with neither → no `Credentials` setting and no entry. Deploy with `username` only → an entry with an empty password.
  - Live `SecuredPipelineTest.TestRebindWithCredentials`: deploy against `plc` with credentials, rebind, and assert the coverage check connects (no connection error).
- [ ] **Step 2:** Run red.
- [ ] **Step 3:** Implement. Remove `Username:User,Password:User` from `Common`'s one-line `SETTINGS` (it must stay one line).
- [ ] **Step 4:** Update the Examples to use `Credentials`. Check that `PollingExample` and `SubscriptionExample` still store real values from `plc`.
- [ ] **Step 5:** Green, plus the regression gate. Update audit #15. Commit `fix(adapters): keep OPC UA passwords in IRIS credentials`.

### Task 10: (dropped)

The user decided the console keeps the OPC UA password in localStorage, as it does the IRIS sign-in password. Nothing to do; task numbers are kept so references stay valid.

### Task 11: #17 Installer resumes an interrupted namespace; case-insensitive ownership

**Files:**
- Modify: `installer/objectscript/IRISConfig/ClientInstaller.cls` (`ClassifyNamespace` `:583-610`, `CreateNamespace` `:189-228`, ownership lookups at `:587`, `:639`, `:655`)
- Test: a scripted check run in the container in `%SYS` (the installer has no ObjectScript test class; add `installer/objectscript/tests/ClientInstallerResume.script` or extend the Rust integration tests if they drive IRIS, whichever the existing installer tests use)

**Interfaces:**
- `DescribeNamespace` gains state `resumable`: the namespace is marked owned (`^IRISConfig.ClientInstaller("ns", NS)`) or its database is `DatabaseOwned`, and interoperability isn't enabled. `CreateNamespace` treats `resumable` like `missing` for the remaining steps. The Rust side shows `resumable` the way it shows `owned` (check `installer/src` for the state strings, and update the match there).
- Ownership subscripts are stored and looked up with `$ZConvert(path,"U")` for app paths (namespace names are already uppercase).

- [ ] **Step 1: Failing check:** in `%SYS`, run `CreateNamespace("OPCUARESUME")` with a test hook that throws right after `Config.Namespaces.Create`. Then call `InspectNamespace("OPCUARESUME")`: expected `state="resumable"`, today `conflict`. Then rerun `CreateNamespace`: expected success, with interoperability enabled. Also: record app `/csp/OpcUa/api` as owned, then `DescribeApp("/csp/opcua/api")` → owned.
- [ ] **Step 2:** Run red. Implement. Run green. Clean up `OPCUARESUME` (namespace, database, files).
- [ ] **Step 3:** `cargo test` in `installer/` passes (it embeds the class).
- [ ] **Step 4:** Update audit #17 and the "Ownership markers" bullet. Commit `fix(installer): resume an interrupted namespace setup`.

### Task 12: #18 Demo image build fails on compile errors

**Files:**
- Modify: `demo/iris/IRISConfig/Installer.cls:44-50`

- [ ] **Step 1: Red:** add a syntax error to a throwaway class `backend/src/OPCUA/ZZBroken.cls` and run `docker compose build iris`. Expected today: the build succeeds.
- [ ] **Step 2:** Check the statuses of `Load` (Constants.inc), `LoadDir` and `CompileAll`, plus their error arrays, and `$$$ThrowOnError` so the install script exits non-zero. Confirm `demo/iris/Dockerfile`'s `RUN` propagates the exit code. Fix it there too if not.
- [ ] **Step 3: Green:** the build fails and names `ZZBroken`. Delete `ZZBroken.cls`, rebuild, and the build succeeds.
- [ ] **Step 4:** Update audit #18. Commit `fix(demo): fail the image build on compile errors`.

### Task 13: AI-pattern sweep and remaining ignored statuses

**Files:**
- Modify: whatever the sweep finds in `backend/src`, `installer/objectscript`, `demo/iris`

- [ ] **Step 1:** List every instance with its file:line: `CreateFromStatus(0)`; `Catch (e) {}` and `} Catch (e) {}` (including `SafeReadValue` and `GetRowSourceInfo`); `$LI(` / `$List(` reading an element that can be absent; `?1.N` tests on a `$Piece` result; ignored statuses from `SetLogFile`, `CreateObjectFromSourceData`, and any `do ##class(...).X()` whose return is a `%Status`. Put the list in the commit message body.
- [ ] **Step 2:** For each real instance, write the smallest test that shows the wrong behaviour (in `OPCUA.Tests.Unit.SweepTest`, one method per instance, named after the method fixed). Fix it, and run green. For an intentional instance, add a one-line comment saying why, and give it no test.
- [ ] **Step 3:** Regression gate. Update the audit's "Ignored statuses" bullet (remaining part) and add a short "Sweep" note under "AI-style patterns to watch" listing what was fixed. Commit `fix: sweep swallowed errors and unchecked statuses`.

### Task 14: Move the test suite to `%UnitTest`

**Files:**
- Convert: `backend/tests/OPCUA/Tests/MeasurementMetadataTest.cls` → `Unit/MeasurementMetadataTest.cls` (offline sections) + `Live/MeasurementMetadataTest.cls` (`TestLiveRow`, `TestLiveSubscription`); `ResolverTest.cls` → `Unit/ResolverParsingTest.cls` (`TestParsing`) + `Live/ResolverTest.cls`; `PortalPipelineTest.cls` → `Live/PortalPipelineTest.cls`; `TypeInferenceTest.cls` → `Live/TypeInferenceTest.cls`; `DataTest.cls` → `Live/DataTest.cls`
- Keep: `FakeBatchHost.cls`, the `*DS.cls` data-source classes, `Production.cls`
- Delete: the old harness classes once their checks are all ported
- Create: `Unit/ParseNodePathTest.cls`, `Unit/RestServiceTest.cls`, `Live/PortalDataValuePipelineTest.cls`
- Modify: both CLAUDE.md files' Testing sections, `docs/architecture.md` / `docs/workflow.md` where tests are described

**Interfaces:**
- Consumes: `OPCUA.Tests.Runner` (Task 0).

- [ ] **Step 1:** Port each harness check one to one into `$$$Assert*` calls, keeping its name as the test method name. Port count check: the old pass totals (MeasurementMetadata 257, Portal 38, Resolver 78, plus whatever Tasks 1–13 added) must equal the new assertion counts, or the difference is explained in the commit body.
- [ ] **Step 2:** Replace `PortalPipelineTest.Settle`'s fixed `hang`s with `WaitFor(pCondition As %String, pTimeoutSec As %Integer = 30) As %Boolean` (poll every 0.5 s, `$$$AssertTrue` on the result, timeout reported with the condition text).
- [ ] **Step 3:** `DataTest`: assertions fail when checks fail. `TypeInferenceTest`: when `certified-server` is unreachable, call `$$$AssertSkipped("certified-server unreachable")` (or the 2025.3 equivalent; if none, log it and return without asserting so it's not counted as a pass) instead of passing.
- [ ] **Step 4:** New coverage:
  - `ParseNodePathTest`: `ns=2;s=AC1`, `ns=2;i=42`, `s=AC1` (default ns), `ns=2;s=` (error), `ns=x;s=A` (error), `ns=2;s=A;B` (semicolon inside the id), surrounding whitespace, `|label` suffix, and a `?1.N`-style trap (`"ns=2"` with no `;`) → error.
  - `RestServiceTest`: offline calls of `PipelineService.Rebind` / `Toggle` / `Delete` / `List` (health field) and `SchemaService.Delete` refusal, against a tmp production with no running items.
  - `PortalDataValuePipelineTest`: the Portal path end to end with a **DataValue** schema (generated by `GenerateSchemaClass`, not plain columns). Assert that `X_Value`, `X_Status`, `X_SourceTS` and `X_ServerTS` are all non-NULL for a polled row.
- [ ] **Step 5:** `Offline()` and `Live()` both pass. Update the CLAUDE.md files' Testing sections to the two runner commands, and remove the DataTest caveat wording that no longer applies (keep the APPINT/public-server fact). Update the audit's "Test suite" section to ✅ per bullet. Commit `test: move the suite to %UnitTest with offline and live packages`.

### Task 15: CI job for the offline tests

**Files:**
- Create: `.github/workflows/backend-tests.yml`
- Possibly create: `demo/ci/` helper (an install script for the Community container)

- [ ] **Step 1:** Workflow on push and PR, with paths `backend/**` and the workflow file. One job on `ubuntu-latest`: start `intersystems/iris-community:2025.3` (the same tag as `demo/iris/Dockerfile`'s base), wait for it to be ready (poll `iris session` / `iris qlist` until running, 5-minute cap), create namespace `OPCUA` with interoperability (reuse the logic from `demo/iris/IRISConfig/Installer.cls`'s setup, without demos, web app or native library), load and compile `backend/src` + `backend/tests`, run `Runner.Offline()` then `Runner.Exit()`.
- [ ] **Step 2:** The offline tests must not load the native library. If a `Unit` test or a compile needs it, **stop and ask** (spec).
- [ ] **Step 3:** Prove it both ways on the branch. Push a commit that breaks one Unit assertion: the job fails and names the test. Revert: the job passes. Record the run URLs in the commit body of the revert.
- [ ] **Step 4:** Commit `ci: run the offline backend tests on every push`.

### Task 16: Legacy Studio export and final verification

**Files:**
- Regenerate: `legacy/windows-studio/IrisOPCUA_prj-*.xml`
- Modify: `docs/design/objectscript-audit.md` (header note that all items are closed, and the Windows pass is still pending. That pass must record the client's exact IRIS version and build, and if it's older than 2025.3, re-check #13, #14, #15, #16 and `%FromJSON` on a stream there)

- [ ] **Step 1:** Check the existing export's header (`<Export generator=… version=…>`) and contents list. Re-export the same set of classes and `Constants.inc` (plus any new production classes from this plan, but **not** tests) from the container with `$System.OBJ.Export`. Use the oldest export `version` the API accepts on 2025.3 if a qualifier exists (`/exportversion=`), and record the version used in the audit.
- [ ] **Step 2:** Import check: load the new XML into a fresh scratch namespace in the container and compile. Zero errors.
- [ ] **Step 3: Final verification on a fresh image:** `docker compose down`, `docker compose build --no-cache iris`, `docker compose up -d`, then:
  - `Runner.Offline()` and `Runner.Live()` both pass.
  - `PollingExample` and `SubscriptionExample` store real values.
  - Build the console (`npx ng build`), and run the installer against the container if its tests support that (`cargo test`).
  - Record the counts in the audit.
- [ ] **Step 4:** Commit `build(legacy): re-export the Studio project from the fixed sources` and `docs(audit): all items closed; Windows pass pending`.
