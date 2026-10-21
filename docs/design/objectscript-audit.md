# ObjectScript repository audit

**Date:** 2026-10-15 · **Applies to:** `main` at `1346bbc` (release `setup-cli-v0.2.0`) · **IRIS used for checks:** `iris-demo`, IRIS 2025.3, namespace `OPCUA`

Items marked ✔ were checked against the running IRIS instance or confirmed in the
code by hand. Everything else comes from reading the code; "plausible" means likely
but not reproduced. No code was changed as part of this audit.

Items marked ✅ have since been fixed; each one notes the fix and how it was verified.

## Summary

The code is in better shape than most AI-generated ObjectScript. The classic syntax
traps are absent: no `$Get(obj.prop)`, no `Quit value` inside loops or Try blocks,
no bad postfix spacing, no transaction misuse.

The real problems are subtler. They are in error codes, edge cases around lists and
names, and how the code affects other things on the IRIS server (other productions,
leftover data).

## Fix first

| # | Problem | Where | What goes wrong |
|---|---|---|---|
| 1 ✔ ✅ | ~~**Every error from the native library shows the wrong message**~~ **Fixed 2026-10-21** | `Client.cls:65`, `Constants.inc:184` | Error code 29000 means something else in IRIS 2025.3. Every connect, browse or poll error reads *"Context class '<real error>' does not exist"*, in the event log and in REST responses. Use `$$$GeneralError` instead. **Fix:** `DecodeError` now returns `$$$ERROR($$$GeneralError,tMsgTxt)`. `OPCUACLIENT` (29000) and the unused `OPCUAParameterMustBe` (29001, also an IRIS system error) are commented out in `Constants.inc`, so they can't be reused. Verified on IRIS 2025.3: the `OPCUA` and `Examples` packages compile clean, and a real failed connect now reads `ERROR #5001: OPC UA Error 0x80AE0000 [BadConnectionClosed] … Unable to connect to '…'`. The Studio export in `legacy/windows-studio/` still has the old code. |
| 2 ✔ ✅ | ~~**A device child whose name is only digits breaks the whole device**~~ **Fixed 2026-10-21** | `Resolver.cls:552` `NameKey()` | `NameKey("42")` returns an empty string. Using that as a subscript crashes the browse, so **every** column on that device is stored as NULL. Also, a name like `"10:30 Shift"` becomes `"30 Shift"`. **Fix:** `NameKey` now returns the name unchanged, so matching is exact. A raw browse of `plc` showed the native library sends a BrowseName as `$LB(name, nsIndex)`, so a `"ns:"` prefix never reaches `NameKey` and stripping one had no use. Added offline checks to `ResolverTest.TestParsing` for `"42"`, `"10:30 Shift"` and case sensitivity. Verified on IRIS 2025.3: the `OPCUA` package compiles clean and `ResolverTest.Run()` passes 78/0 against `plc`. |
| 3 ✔ ✅ | ~~**Deleting a schema keeps its rows**~~ **Fixed 2026-10-21** | `SchemaService.cls:161` | `$System.OBJ.Delete(cls,"-d")` has no `e` flag, so the data global survives, and the returned status is ignored. The storage global name comes from the class name (`^OPCUA.DS.AirConsD`). A new schema with the same name would therefore inherit the old rows under a different column layout. **Fix:** `Delete` now calls `%KillExtent` before deleting the class, and stops with the error if either step fails. It no longer reports `deleted` or drops `^OPCUA.DataSource` after a failure. I used `%KillExtent` rather than the `e` flag because `e` runs `%DeleteExtent`, which deletes row by row (0.89 s per 200k rows) and refuses the whole delete if one row won't open. Added `MeasurementMetadataTest.TestSchemaDelete`: it failed on the old code (global left behind, recreated schema showed the old row) and passes now. Verified on IRIS 2025.3: `OPCUA` package compiles clean, `MeasurementMetadataTest.Run()` passes 204/0 against `plc`. Schemas deleted before this fix may have left orphaned data globals on client servers. `iris-demo` has none. |
| 4 ✔ ✅ | ~~**Enabling a pipeline force-stops any other running production**~~ **Fixed 2026-10-21** | `DeployService.cls:396-404` | It calls `StopProduction(,1)` with no warning. On a client server this takes their unrelated production offline. `PortalPipelineTest` triggers it too, and never restores the original production. **Fix:** the new `DeployService.CheckNoOtherProduction()` refuses while a different production is running, suspended or troubled in the namespace. The error names that production, and nothing is stopped. `StartOrUpdateProduction` uses it. `PipelineService.Toggle` checks before saving, so a refused enable leaves the pipeline disabled (before, it was saved as enabled). Several pipelines can still run at once, because they are all items in `OPCUA.Pipeline.Production`. `PortalPipelineTest` now refuses to start while another production holds the namespace, and puts the pipeline production back as it found it. Its new test 6 uses a throwaway empty production as the "other" one: it failed on the old Toggle and passes now. The dashboard now shows a refused toggle, or a failed pipeline delete, in an error banner matching the schema library's. The webapp passes `tsc --noEmit` and `ng build`. Verified on IRIS 2025.3: `OPCUA` and `Examples` compile clean, `PortalPipelineTest.Run()` passes 38/0 against `plc`. |

