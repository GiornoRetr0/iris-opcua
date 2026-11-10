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
| ObjectScript (`backend/src/OPCUA/`) | A dedicated IRIS namespace | REST API, schema generation, background collection and storage |
| Native libraries (`bin/`) | The IRIS host | Communicate with OPC UA servers |

There are two separate connections to configure: **browser → IRIS API** and **IRIS → OPC UA server**. Their URLs and credentials are different. OPC UA hostnames and certificate paths must be accessible from the IRIS host, even when you use the console on your laptop. Collection continues in IRIS after you close the browser.

## Run with Docker

### 1. Start the backend

You need Docker with Compose, Bash and OpenSSL for generating demo certificates, and Node.js with npm for the frontend. Node.js 22 satisfies the frontend toolchain's declared engine requirement.

From a clone of this repository:

```bash
# Once, before the first build:
bash demo/certgen/generate.sh

# Build and start IRIS and the demo OPC UA servers:
docker compose up -d --build
docker compose logs -f iris
```

Wait for IRIS to finish starting. Ctrl+C exits the log view without stopping the containers. On subsequent starts, reuse the generated certificates; the generator expects `demo/certgen/temp` not to exist.

The image installs the libraries and ObjectScript code, creates the `OPCUA` namespace, and configures the REST API. **Compose does not start the frontend.**

### 2. Start the frontend

In another terminal:

```bash
cd webapp
npm ci
npm start
```

