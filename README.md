# IRIS OPC UA Console

Connect InterSystems IRIS to OPC UA servers, browse their nodes, define reusable schemas, and collect measurements into SQL tables through polling or subscriptions.

- **Evaluate locally:** [Run with Docker](#run-with-docker).
- **Use your own IRIS instance:** [Client installation](#client-installation).
- **Start collecting:** [Your first pipeline](#your-first-pipeline).
- **Learn about the protocol:** [OPC UA concepts and legacy demos](docs/opcua-concepts-and-legacy-demos.md).

## What you install

```text
Browser → Web server / gateway → IRIS REST API → Native libraries → OPC UA server
                                IRIS production → Measurements in SQL tables
```

| Component | Where it runs | What it does |
|---|---|---|
| Web console (`webapp/`) | Browser, served by your web server | Configure connections, browse nodes, manage schemas and pipelines |
| ObjectScript (`src/objectscript/OPCUA/`) | A dedicated IRIS namespace | REST API, schema generation, background collection and storage |
| Native libraries (`bin/`) | The IRIS host | Communicate with OPC UA servers |

There are two separate connections to configure: **browser → IRIS API** and **IRIS → OPC UA server**. Their URLs and credentials are different. OPC UA hostnames and certificate paths must be accessible from the IRIS host, even when you use the console on your laptop. Collection continues in IRIS after you close the browser.

## Run with Docker

### 1. Start the backend

You need Docker with Compose, Bash and OpenSSL for generating demo certificates, and Node.js with npm for the frontend. Node.js 22 satisfies the frontend toolchain's declared engine requirement.

From a clone of this repository:

```bash
# Once, before the first build:
bash tools/certgen/generate.sh

# Build and start IRIS and the demo OPC UA servers:
docker compose up -d --build
docker compose logs -f iris
```

Wait for IRIS to finish starting. Ctrl+C exits the log view without stopping the containers. On subsequent starts, reuse the generated certificates; the generator expects `tools/certgen/temp` not to exist.

The image installs the libraries and ObjectScript code, creates the `OPCUA` namespace, and configures the REST API. **Compose does not start the frontend.**

### 2. Start the frontend

In another terminal:

```bash
cd webapp
npm ci
npm start
```

Open [http://localhost:4200](http://localhost:4200). Under **Settings → IRIS API Gateway**, use:

| Setting | Demo value |
|---|---|
| API Base URL | `/iris/csp/opcua/api` |
| IRIS API Username | `SuperUser` |
| IRIS API Password | `SYS` (uppercase) |

Save the settings. The development proxy forwards this path to `http://localhost:52783`. To check API access through the same route:

```bash
curl --user SuperUser http://localhost:4200/iris/csp/opcua/api/ping
```

Enter `SYS` when prompted. Expect JSON containing `"status":"ok"`. This verifies the API route, not the native library or OPC UA connectivity.

### 3. Connect to a demo server

Under **Settings → OPC UA Servers**, add:

| Setting | Value |
|---|---|
| Display Name | `Demo PLC` |
| OPC UA Server URL | `opc.tcp://plc:4840` |
| Security Mode | `None` |
| Username / Password | Leave empty |

Click **Test Connection**, then **Save Changes**. A second mock server is available at `opc.tcp://plc2:4840`.

These addresses are resolved inside Docker by IRIS. `localhost:10000` is the first mock server's address for clients running on your host, not for IRIS inside its container.

Continue with [Your first pipeline](#your-first-pipeline). The [IRIS Management Portal](http://localhost:52783/csp/sys/UtilHome.csp) uses the same `SuperUser` / `SYS` login; select namespace `OPCUA`.

### Stop and restart

```bash
docker compose stop
docker compose start
```

After changing ObjectScript or native libraries, rebuild with `docker compose up -d --build`. Frontend changes reload through `npm start`.

**The demo is disposable:** the current Compose file persists certificate volumes but has no IRIS database volume. Removing or recreating the IRIS container can lose schemas, pipeline configuration, and collected data. Use the demo credentials and certificates only for evaluation.

## Client installation

Installation on your own instance requires an IRIS administrator. Validate your target IRIS/OS/library combination in staging before deployment.

**Terminal installer (Linux IRIS servers).** [`setup-cli/`](setup-cli/README.md) installs and verifies everything in steps 1–4 over the IRIS web server, with no shell access to the IRIS host:

```bash
cd setup-cli
cargo build --release
./target/release/iris-opcua-setup
```

It asks for a connection (name, base URL, username, password), shows a review before changing anything, and ends with the API URL to enter in the webapp. See its README for the privileges it needs and exactly what it changes. It has been tested against IRIS 2025.3 on Linux ARM64. The manual path below remains available and is the only path for Windows servers.

### 1. Prepare a dedicated namespace

Use IRIS licensed and configured for interoperability productions. Create a dedicated interoperability-enabled namespace and database, for example `OPCUA`, with writable storage. Use that namespace throughout installation.

You will need:

- Access to the IRIS host to install libraries and certificates.
- Administrator access to import classes and configure an authenticated REST application.
- An HTTPS web server / InterSystems Web Gateway for the API and a web server for the frontend; these may share one origin.
- The OPC UA endpoint, credentials if required, and certificate/trust requirements from the server administrator.

**Use a dedicated namespace.** The console manages `OPCUA.Pipeline.Production`. Starting a pipeline currently stops another running production in the same namespace before starting its own.

Do not run `IRISConfig.Installer.Install()` on a client instance: it assumes Docker paths, creates demo credentials, and changes default-account password-expiration settings.

### 2. Install native libraries on the IRIS host

Find the instance's binary directory in an IRIS terminal:

```objectscript
write $System.Util.BinaryDirectory(), !
```

Select files for the **IRIS host's OS and CPU**, not the browser machine:

| IRIS host | Files |
|---|---|
| Linux x86-64 | `bin/unix/amd64/` |
| Linux ARM64 | `bin/unix/arm64/` |
| Windows x64 | `bin/windows/` — compatibility caveat below |

On Linux, install `irisopcua.so` and its required companion libraries from the matching directory into the instance's binary directory. Check dependencies on that host:

```bash
ldd /path/to/iris/bin/irisopcua.so
ldd /path/to/iris/bin/libopen62541.so.0
```

Resolve any `not found` dependencies. The Docker image also installs `libmbedtls-dev`; the required packages depend on the target OS. Do not overwrite existing instance libraries without checking compatibility.

On Windows, the connector uses `IrisOPCUA.dll` and `open62541.dll`. The supplied `libcrypto-1_1-x64.dll` is supplemental: **do not overwrite IRIS's existing copy**. The [Windows notes](bin/windows/README.md) warn that the binaries and source may be from different revisions. Confirm a matching build for the current console; the legacy Studio export does not replace the current REST classes.

No native macOS library set is included. On macOS, use the Linux Docker environment. The repository does not yet provide a tested compatibility matrix for client installations.

### 3. Load and compile ObjectScript

Copy `src/objectscript/OPCUA/` to a staging directory readable by IRIS **on the IRIS host**. Omit its `Tests/` directory for a client installation. The console does not require `Examples/`, `IRISConfig/`, or the legacy Studio project.

In an IRIS terminal, substitute your namespace and staging path. Run each command and resolve any reported error before continuing:

```objectscript
zn "OPCUA"
set sc = $System.OBJ.Load("/srv/iris-opcua/OPCUA/Constants.inc", "k")
do $System.Status.DisplayError(sc)
set sc = $System.OBJ.LoadDir("/srv/iris-opcua/OPCUA/", "k", , 1)
do $System.Status.DisplayError(sc)
set sc = $System.OBJ.CompilePackage("OPCUA", "ck")
do $System.Status.DisplayError(sc)
```

Load `Constants.inc` explicitly; `LoadDir` does not load include files automatically. On Windows, use the equivalent absolute staging path.

Register and test the library in the same namespace:

```objectscript
set sc = ##class(OPCUA.Utils).Install($System.Util.BinaryDirectory()_"irisopcua.so")
do $System.Status.DisplayError(sc)
set sc = ##class(OPCUA.Utils).Initialize()
do $System.Status.DisplayError(sc)
```

Use `IrisOPCUA.dll` instead on Windows. `Install()` only records the path; `Initialize()` actually loads and calls the library. Resolve loading errors before proceeding.

### 4. Configure the REST API

In the Management Portal, open **System Administration → Security → Applications → Web Applications** and create:

| Property | Value |
|---|---|
| Name | `/csp/opcua/api` |
| Namespace | Your dedicated namespace, e.g. `OPCUA` |
| Dispatch class | `OPCUA.REST.Handler` |
| Enabled | Yes |
| Authentication | Password authentication with an authorized IRIS account |

Configure your web server / InterSystems Web Gateway to serve this application through HTTPS. The externally visible prefix depends on the gateway: `/iris/csp/opcua/api` and `/csp/opcua/api` are not automatically interchangeable.

Create a dedicated API account with the application/database permissions needed to browse, generate and compile schema classes, and manage this namespace's production. The repository does not supply a predefined role or verified minimum-permission profile. Have your IRIS administrator validate these operations with the dedicated account.

Test your published URL, substituting your actual address and username:

```bash
curl --user opcua-console https://iris.example.com/csp/opcua/api/ping
```

Enter the password when prompted. Expect JSON containing `"status":"ok"`; an HTML login page is not an API success.

### 5. Host the frontend and connect it to IRIS

On a build workstation:

```bash
cd webapp
npm ci
npm run build
```

Publish the contents of `webapp/dist/webapp/browser/` on your HTTPS web server. Configure frontend routes such as `/schemas` and `/pipelines` to fall back to `index.html`; route API requests to IRIS separately. The default build assumes the site's root. For a subdirectory, use the appropriate base, for example `npm run build -- --base-href /opcua/`.

Prefer a same-origin deployment, with the web server proxying the API. If frontend and API use different origins, configure and verify CORS/preflight handling for your frontend origin, the `Authorization` header, and API methods. **The Angular development proxy is not part of the production build.**

Open **Settings → IRIS API Gateway** and enter your API URL and dedicated IRIS account credentials. Use the same-origin API path if you configured a proxy, or the full HTTPS API URL otherwise. Save the settings; changing the target instance needs no frontend rebuild.

For temporary development use, you can run `npm start` and edit `webapp/proxy.conf.json` to target your instance. It forwards the existing path unchanged: adjust the route/path handling if your gateway uses another prefix, then restart the development server.

**Current limitation:** IRIS and OPC UA passwords are saved in cleartext browser `localStorage`, per browser profile. Profiles do not automatically follow users between computers. See the [credential-storage review](webapp/SECURITY-REVIEW.md); improved authentication and server-side credential storage remain product work before a general client rollout.

### 6. Connect to the real OPC UA server

Under **Settings → OPC UA Servers**, add the endpoint and its credentials if required. These belong to the OPC UA server, separately from the IRIS API account.

For **Sign & Encrypt**, provision the following on the IRIS host and enter their paths:

- Client certificate and private key in DER format, readable by the IRIS service account. Restrict access to the private key.
- Trust directory containing the certificates needed to trust the server, and the revocation-list directory required by your certificate configuration.
- Client application URI matching the URI in the client certificate.

Have the server administrator trust the client certificate as well. The UI offers `None` and `Sign & Encrypt`, identifying `Basic256Sha256` for the latter; verify compatibility with your server. The console accepts filesystem paths and does not upload or provision certificates. Use your organization's certificates for client installations.

Click **Test Connection**, save, then verify browsing and actual collection below.

## Your first pipeline

1. In **Node Explorer**, select your server and browse to the device containing the measurements you need.
2. Open **Schemas → New Schema**. Select the server, mark a representative device as the template root, select measurement nodes, name the schema, and click **Save Schema**.
3. Bind devices to the saved schema. Select device roots, resolve validation errors, choose polling or subscription and collection settings, then deploy. For the local mock server, use `Objects` as the root and measurements such as `SA1`, `SA2`, and `VT5`.
4. Find the pipeline on the dashboard and start it. **Deployment creates a stopped pipeline; starting it begins collection.**
5. Open SQL in the Management Portal in the same namespace and query the table shown for the schema. For example, class `OPCUA.DS.MyDevice` uses table `OPCUA_DS.MyDevice`:

   ```sql
   SELECT TOP 20 * FROM OPCUA_DS.MyDevice ORDER BY ID DESC
   ```

Expect device identity in `NodePath`, plus each measurement's value, status, source timestamp, and server timestamp. Check the production event log if collection fails or quality is bad. With subscriptions, unchanged values may not produce a row every interval.

Reuse schemas for more devices of the same structure. Removing a pipeline retains its schema and collected data. Include the namespace database, production configuration, and certificates in operational backups; browser settings are separate.

## Troubleshooting

| Symptom | Check |
|---|---|
| Docker build cannot find certificates | Run `bash tools/certgen/generate.sh` before the first build |
| Certificate generator says temporary directory exists | Reuse existing outputs, or archive the previous generation before deliberately generating replacement demo identities |
| API returns 404 or HTML | Gateway prefix, REST application's namespace/dispatch class, and proxy routing |
| API returns 401/403 | IRIS credentials, authentication settings, application and namespace permissions |
| CORS or mixed-content error | HTTPS on both connections, preflight handling, or a same-origin proxy |
| `/ping` succeeds, connection test fails | Library initialization, reachability from IRIS, server credentials, security mode, and certificate trust |
| Native library will not load | Host architecture, dependency libraries, file access, and registered path |
| Pipeline starts but no rows appear | Device validation, production event log, measurement quality, and SQL namespace/table |
| Demo data disappears after container recreation | Compose currently has no persistent IRIS database volume |

## Further reading

- [OPC UA concepts and legacy demos](docs/opcua-concepts-and-legacy-demos.md) — original background material, with legacy instructions identified.
- [Architecture](docs/architecture.md) and [workflow diagrams](docs/workflow.md) — implementation details.
- [Setup improvements proposal](docs/setup-improvements.md) — recommended installer, diagnostics, and onboarding work; the terminal installer part is implemented in `setup-cli/`.
- [Terminal installer plan](docs/terminal-installer-plan.md) — design and integration-test evidence for `setup-cli/`.