## Should fix

5. **One short result list kills a whole poll cycle** ✔ (`RowWriter.cls:173`). `$LI(pInput, i)` throws `<NULL VALUE>` when an element is missing. That device and every device after it lose that cycle. Use `$ListGet`.
6. **The Projection reports the wrong error** ✔ (`Projection.cls:90`, `:167`). `ProcessObj` uses `cls`, a variable that only exists in another method, and never initialises `tSC`. A user who forgets `OPCUANAMESPACE` gets `<UNDEFINED> cls` instead of the helpful message.
7. **Subscriptions are never really deleted** ✔ (`TCPSubscriptionInboundAdapter.cls:410`, `:453`). The adapter cleans up with `ReadBulkClear`, the polling API. Each reconnect probably leaks a subscription. Caveat: the tests note that the real `DeleteSubscriptionSet` double-frees memory in C++, so the root fix is in the native library.
8. **A batch's result depends only on its last notification** (`TCPSubscriptionInboundAdapter.cls:278-297`). If only the last notification fails, the whole successful batch takes the error path. If an earlier one fails, it is only counted.
9. **Pipelines stop for good after a 10-minute outage** (`TCPPollingInboundAdapter.cls:183`). With the defaults, a PLC down for more than 10 minutes stops collection until someone restarts the pipeline. The warning branch meant for `AlwaysConnect=1` can never run.
10. **Production edits are not locked** (DeployService, PipelineService). Two requests at once, or a request plus a Portal edit, means the last save wins and the other change is silently lost. Rebind also saves in two separate steps.
11. **Schema delete can miss a schema that is still in use** (`SchemaService.cls:698`). `MapSchemaUsage` swallows every error and only looks at `OPCUA.Pipeline.Production`. If it fails, or a pipeline lives in a hand-built production, the delete goes ahead.
12. **A failed schema creation leaves debris** (`SchemaService.cls:377-444`). Half-created serial or main classes stay behind, and every retry then fails with "already exists".
13. **String columns are capped at 50 characters** ✔ (`Types/StringDataValue.cls` and siblings). `%String` defaults to `MAXLEN=50`. Rows save today only because `SaveSourcedData` writes the global directly. A SQL UPDATE or `%Save` on a longer value fails, and SQL clients see VARCHAR(50).
14. **The status column is the wrong size** (plausible). `Status As %Integer` holds unsigned 32-bit codes, and every Bad code is above the INTEGER range. JDBC or ODBC `getInt` would likely overflow on exactly the readings you care about.
15. **OPC UA passwords are stored in plain text** in the production settings, and so in the production class source. Ens Credentials would avoid this.
16. **Wrong passwords return 404, not 401** ✔ (`Handler.cls:20`). The `Login()` override suppresses the login challenge. No data leaks, but it is confusing.
17. **The installer can't resume an interrupted namespace creation** (`ClientInstaller.cls:216-223`). If enabling interoperability fails, every rerun calls the namespace "in use by something else".
18. **The demo Docker build ignores compile failures** (`demo/iris/IRISConfig/Installer.cls:44-50`). A broken `backend/src` still produces a "successful" image.

## Smaller issues