Open [http://localhost:4200](http://localhost:4200). The development server signs in by itself as the demo account, `SuperUser` / `SYS` (uppercase), against the API Base URL `/iris/csp/opcua/api`. To use another account, sign out under **Settings → IRIS API Gateway** and sign in again. The development proxy forwards this path to `http://localhost:52783`. To check API access through the same route:

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

**Terminal installer (Linux and Windows IRIS servers).** [`installer/`](installer/README.md) installs and verifies everything in steps 1–5 over the IRIS web server, with no shell access to the IRIS host. That includes the OPC UA Console, which IRIS then serves itself:

Download the single-file binary for your machine from [GitHub Releases](https://github.com/GiornoRetr0/iris-opcua/releases) and run it. It has everything it installs built in, so no clone or build is needed (see [its README](installer/README.md#download) for the file names, checksums and the macOS/Windows first-run prompts). To build it yourself: `(cd webapp && npm ci && npx ng build) && cd installer && cargo build --release`.

It asks for a connection (name, base URL, username, password), shows a review before changing anything, and ends with **Open OPC UA Console**. The console is at `/csp/opcua/ui/index.html` on the same IRIS, already pointed at its API, so there is no URL to enter and no proxy. The console is meant for SuperUser-level developer accounts. An account with only the installer's `OPCUA_API_<NAMESPACE>` role can manage schemas and anonymous pipelines (create, deploy, rebind, delete), but not credentials: any pipeline whose OPC UA server needs a username is refused with 403, because reading or writing an `Ens.Config.Credentials` entry needs `%Ens_Credentials`. Toggling (starting) pipelines with that role is not yet verified, and the dashboard shows row counts as unknown. See its README for the privileges it needs and exactly what it changes. It has been tested against IRIS 2025.3 on Linux ARM64. Windows x64 server support is new; see the installer README for what has been verified. The manual path below remains available.

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
| Linux x86-64 | `backend/native/linux-amd64/` |
| Linux ARM64 | `backend/native/linux-arm64/` |
| Windows x64 | `backend/native/windows-x64/` |

On Linux, install `irisopcua.so` and its required companion libraries from the matching directory into the instance's binary directory. Check dependencies on that host:

```bash
ldd /path/to/iris/bin/irisopcua.so
ldd /path/to/iris/bin/libopen62541.so.0
```

Resolve any `not found` dependencies. The Docker image also installs `libmbedtls-dev`; the required packages depend on the target OS. Do not overwrite existing instance libraries without checking compatibility.

On Windows, copy `IrisOPCUA.dll`, `open62541.dll` and `libcrypto-1_1-x64.dll` into the instance's binary directory. The supplied `libcrypto-1_1-x64.dll` is supplemental: **do not overwrite IRIS's existing copy**. `IrisOPCUA.dll` is built from the same sources as the Linux library (see the [Windows notes](backend/native/windows-x64/README.md)). The legacy Studio export does not replace the current REST classes and predates `OPCUA.Security.*` and the 0.5.0 connector, so it cannot be used for managed Sign & Encrypt.

No native macOS library set is included. On macOS, use the Linux Docker environment. The repository does not yet provide a tested compatibility matrix for client installations.

### 3. Load and compile ObjectScript

Copy `backend/src/OPCUA/` to a staging directory readable by IRIS **on the IRIS host**. That is the whole application: the console does not require `backend/tests/`, `backend/examples/`, the Docker installer in `demo/`, or the legacy Studio project.

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

The terminal installer does this step for you: IRIS serves the console from a file-only web application beside the REST API. To host it yourself instead, publish the contents of `webapp/dist/webapp/browser/` on your HTTPS web server. The build uses relative paths and hash routes (`#/schemas`), so it works under any directory and needs no `index.html` fallback. A `config.json` next to `index.html` containing `{"apiBaseUrl": "../api"}` (resolved against the console's own URL; an absolute path such as `/csp/opcua/api` also works) fixes the API address and skips the step below.

Prefer a same-origin deployment, with the web server proxying the API. If frontend and API use different origins, configure and verify CORS/preflight handling for your frontend origin, the `Authorization` header, and API methods. **The Angular development proxy is not part of the production build.**

Open **Settings → IRIS API Gateway**, enter your API URL, and sign in with your dedicated IRIS account. Use the same-origin API path if you configured a proxy, or the full HTTPS API URL otherwise. Save the settings; changing the target instance needs no frontend rebuild. The console signs in to IRIS's JWT login (`POST <api>/login`), so switch on **JWT Authentication** for the REST web application (the terminal installer does this). Without it the console falls back to sending the password with every call, kept in memory only, so each reload asks you to sign in again.

For temporary development use, you can run `npm start` and edit `webapp/proxy.conf.json` to target your instance. It forwards the existing path unchanged: adjust the route/path handling if your gateway uses another prefix, then restart the development server.

**OPC UA passwords** are stored in IRIS credentials entries (Interoperability > Configure > Credentials), never in the browser: each saved server names an entry, the API reads it on the server, and a pipeline deployed for that server uses the same entry.

**The IRIS sign-in** is a token, not a password: the password is sent once to `POST /login`, and the access and refresh tokens IRIS returns are kept in `sessionStorage`, so they last for that browser tab. The console refreshes them in the background; signing out revokes them, and an idle session expires (the refresh token's lifetime, 15 minutes by default). Nothing in `localStorage` is a secret. The server list is still per browser profile and does not follow users between computers. Cross-origin hosting needs a CORS preflight for `/login`, which IRIS does not answer by default, so serve the console from the API's origin.

### 6. Connect to the real OPC UA server

Under **Settings → OPC UA Servers**, add the endpoint and its credentials if required. These belong to the OPC UA server, separately from the IRIS API account.

For **Sign & Encrypt**, the console manages the certificates (you need an IRIS account with `%Admin_Secure:USE`, normally SuperUser level):

1. **Settings → OPC UA Security**: create the instance's client identity, import a certificate and key (PEM, DER or PKCS#12), or use existing DER files on the IRIS host. There is one identity per IRIS instance, shared by all namespaces, stored under the instance's `mgr/opcua-pki` directory (back it up).
2. On the server profile, choose Sign & Encrypt, review the server's certificate (subject, application URI, validity, SHA-256 fingerprint) and trust it. A CA-issued server certificate also needs the CA certificate and its CRL. The connection is then pinned to exactly that certificate; if the server presents a different one, you review and approve the replacement.
3. **Download IRIS's certificate** (DER or PEM) and have the server administrator trust it on the server. IRIS cannot do this for you; until it is done, Test Connection reports that the server has not approved IRIS's certificate and shows IRIS's fingerprint.
4. **Test Connection**. Pipelines deployed for that server use the same setup with no certificate settings of their own.

An empty trust list would make the OPC UA stack trust everything, so IRIS refuses to connect when a server has no reviewed certificate; it never falls back to an unencrypted connection.

**Manual configuration** still works: if you give certificate and key paths (DER, readable by the IRIS service account, key access restricted), a trust directory, a CRL directory and a Client URI matching the certificate, the connection uses exactly those, as in the Docker demo (`demo/certgen/generate.sh`). The UI offers `None` and `Sign & Encrypt`, identifying `Basic256Sha256` for the latter; verify compatibility with your server.

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
| Docker build cannot find certificates | Run `bash demo/certgen/generate.sh` before the first build |
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
- [Setup improvements proposal](docs/design/setup-improvements.md) — recommended installer, diagnostics, and onboarding work; the terminal installer part is implemented in `installer/`.
- [Terminal installer plan](docs/design/terminal-installer-plan.md) — design and integration-test evidence for `installer/`.
