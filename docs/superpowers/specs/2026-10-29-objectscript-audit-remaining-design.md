# ObjectScript audit: the remaining items

**Date:** 2026-10-29 · **Branch:** `docs/objectscript-audit` (items 1–9 already fixed here) · **Source of the items:** `docs/design/objectscript-audit.md`

## Why

The adapter is going to its first client, a long-time InterSystems customer who
runs IRIS on **Windows**. They'll set pipelines up mostly through the OPC UA Console,
but they know the Management Portal well and may use it too. This is the first time
anyone outside the team runs the product, so it has to work first time: every
problem still open in the audit is in scope, not just the serious ones.

"Flawless" here means:

- Every fix is verified against a running IRIS, the way 1–9 were.
- No code path silently loses a change, leaves debris behind, or touches anything
  the client owns.
- Errors tell the user what actually went wrong.
- Tests fail when they should, and the offline ones run in CI on every push.

## Goals

1. Fix every open audit item: **10–19**, every bullet under **Smaller issues**, and
   the **Test suite** section.
2. Sweep the **AI-style patterns to watch** across `backend/src` and fix every
   instance, not only the ones the audit names.
3. Make the offline tests `%UnitTest.TestCase` classes and run them in a GitHub
   Actions job.
4. Keep `docs/design/objectscript-audit.md` up to date. Each item gets the same ✅ /
   **Fix:** / **Verified:** write-up as 1–9.

## Non-goals

- **Testing on Windows.** The user will do this as a separate pass on their own
  Windows IRIS machine after this work. It's a release gate, not part of this
  project. All verification here runs in the Linux docker stack
  (`iris-opcua-iris-1` plus `plc`, `plc2` and `certified-server`).
- **The client's IRIS version is unknown (my call on how to handle it).** Verify
  on the container's IRIS 2025.3, and pin the CI image to the same version. The
  Windows pass must record the client's exact version and build. If it's older than
  2025.3, re-check the version-sensitive fixes there: #13/#14 SQL projection, #15
  `Ens.Config.Credentials`, #16 login handling, `%FromJSON` on a stream. Export the
  legacy Studio XML in a format older IRIS releases can import, if the export API
  allows it, and say which format was used.
- Changing the C++ library, unless a fix can't be made without it. If one can't,
  stop and ask (see "When to stop and ask").
- Editing a schema's columns, or any combined create-and-deploy path. The
  architecture rules in both CLAUDE.md files still hold.

## Anti-goals (failure even if it technically works)

- A fix that changes or stops anything the client owns: their productions, their
  classes, their credentials, their web apps.
- A pipeline set up in the Portal that behaves differently from one set up in the
  console.
- A test that passes when it can't actually check anything (an unreachable server
  counted as a pass).
- Forking row assembly out of `RowWriter`, or merging schema creation into deploy.

## Constraints

- **No backwards compatibility needed.** The user confirmed the client is the first
  install. Setting names, SQL column types, HTTP status codes and REST response
  shapes can change freely. The webapp has to change with them in the same commit.
- **Worst case for the namespace.** We don't know yet whether the client will give
  us a dedicated namespace, so assume the worst. The installer already refuses a
  namespace that hosts a different production (`ClientInstaller.cls:606`). From
  there, the remaining risks all come through the Portal: someone starts another
  production in our namespace, adds a pipeline to a hand-built production, or edits
  at the same moment as the console. Design for those.
- One commit per audit item (closely related smaller issues may share one), in the
  repository's commit style: concise, conventional prefix, **no** Claude co-author
  trailer (user memory overrides the default attribution).
- ObjectScript changes need importing and compiling in the container before they
  take effect. Rebuild the image, or load and compile in place, whichever the
  builder finds faster. The final verification must run on a freshly built image.
- Regression gate after every item: `OPCUA`, `Examples` and the test packages
  compile clean, and `MeasurementMetadataTest`, `PortalPipelineTest` and
  `ResolverTest` pass against `plc`. The declarative `PollingExample` /
  `SubscriptionExample` path must still store real values.

## Decisions

Marked **(user)** where the user decided, **(my call)** where I did. The builder may
revisit a "my call" if the code shows it was wrong, but must say so in the item's
write-up.

### Test suite (user, agreed to the recommendation)

- Every test becomes a `%UnitTest.TestCase` class, so there's one way to run them all.
- **Offline tests** run in a GitHub Actions job on every push and PR, in an IRIS
  Community container with no PLC: RowWriter, `ProcessBatch`, Projection errors,
  `ParseNodePath` / `ParseDeviceNodePaths` edge cases, and the REST layer as far as
  it can run without a server.
- **Live tests** run locally against the docker `plc`, and are kept separate (their
  own package or a clear naming convention) so CI never picks them up: Resolver,
  PortalPipeline, and the live parts of MeasurementMetadata. Their fixed `hang`
  waits get replaced by polling for the condition, with a timeout.
