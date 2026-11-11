## 0.5.0 — 2026-11-11 — Managed Sign & Encrypt (connector 0.5.1, installer 0.5.0)

Security fix: on Windows the identity key and the `opcua-pki` folders inherited the parent
folder's ACL, which can let any local user (Users, Authenticated Users) read or replace the
key and write into the trust folders. Connector 0.5.1 adds ordinal 53 `zfPkiProtectPath`
and `OPCUA.Utils.SupportsProtect()`: the store root, every folder and every key get a
protected DACL granting full control only to the IRIS process account, SYSTEM and
BUILTIN\Administrators (well-known SIDs, Windows API, no `icacls`). Keys are created with
it, and `Store.EnsureDirs` re-applies it to the whole store each time, so existing installs
are tightened on first use; it fails closed if the DACL cannot be applied. Linux keeps
0700/0600. The three native wrappers are rebuilt as 0.5.1.

Sign & Encrypt no longer means generating DER files with OpenSSL, copying them onto the
IRIS server and typing four paths and a Client URI into every server profile and
pipeline. IRIS keeps one client identity per instance and a reviewed, pinned
certificate per server; a SuperUser sets both up in the console.

### Added
  - Connector 0.5.0 (`irisopcua.so` for linux-amd64 and linux-arm64, `IrisOPCUA.dll`):
    ordinals 48-52 -- create an RSA 2048 self-signed identity (`keyCertSign` included),
    inspect a certificate, check a key against a certificate, normalise PEM/DER/PKCS#12
    to DER, and pin a server certificate with an endpoint host check. Ordinal 47
    (`zfGetEndpoints`) is now declared and used. `OPCUA.Utils.SupportsPki()` gates the
    new calls on a 0.5 library. `open62541.dll`, `libcrypto` and `libopen62541` are
    unchanged.
  - `OPCUA.Security.*`: `Store` (files under `<manager dir>/opcua-pki/`, config in
    `^%OPCUA.Security`), `Identity` (create, import, use files on IRIS, validate on every
    read, replace only with the current fingerprint), `Trust` (inspect, fingerprint-confirmed
    trust, issuer + CRL for CA-issued servers, per-server pin), `Connection` (resolves a
    managed connection; used by REST and both adapters), `Diagnose` (categorised failures,
    including `clientNotApproved` with IRIS's fingerprint), `Native`.
  - `/security/identity` (GET, POST, `/import`, `/files`, `/certificate?format=der|pem`) and
    `/security/servers` (GET, `/inspect`, `/trust`, `/issuer`, DELETE `/:key`). They need
    `%Admin_Secure:USE` (403 otherwise). `POST /test` gains a `security` block for managed
    connections.
  - Console: Settings -> OPC UA Security tab (identity, expiry, download as DER/PEM,
    replace with an impact list) and, on each server profile, three readiness rows
    (identity, server certificate reviewed and trusted, IRIS approved by the server).
  - Docker demo: named volume `iris-opcua-pki` for `/usr/irissys/mgr/opcua-pki`;
    `demo/iris/secure-e2e.sh` runs the approval flow against `certified-server`;
    `OPCUA.Tests.Runner.Run(...)` runs a single test class or method.

### Changed
  - `SecurityMode=3` with no certificate paths is now a *managed* connection using the
    instance identity. `POST /deploy` writes only `SecurityMode=3` for it. Explicit
    `certPath`/`keyPath`/`trustDir`/`crlDir`/`clientURI` (and the adapters'
    `PublicCertificate`/`PrivateKey`) still select the manual path, unchanged -- the demo
    `SecureExample` and existing pipelines keep working.
  - The console no longer fills in certificate paths or a Client URI when Sign & Encrypt is
    chosen.
  - Installer 0.5.0 embeds the 0.5.0 native files and `OPCUA/Security/*`. A differing
    native library is still replaced only after confirmation; processes that loaded the old
    one need a restart.

### Security
  - Managed connections refuse (before any native setup) when the server has no trusted
    certificate, no pin, or a CA-issued certificate without its issuer and CRL: open62541
    1.2.1 treats an empty trust list as trust-everything. They never fall back to
    SecurityMode 1.
  - Each managed connection is pinned to the reviewed certificate (SHA-256) on top of
    normal chain, CRL and expiry checks, plus a SAN host check. A replaced server
    certificate is shown for approval, never accepted silently.
  - The private key is never returned by the API or written to logs; no `openssl`
    executable or shell is used at runtime.

### Known limitations
  - IRIS cannot make the OPC UA server trust it: the server administrator must approve
    the downloaded certificate.
  - Server-side rejections reach IRIS as `BadConnectionClosed`; the category is inferred
    (`clientNotApproved` when the pin and host check out).
  - Not tested on Windows: the DLL is built, but key-file permissions and the managed flow
    are on the Windows checklist. `legacy/windows-studio/` predates `OPCUA.Security.*`.
  - Console accounts holding only the installer's `OPCUA_API_<NS>` role get 403 on
    `/security/*`.

## Unreleased — Schema / device decoupling

Creating a schema and choosing which devices to read are now separate operations.
Previously one wizard run produced a single frozen artifact: a generated class whose
device list was baked in at deploy time. Adding a device meant regenerating and
recompiling the class.

### Added
  - `includeServerTimestamp` option on `POST /schemas` (default `true`), with a
    checkbox in the schema builder. When it is `false`, columns are typed as the new
    `OPCUA.Types.NoServerTS.*` measurements, which have no `ServerTimeStamp`, so the
    table has no `*_ServerTS` columns. The source timestamp, status and full payload
    are kept, flat and nested. Existing schemas are unchanged.
  - `OPCUA.DataSource.DeviceSchema` — abstract superclass for generated schemas. Gives
    the `DataSourceClass` production setting a class family, so it renders as a dropdown.
  - `OPCUA.DataSource.Resolver` — parses `DeviceNodePaths` and matches each device's
    children **by name** against the schema's columns, at connect time.
  - `OPCUA.REST.SchemaService` and `/schemas` endpoints (list, create, get, delete,
    validate). Creating a schema has no production side effects.
  - `POST /pipelines/rebind` — change a pipeline's device list as a settings update:
    no regeneration, no recompile.
  - `DeviceNodePaths` adapter setting. A pipeline can now be built entirely from the
    Management Portal, with no webapp involved.
  - Pipeline health reporting: a pipeline that is enabled but failing to connect or
    resolve is reported as `error` rather than looking healthy.
  - Webapp: Schemas library, schema builder, device binding screen with a live
    address-space picker. Each device is dry-run against the schema as it is added,
    so coverage is a property of the device list rather than a separate step.
  - `OPCUA.Tests.ResolverTest`, `OPCUA.Tests.PortalPipelineTest`.

### Changed
  - `POST /deploy` now requires `schemaClass` and **generates nothing** — it binds
    devices to a schema that already exists.
  - Deleting a pipeline no longer deletes its schema. Schemas are reusable and may back
    several pipelines; `DELETE /schemas/:name` refuses while any pipeline uses one.
  - The polling adapter drops its session when query setup fails, so a resolution
    failure reports its real cause on every retry and recovers from a config edit
    instead of stalling until restarted.
  - Schema columns are typed from a sample read instead of all landing as `%String`.
  - Schema columns are named relative to an explicitly marked template device, so a
    device's own name and browse path never become part of a column name.
  - A device missing some columns stores NULL for them and keeps collecting the rest.
    Coverage is reported before deploy, so there is no refuse-to-collect toggle.
  - `POST /deploy` and `POST /pipelines/rebind` refuse a device that would contribute
    nothing: it must browse successfully **and** match at least one schema column.
    A device matching none would only ever add all-NULL rows. Runtime is unaffected —
    a device that fails later still stores NULL rather than stopping the pipeline.

### Removed
  - `^OPCUA.RowSource`. Device metadata, column masks and the nesting spec are now
    derived — masks by browsing at connect time, nesting from the compiled class.
  - The combined create-and-deploy wizard, `DeployService.DeployV2()`, and
    `PipelineService.Edit()` with its `/pipelines/edit` route.
  - The Monitoring tab and its metrics stack (`OPCUA.REST.MetricsService`,
    `OPCUA.Monitor.Metrics`, `/metrics`, and the SAM registration in the installer —
    including the `%DB_OPCUA` grant to `UnknownUser` that existed only to serve it).

### Known limitations
  - A schema's **column set** cannot be changed after creation; recreating the schema
    drops its table and data. An `ALTER`-style schema edit is the obvious next step.
  - `OPCUA.Tests.DataTest` cannot run in the Docker compose setup (no `APPINT`
    namespace, and its target server is unreachable). Use the local `plc` server as the
    declarative-path regression gate.

## 0.3.4 (May 14, 2021)
  - Update README.md, IrisOPCUA_prj-20210513.xml, and 6 more files...
  - Update README.md, IrisOPCUA_prj-20210513.xml, and 6 more files...
  - windows README edit
  - Windows files
  - NodeIdDataValue storage correction
  - Another README edit
  - Removes unnecessary instruction from README
  - Bump version to 0.3.3.

## 0.3.3 (May 07, 2021)
  - hook
  - bumpversion

## 0.3.2 (May 07, 2021)
  - Security changes. Export of arrays and additional data types.
  - Fixing bumpversion script
  - Fixing bumpversion script

## 0.3.1 (May 06, 2021)
  - OPCUA Connector with TCP/IP Pulling available