- **Ignored statuses:** `SetLogFile`, `UpdateProduction`, `EnableConfigItem`, `GetProductionStatus` and `CreateObjectFromSourceData`. Rebind reports `restarted=1` even when the restart failed.
- **Library-not-found hides its reason** ✔ (`Utils.cls:50-54`). The real status is overwritten, then `CreateFromStatus(0)` throws, so the user sees "Invalid status code structure".
- **Typo bug:** `tRetVal` vs `tRetval` in `DateTimeUtils.cls:94` and `:113`. It is hidden today only because the native function isn't available.
- **Large request bodies are cut** ✔ (`Handler.cls:326`). `Content.Read()` reads one chunk, about 160 KB. Use `%FromJSON(%request.Content)`.
- **Every error returns HTTP 400** and exposes raw `<UNDEFINED>` routine offsets.
- **SQL table names are rebuilt by hand in three places**, ignoring `SqlTableName`.
- **Schema delete can remove a shared class:** `DeleteSerialSubclasses` would delete a serial class shared with a hand-written schema.
- **Ownership markers are case-sensitive** in the installer, but IRIS application names are not ✔.
- **Stale documentation:** CLAUDE.md still mentions `StrictSchemaMatch`, and the `Client.cls` header says security isn't implemented.

## AI-style patterns to watch

- **Code that throws a status as a "goto"** (`CreateFromStatus(0)`), instead of building a real status.
- **Swallowing errors as `$$$OK`** in helpers (`MapSchemaUsage`, `SafeReadValue`), a Python-style "best effort" habit. In this code it disables safety checks.
- **Assuming lists are always complete:** `$LI` where `$ListGet` is needed, and the last-status-wins logic in batches.
- **Pattern tests that are too loose:** `?1.N` on `$Piece` also matches when there is no delimiter at all.
- **Defaults never checked against this IRIS version:** the 29000 code, `MAXLEN=50`, delete without the `e` flag, and `HandleCorsRequest` (it does nothing because the CORS allowlist is empty ✔).

## Already done well

- **Consistent `Client.cls` wrapper:** every native call goes through Try/Catch, converts errors to statuses, has a single exit, and checks the return before reading the list.
- **Clean architecture:** one row-assembly implementation (`RowWriter`) and one resolve path shared by both adapters, so polling and subscriptions can't drift.
- **Load-bearing ordering is respected:** adapters drop the session when resolving fails (`TCPPollingInboundAdapter.cls:103`), so they retry instead of polling a dead handle.
- **Defensive code in the core:** `$IsObject` follows every `%OpenId` in Resolver and RowWriter, list positions come from compiled storage rather than guesses, and Bad readings are read safely.
- **Careful input parsing:** `ParseDeviceNodePaths` handles CRLF, comments and per-line errors.
- **Safe schema deletion targets:** `RequireSchema`/`IsSchema` stop arbitrary classes being deleted through the API ✔.
- **Type inference from metadata:** types come from DataType + ValueRank, and the probe is always cleared.
- **The ServerTS-free type family** is properly separate, not a subclass.
- **ClientInstaller:** uses the `Config`/`Security` class APIs (not SQL), checks hashes, never overwrites files it doesn't own, and writes no secrets to logs. The live web app, role and resource settings match the code ✔.
- **`MeasurementMetadataTest`:** thorough offline coverage of RowWriter.

## Test suite

- **Not standard and not CI-ready:** the tests are hand-written `Run()` harnesses, not `%UnitTest.TestCase` classes. They all need the docker `plc` server, and `PortalPipelineTest` relies on about 44 seconds of fixed `hang` waits.
- **Tests that pass when they shouldn't:**
  - `DataTest` returns success even when checks fail.
  - `TypeInferenceTest` counts "certified-server unreachable" as a pass.
- **Resolver and Portal tests only cover the old shape:** they use plain-column schemas. The shipping DataValue schema is never tested end to end through the Portal path.
- **Untested:**
  - the whole REST layer: rebind, toggle, delete, health, and delete-refusal
  - `ParseNodePath` edge cases
  - RowWriter with short input
  - subscription batches with more than one notification

## Suggested order

1. Items 1–5: each is a small, low-risk change and fixes the most visible failures.
2. Items 10–12: locking and cleanup around production and schema edits. This is the bigger design fix.
3. Test suite: move the offline checks into `%UnitTest.TestCase` classes so they can run in CI without the docker servers.

## How this was checked

Four reviewers each read one area in full (client and types, adapters and data
model, REST, tests and installer). The main findings were then checked again in the
code and on `iris-demo`. The compose stack (with `plc`) was not running, so nothing
was tested against a live PLC.