- `DataTest` fails honestly when its checks fail. `TypeInferenceTest` reports
  *skipped*, not passed, when `certified-server` is unreachable.
- Add the missing coverage the audit lists: REST rebind / toggle / delete / health /
  delete-refusal, `ParseNodePath` edge cases, and the end-to-end Portal path with a
  **DataValue** schema (not only plain-column schemas).
- Known risk: the Community container is slow to start, and the native library may
  not load in CI. Offline tests must not need it. If the classes need it just to
  compile, find a way round that and record it.
- CLAUDE.md files and `docs/` get updated to the new way of running tests.

### #10 Production edits are not locked (my call)

- Every console read-modify-save of `OPCUA.Pipeline.Production` (deploy, toggle,
  delete, rebind) runs under one named IRIS lock, with a timeout. If the lock isn't
  free, the request fails with a clear "another change is in progress" error
  instead of waiting forever.
- Inside the lock, always reopen the production fresh, change it, then `%Save` and
  `SaveToClass` once.
- **Rebind becomes one save.** Devices and categories change in the same open/save,
  not two separate `Update*` calls. Fold `UpdateDeviceNodePaths` and
  `UpdateItemField` into one helper that applies several changes.
- Portal edits don't take our lock. The builder should find out what actually
  happens when a Portal save and a console save overlap: does either side detect a
  stale copy? Then close the gap as far as IRIS allows. For example, compare the
  production's last-modified marker read at open with the one just before save, and
  refuse if they differ. Record what was found in the write-up.

### #11 Schema delete misses a schema still in use (my call)

- `MapSchemaUsage` returns a `%Status`. Any failure **refuses** the delete.
- It looks at **every** production in the namespace, not only
  `OPCUA.Pipeline.Production`, so a pipeline in a hand-built Portal production also
  blocks the delete. The usage message names the production as well as the item.
- The schema library's `usedBy` comes from the same function, so it shows those
  pipelines too.
- **Pipelines in other productions: show, don't manage (user).** The console never
  lists, toggles, edits or deletes them. They show up only as "used by *item* in
  *production*" in the schema library, without a link to the edit page, and they
  block that schema's delete. Everything else in the console still works only on
  `OPCUA.Pipeline.Production`, and so do the #10 lock and the stale-save check.
  Pipelines stay identified by name alone.

### #12 A failed schema creation leaves debris (my call)

- Before creating anything, check that none of the target class names (main and
  serial) exist, and refuse with a clear message if one does.
- If anything fails after that, delete exactly the classes this call created, and
  nothing else, then return the original error.

### #13 String columns capped at 50 characters (user: change freely)

- `MAXLEN = ""` on every unbounded string payload property in **both** type families
  (`OPCUA.Types.*` and `OPCUA.Types.NoServerTS.*`): String values, Locale, NodeId,
  QualifiedName, and the String array element type. Keep the two families in step.
- Verify with a SQL `UPDATE` and a `%Save` of a value well over 50 characters, and
  check the projected SQL type.

### #14 Status is the wrong size (my call)

- Type `Status` as `%BigInt` in both families (or an equivalent that projects to SQL
  BIGINT), so every unsigned 32-bit code fits.
- First confirm what the native layer actually hands over for a Bad code (unsigned
  `2147483648` and up, or negative), and make sure the stored value is the unsigned
  code. `RowWriter`'s severity logic must still classify it correctly.
- Prove it over a real JDBC or ODBC `getInt`/`getLong` if one is easy to run from the
  container or host. Otherwise use SQL metadata, and say so.

### #15 OPC UA passwords stored in plain text (my call)

- Use the standard `Credentials` setting that `Ens.Adapter` already provides
  (`Ens.Config.Credentials` plus `CredentialsObj`). Remove the `Username` and
  `Password` settings and properties from `Common`, and connect with
  `CredentialsObj.Username` / `.Password`.
- `POST /deploy` accepts either an existing credentials ID (`credentials`), or a
  `username` + `password`, which it saves as a new credentials entry named after the
  pipeline. An existing entry is **never** overwritten: if the name is taken, refuse.
  Deleting a pipeline deletes the credentials entry only if deploy created it.
- `DescribeItem` (rebind's coverage check) reads the username and password from the
  credentials entry, so secured pipelines still validate.
- `/browse`, `/read`, `/test` and `/validate` keep taking `username` / `password`
  per request. They're never stored.
- Update the Examples to match. In the Portal, the `Credentials` setting is the
  standard credentials picker.
- **The console offers no credentials picker (my call).** Its deploy form keeps
  sending `username` + `password`, and there's no endpoint that lists the
  namespace's credentials entries, since those may belong to the client. Choosing
  an existing entry is a Portal job, or a direct `credentials` field on the API.
- **The console's browser storage is unchanged (user).** The OPC UA password stays
  in localStorage next to the IRIS sign-in password, which is already kept there.
  #15 is about what IRIS stores, not what the browser stores.

### #16 Wrong passwords return 404 (my call)

- A failed login returns **401** with the usual error envelope. It must **not**
  trigger the browser's own Basic-auth pop-up over the console, so no
  `WWW-Authenticate: Basic` header goes to the console. The console shows a clear
  "sign-in failed" message on 401.

### #17 Installer can't resume an interrupted namespace creation (my call)

- A namespace whose database this installer created (the existing ownership check)
  but which isn't interoperability-enabled yet is classified as **resumable**, not
  as a conflict. A rerun finishes the job. A namespace the installer didn't create
  still counts as a conflict.
- Test it in the Linux container by interrupting after `Config.Namespaces.Create`.

### #18 Demo Docker build ignores compile failures (my call)

- `demo/iris/IRISConfig/Installer.cls` fails the build when any load or compile
  fails. Test it by building once with a deliberately broken class, then reverting.

### #19 Deleting a pipeline leaves its config item row (audit's own fix)

- After `RemoveAt` and save, delete the `Ens.Config.Item` row. Do the same in
  `PortalPipelineTest.Cleanup`. Add a test that deletes an enabled pipeline,
  recreates it under the same name, and toggles it.

### Smaller issues (my call, all of them)

- **Ignored statuses:** check every one the audit names, and any others the sweep
  finds. Rebind reports `restarted` only when the restart actually succeeded, and
  otherwise returns the restart error, saying the device list was saved.
- **Library-not-found hides its reason:** return the real status from `Utils`. Don't
  throw `CreateFromStatus(0)`.
- **`tRetVal` / `tRetval` typo** in `DateTimeUtils.cls`: fix both spots.
- **Large request bodies are cut:** parse with `%FromJSON(%request.Content)`. Test
  with a body over 1 MB.
- **Every error returns HTTP 400, with raw routine offsets:** map errors to statuses.
  Bad input → 400, not found → 404, conflict (in use, another production, lock
  busy, name taken) → 409, failed login → 401, anything unexpected → 500. For 500
  the response carries a short generic message plus a reference. The full error,
  with the `<UNDEFINED>` and offset detail, goes to the IRIS application error log
  (or the event log), never into the response. Our own `$$$GeneralError` messages
  stay readable in the response. Update the console to show the message for any
  status.
- **SQL table names rebuilt by hand in three places:** read the compiled class's
  real qualified table name (which honours `SqlTableName`) in one helper, used
  everywhere.
- **Schema delete can remove a shared class:** `DeleteSerialSubclasses` only deletes
  serial classes that follow this schema's own generated naming
  (`SerialClassName`) and that no other class references.
- **Installer ownership markers are case-sensitive:** compare application names
  case-insensitively.
- **Stale documentation:** `StrictSchemaMatch` was removed
  (`SchemaService.cls:303`), so drop it from both CLAUDE.md files and `docs/`. Fix
  the `Client.cls` header that says security isn't implemented.

### AI-style pattern sweep (my call)

One pass over `backend/src`, `installer/objectscript` and `demo/iris`:
`CreateFromStatus(0)` used as a goto, `Catch {}` blocks that swallow errors in
places where the error matters, `$LI` / `$List` where an element can be missing,
loose `?1.N` pattern tests on `$Piece`, and IRIS defaults nobody checked. Fix each
real instance. Leave an intentional one alone, but give it a one-line comment saying
why.

### Legacy Studio export (my call)

`legacy/windows-studio/` still has the old code (it predates fix #1). At the end,
regenerate it from the final sources in the container, so a Windows install by hand
gets the fixed code too.

## Order (my call)

1. #19 and the small, contained fixes (typo, Utils status, body size, table names,
   stale docs).
2. #10, #11, #12 together: the production and schema edit paths.
3. The HTTP status mapping, and #16 (they touch the same Handler and console code).
4. #13, #14 (type changes), then #15 (credentials, touches adapter, REST, Examples
   and console).
5. #17, #18 (installer and demo build).
6. The pattern sweep.
7. The test-suite move and CI. New tests written along the way go straight into
   `%UnitTest` form, so this step is mostly converting what's left and adding the
   Actions job.
8. Legacy Studio export, and a final full verification on a freshly built image.

## When to stop and ask

The user wants a ping whenever their input is needed. Stop and ask (don't guess)
when:

- a fix would need a C++ change,
- a fix would touch anything outside our own namespace, classes, productions or
  web apps,
- a "my call" decision above turns out to be wrong or impossible,
- the Portal race in #10 can't be closed and needs a trade-off,
- CI can't run the offline tests without the native library.

## Left to the builder

Method names, the lock's name and timeout, the error-to-HTTP mapping mechanism, the
`%UnitTest` package layout, the Actions workflow details, and how each item is
tested, within the rule that every fix has a test that failed before it and passes
after.
