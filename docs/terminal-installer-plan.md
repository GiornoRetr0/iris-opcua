# IRIS OPC UA terminal installer — implementation plan

Status: implemented in `setup-cli/` (binary `iris-opcua-setup`) and integration-tested; see §10 for evidence, deviations from this brief, and what remains unverified. This document is the implementation brief; it supersedes the terminal onboarding suggestions in [setup-improvements.md](setup-improvements.md).

## 1. Purpose and scope

Build a lightweight, attractive terminal tool that installs and verifies the OPC UA backend on an existing IRIS instance. It must be usable by an administrator seeing this repository for the first time.

The CLI does **not** discover instances and does not need the IRIS installation directory. The user defines the connection themselves — a name, a base URL, then a username and password — the same shape as a VS Code InterSystems Server Manager definition. Everything after that goes over HTTP to IRIS's built-in Atelier REST API (`/api/atelier`). The CLI can therefore run on the IRIS host or on another machine that can reach the instance's web server.

The first launch starts with defining the connection and authenticating. No installation, configuration, or operational menu is available until authentication succeeds. Remember the connection, including its password, so subsequent launches normally need no login prompt (see §6).

After login, guide the user through namespace selection, prerequisites, installation, verification, and a clear handoff to the existing webapp.

**The terminal must not configure or connect to OPC UA servers.** Server profiles, OPC UA certificates, browsing, schemas, device binding, pipelines, and collection belong exclusively in the webapp. Do not duplicate those screens or build a terminal monitoring product.

Other exclusions for the first release:

- Installing IRIS itself, automatic instance discovery, SSH, and any OS-level access to the IRIS host.
- Building or hosting the frontend, configuring web-server TLS, or installing a Web Gateway.
- Starting/stopping productions or the IRIS instance automatically.
- Account creation, password-policy changes, broad permission grants, or a general secrets-management system.
- Uninstall, automatic upgrades of incompatible native libraries, and unattended installation.

Platform scope is about the **IRIS server**, not the machine running the CLI: the CLI is a single Rust binary talking HTTP and builds for Linux, macOS, and Windows. Implement and validate against Linux IRIS servers first, covering amd64 and arm64 only where the supplied artifacts are verified compatible. Structure the artifact-selection code so Windows servers can be added later. Detect an unsupported server platform early (IRIS reports it after sign-in) and explain it clearly; do not advertise untested Windows/macOS server support.

## 2. Keep the implementation small

Write the CLI in Rust as one synchronous binary: no async runtime, no OpenSSL. Direct dependencies are limited to this set (measured with the finished crate, 2026-09-29: 46 packages besides the CLI itself on macOS/Linux, 49 on Windows):

| Need | Crate | Notes |
|---|---|---|
| HTTP/HTTPS | `ureq 3.4`, default features off, `rustls` | Blocking; agent-level connect/global timeouts; Basic auth is a header we build ourselves |
| JSON | `serde 1` (`derive`) + `serde_json 1` | Atelier bodies, ClientInstaller results, and the local config file |
| Terminal | `console 0.16`, default features off, `std` | Colors, TTY detection, `NO_COLOR`, and hidden password input (`Term::read_secure_line`) |
| Base64 | `base64 0.23` | Basic auth and chunked library upload; already in `ureq`'s tree |
| SHA-256 | `sha2 0.11`, default features off | Artifact verification |
| Arguments | `lexopt 0.3` | Only a few flags (`--dist <path>`, `--version`, `--help`); help text is hand-written |

```toml
[dependencies]
ureq = { version = "3.4.2", default-features = false, features = ["rustls"] }
serde = { version = "1.0.229", features = ["derive"] }
serde_json = "1.0.151"
console = { version = "0.16.6", default-features = false, features = ["std"] }
base64 = "0.23.1"
sha2 = { version = "0.11.0", default-features = false }
lexopt = "0.3.2"
```

Commit `Cargo.lock`. Adding any other crate needs a stated reason. Deliberately not used: `reqwest` (its blocking client runs Tokio internally), `indicatif` (the spinner is a small `std::thread` loop), `clap`, `toml`, keychain crates, and TUI frameworks such as `ratatui`: the full-screen screens (§5) are drawn with `console` alone.

TLS limit: `rustls` with bundled Mozilla roots does not trust enterprise CAs installed in the OS. An IRIS web server using an internal CA will fail the TLS handshake; the error must say so. Supporting it (ureq's platform-verifier feature or a per-connection CA file) is an open decision, not in the first release.

The interface is full-screen (decided 2026-09-29, replacing the original scrollback design): every step is its own screen drawn from the top of the window, menus move with the arrow keys, and the last screen stays visible after exit. See §5.

Put IRIS-specific inspection and installation logic in a separate parameterized ObjectScript installer class. Keep the current Docker demo installer working independently. Do not reuse its top-level `Install()` method for client installations.

Suggested layout:

```text
setup-cli/
  Cargo.toml / Cargo.lock        # binary: iris-opcua-setup
  README.md                      # build/run instructions and supported platforms
  .gitignore                     # local/ and target/
  local/                         # created at runtime: connections.json, progress, logs (never committed)
  src/
    main.rs                      # argument parsing, authentication gate, small workflow
    ui.rs                        # prompts, colors, spinner, status lines
    atelier.rs                   # HTTP client for /api/atelier: auth, doc upload, compile, query
    installer.rs                 # inspect, plan, apply, verify (calls ClientInstaller via atelier.rs)
    config.rs                    # connection profiles, base URL rules, saved passwords
    log.rs                       # redacted local/setup.log
    payload.rs                   # locate src/objectscript + bin/, select artifacts, hash them
  tests/
src/objectscript/IRISConfig/ClientInstaller.cls
```

The exact module boundaries can be simplified if useful. Build one binary, `iris-opcua-setup`, with `cargo build --release`. The CLI must locate the source/library payload (the repository's `src/objectscript/` and `bin/`) reliably when launched outside the repository directory: default to the checkout containing the binary, and accept `--dist <path>` when necessary.

## 3. Connection and bootstrap (proven)

The mechanism is the built-in Atelier REST API. It exists on a clean instance **before the OPC UA REST application exists**, so login never depends on `/csp/opcua/api`, and no new privileged HTTP endpoint is created.

A throwaway `intersystems/iris-community:2025.3` container (Linux arm64) confirmed, using only a base URL and credentials:

| Operation | Atelier call | Observed |
|---|---|---|
| Authenticate | `GET /api/atelier/` | 200 + server version with the right password; 401 for a wrong password or unknown user |
| Upload source | `PUT /api/atelier/v1/{ns}/doc/{name}?ignoreConflict=1` | `Constants.inc` + 43 classes in ~1 s. Without `ignoreConflict` a re-upload returns 409 |
| Compile | `POST /api/atelier/v1/{ns}/action/compile?flags=cuk` with a document list | Compiles only the listed documents. Compile errors come back in `status.errors` **with HTTP 200** |
| Run installer logic | `POST /api/atelier/v1/{ns}/action/query` calling `[SqlProc]` class methods with `parameters` | Runs as the authenticated user; values bound as SQL parameters; a JSON string result is returned already parsed |
| Create namespace/database with interoperability | `%Installer` manifest invoked from a SqlProc | Works (<1 s) |
| Stage native libraries | base64 chunks → SqlProc writing a file as the IRIS process | SHA-256 of all three files matched after upload |
| Load library | `OPCUA.Utils.Install()` → `Initialize()` → `GetVersion()` from a SqlProc | Loaded, version `0.4.0` |
| REST app | `Security.Applications.Create` from a SqlProc, then `GET {base}/csp/opcua/api/ping` | 200 with valid credentials; wrong password gives **404**, not 401 |

Bootstrap order: probe without credentials → authenticate → upload and compile `IRISConfig.ClientInstaller` into `%SYS` → all further inspection (including the `%SYSTEM.Security.Check` privilege checks) and installation are calls into that class. Atelier offers no way to evaluate `%SYSTEM.Security.Check` before a class exists, so an account without `%DB_IRISSYS` write is caught by the upload itself, whose error names the missing access. Loading the installer class is a post-authentication operation; it changes no configuration.

Rules for the bridge:

- Supply values as SQL parameters, never interpolated into ObjectScript or SQL text. Do not spawn any subprocess.
- Secrets go only in the `Authorization` header. Apart from a remembered password in `local/connections.json` (§6), they must not appear in URLs, logs, other files, or error output. Refuse a base URL containing embedded credentials.
- Every ClientInstaller method returns a JSON result with step identifier, outcome, concise explanation, and diagnostic details. Handle HTTP status, Atelier `status.errors`, IRIS `%Status` inside the result, malformed results, timeouts, and connection loss explicitly. **HTTP 200 is not proof that a compile or step succeeded.**
- Warn when the connection is plain `http://` to a host other than localhost: Basic credentials travel unencrypted. Allow it only after the user confirms.

Known limits of this mechanism:

- A 401 cannot distinguish a wrong password from an account that lacks `%Development` (Atelier requires it). The sign-in error must say both.
- If `/api/atelier` is disabled or blocked by the web gateway, report the target as unsupported and name the web application to enable. Do not fall back to another channel.
- Files written by IRIS get the IRIS process's umask (observed 0600). Atelier offers no chmod; that is sufficient for IRIS to load them.
- Missing native dependencies of the library cannot be checked before loading; the first evidence is `Initialize()` failing, which must be reported with its actual message.

## 4. User workflow

### A. First launch: define the connection and sign in

Show a small title followed immediately by the saved connections, if any, and the option to add one. No dashboard or feature menu yet.

```text
IRIS OPC UA Setup

Choose a connection

  1  iris-prod    https://iris.example.com/iris-prod   Saved login
  2  iris-test    http://10.0.0.12:52773               Session only
  N  New connection

Connection [1]:
```

A new connection asks, in order:

1. **Name** — a local label for this definition. Must be unique among saved connections.
2. **Base URL** — `http(s)://host(:port)/pathPrefix` or just a hostname/IP. The path prefix covers instances served behind a web gateway under a prefix.
   - If no port is written, **warn** that none was given and show the URL exactly as it will be used; do not assume 52773, 80, or 443. The user either confirms it or re-enters it.
   - If only a hostname is given, also ask for the scheme rather than guessing.
   - Show the final normalized URL before continuing.
3. **Username**, then **Password** (masked).

Then call `GET {base}/api/atelier/`. Distinguish: unreachable host/port, TLS error, non-IRIS response, Atelier disabled (404 on `/api/atelier/`), and 401 (wrong credentials **or** missing `%Development`). Offer Retry and Edit connection; preserve the entered name and URL when going back.

After successful authentication, record the instance identity reported by IRIS (`%SYS.System.InstanceGUID()`, version, platform) with the connection. Then ask whether to remember the password (default Yes), stating where it will be saved (§6). Choosing No keeps it for this session only.

On later launches, validate the saved credential against the remembered URL, user, and instance GUID. Show the authenticated target before offering any action. If authentication fails, preserve non-secret setup choices and return to sign-in with a short explanation. If the GUID differs from the one recorded, stop and say the URL now reaches a different instance; do not continue silently.

### B. Inspect and show the next action

Automatically inspect version/server platform, privileges, installed artifacts, namespace/application configuration, and prerequisites. Inspection is read-only.

```text
IRIS OPC UA Setup
iris-prod · https://iris.example.com/iris-prod · signed in as installer-admin

  OK    IRIS connection
  OK    Server platform and native artifacts
  OK    Interoperability available
  TODO  OPC UA backend installation

  1  Set up backend                  Recommended
  2  Check installation
  3  Switch connection / sign out
  Q  Exit
```

Adapt the recommended action to actual state: Set up backend, Resume setup, Repair installation, or Show connection details. Do not force healthy installations through the wizard again. No upgrade option until a tested upgrade policy exists.

### C. Choose a dedicated namespace

Recommend creating `OPCUA` with a database in the instance's default manager directory (reported by IRIS). Offer compatible existing dedicated namespaces after inspection. Present connection, namespace, and whether each resource will be created or reused.

Do not assume that an existing namespace called `OPCUA` belongs to this tool. Check its content, mappings, application ownership, and production configuration. Refuse an unrelated production/application conflict and explain how to select a separate namespace. Never stop a production to make installation proceed.

Derive normal paths and API application defaults from what the instance reports. Hide optional overrides behind one Advanced settings choice. Prompt only for missing decisions; validate answers immediately and preserve them when the user goes Back.

### D. Preflight and review

Complete prerequisite checks before writing libraries or importing application code: server OS/CPU and artifact compatibility, whether the IRIS process can write to its `bin` directory, source payload completeness, IRIS privileges, namespace suitability, and web-application conflicts.

Required IRIS privileges, checked with `%SYSTEM.Security.Check`: `%Development:USE` (Atelier and compile), `%Admin_Manage:USE` (namespace/database), `%Admin_Secure:USE` (web application), and write access to `%DB_IRISSYS` (installer class in `%SYS`). List exactly which are missing. Never grant privileges.

The CLI has no OS access to the server. All file writes are done by the IRIS process through the ClientInstaller. If the IRIS process cannot write to its `bin` directory (likely on native installs where `bin` is root-owned — unverified), stop before any change and show the narrow manual action: the exact files, their SHA-256, and the destination path, for a server administrator to copy. Retry then verifies the hashes and continues.

Present one review of the concrete changes:

```text
Ready to install into iris-prod (https://iris.example.com/iris-prod)

Namespace       OPCUA                  Create
Native adapter  Linux ARM64            Upload through IRIS
ObjectScript    OPCUA application       Import and compile
REST app        /csp/opcua/api          Create

Enter Install to continue, B to go back, or Q to save and exit:
```

Ask once for this installation, not once per file. Existing compatible resources should be marked Reuse. A conflicting REST path must not be silently retargeted or have its security settings overwritten.

### E. Apply and verify

Show sequential named steps and elapsed activity, without fabricated percentage completion:

```text
  OK    Native libraries installed
  OK    Namespace ready
  ...   Importing and compiling ObjectScript
  WAIT  Registering and loading native connector
  WAIT  Configuring REST application
  WAIT  Verifying backend
```

Required backend behavior:

1. Install only verified matching native artifacts, chosen from the server platform IRIS reports. Upload in chunks to a staging file inside IRIS's `bin` directory, verify SHA-256, then move into place. Compare existing files by hash: identical means Reuse; different and not previously installed by this tool means refuse. Never overwrite an IRIS-provided crypto library. If an existing file is in use or needs replacement, stop with a maintenance instruction.
2. Create or reuse the selected dedicated namespace/database with interoperability enabled. Preserve existing data and configuration.
3. Upload `OPCUA/Constants.inc` explicitly, then the application classes. Exclude `Tests/`, `Examples/`, and the Docker demo installer from the client payload. Compile the uploaded documents only, and treat any `status.errors` entry as a failed step.
4. Register the library using `OPCUA.Utils.Install()` and load/test it using `Initialize()` and `GetVersion()`. Registering a path alone is not a successful library installation.
5. Create or verify the REST application pointing to `OPCUA.REST.Handler` in the chosen namespace, with password authentication and an explicitly defined application resource/permission contract. Do not copy demo credentials, enable anonymous access, grant `%All`, or change password policies.
6. Verify the expected classes, namespace, library, and application configuration. Then check authenticated `GET {base}/csp/opcua/api/ping` as a separate result. A 404 there with good Atelier credentials means the account lacks access to the new app or the gateway does not route it; say which. Its fixed version string is not native-library compatibility evidence.

Use the authenticated administrator for installation; do not silently convert that account into the permanent webapp login or export its password. A dedicated runtime API user can be provisioned through existing IRIS administration and verified separately.

### F. Finish with a webapp handoff

Propose `{base URL}/csp/opcua/api` as the API base URL and let the user confirm or change it; the browser may reach IRIS through a different address than the CLI did. Never label an unchecked URL verified.

```text
Backend installed

  OK    Classes compiled
  OK    Native connector loaded
  OK    REST application configured
  OK    API responds at the address below (checked from this machine)

In the webapp, open Settings → IRIS API Gateway:

  API Base URL   https://iris.example.com/iris-prod/csp/opcua/api
  Username       Use your authorized IRIS API account

Then configure your OPC UA servers in the webapp.

  1  Show connection details
  2  Run checks again
  Q  Exit
```

If the API path is not reachable, say **Backend installed; HTTP access not yet verified**, save progress, and show specific routing instructions. Do not roll back a working backend or describe it as fully ready. A check from the CLI's machine does not prove the user's browser can reach the endpoint or that cross-origin requests will work; label the test's scope.

Offer a small export of non-secret connection details and setup status. Do not put passwords in that file, terminal output, frontend URLs, or clipboard data. Do not prompt for an OPC UA endpoint. End the setup here.

## 5. Visual design and interaction rules

- Compact title, consistent spacing, and one restrained accent color. No large ASCII logo, emoji decoration, or heavy nested boxes.
- Green `OK` for verified success; red `FAIL` for blocking errors; amber `ACTION` for incomplete external work; cyan for the current step; muted `WAIT` for pending work.
- Every color has a text label. Use portable ASCII status words by default so rendering and screen readers do not depend on glyph support.
- Show connection name, URL, and selected namespace on every review, mutation, and result screen. Revalidate the target after switching connection.
- One screen per step: a header with the tool name and connection (name · URL · user), a rule, the screen title, the content, the menu, and a dimmed key-hint footer (`↑↓ | Enter | B Back | Q Quit`).
- Menus: ↑/↓ move a `➤` marker, Enter selects, and every item also has a key (number or letter) that selects it directly; Esc means Back. Items that cannot be chosen are shown dimmed with the reason (for example an unusable namespace). `B` goes Back, `R` retries a failed step, and `Q` saves non-secret progress and exits where relevant.
- Text fields (name, URL, username, password, API URL) sit under an explanation of what the value is; Enter keeps a bracketed default. Validation errors appear in red on the same screen.
- The installation screen lists every step and updates it in place: `WAIT`, the spinner with elapsed seconds, then `OK` or `FAIL`.
- During a running mutation, do not display actions that cannot be honored safely. Handle interruption at a safe boundary; otherwise record the outcome as unknown and inspect it on the next run.
- Use a spinner only on an interactive terminal while real work is running. A cleared screen loses history, so failures stay on screen until the user acts, and details are also written to `local/setup.log`.
- Respect `NO_COLOR`, `TERM=dumb`, non-TTY output, and narrow terminals (long lines are truncated rather than wrapped mid-screen). With redirected output or `TERM=dumb` the same screens are printed one after another in plain text, menus read a typed key, and no cursor control is emitted. Do not read or echo passwords from noninteractive stdin; first release should explain that interactive authentication is required.
- Normal operation should show concise outcomes; detailed sanitized diagnostics live behind Details and in a log file.

Example failure:

```text
FAIL  Native connector could not load

IRIS reported: libopen62541.so.0: cannot open shared object file.
Install the matching dependency on the IRIS server, then retry this check.

Completed installation steps have been preserved.

R  Retry    D  Details    Q  Save and exit
```

Use the actual reported error and corrective instruction, not a generic “Something went wrong.” Distinguish authentication failures, missing privileges, unreachable or non-IRIS URLs, disabled Atelier, incompatible binaries, compilation errors, and an unreachable OPC UA API path.

## 6. Persistence, retries, and credentials

Store all local state in `setup-cli/local/` — the tool's own folder, listed in `.gitignore` so it is never committed:

- `connections.json`: per connection its name, normalized base URL, username, **password (when remembered)**, recorded instance GUID/version/platform, selected namespace, installation choices, and optional API URL.
- Progress and log files.

This is deliberately simple: the tool is run by an IRIS administrator on a machine they control, and the passwords are stored in plain text on purpose. No keychain and no home-grown encryption; either would add complexity without protecting the file from the admin who already owns it. What is still required:

- Create `local/` with mode 0700 and the files with mode 0600 on Linux/macOS (on Windows they inherit the folder's ACL — document this).
- Say at the "remember password" prompt exactly which file it goes into.
- The password never appears in terminal output, logs, diagnostics, progress files, or the webapp handoff export — only in `connections.json`.
- Bind a remembered password to the URL, the user, and the instance GUID, not just the connection name.

Use a per-connection lock to prevent simultaneous installations from this machine. Save progress atomically. Redact passwords, `Authorization` headers, and credentials embedded in URLs from all logs and diagnostics. Keep logs private and show their location on failure.

Treat saved progress as a hint, not proof: inspect actual IRIS state before skipping or retrying a step. Reruns must preserve databases, collected data, user-created schemas, and application settings. Retry must not create duplicate resources. Track only resources owned by this installer; never clean up arbitrary existing resources.

Do not promise transactional rollback across IRIS and the filesystem. Preserve completed safe steps, record partial/unknown state, and show the recovery action. If an existing binary is in use or needs replacement, stop with a maintenance instruction rather than overwriting it or restarting IRIS automatically.

Provide Switch connection, Sign out, Forget saved login, and Delete connection as distinct actions. Switching re-enters the authentication gate; signing out ends the current authenticated context; forgetting removes the saved password from `connections.json` without removing the connection or the installation; deleting removes the local connection definition only.

## 7. Repository facts to account for

- `src/objectscript/IRISConfig/Installer.cls` is a Docker/demo installer with fixed paths, demo credentials, and password-policy changes. Keep it separate.
- `src/objectscript/OPCUA/Utils.cls` exposes library path registration, initialization, and version retrieval.
- `src/objectscript/OPCUA/REST/Handler.cls` supplies `/ping`; it does not perform comprehensive readiness checks.
- Native artifacts live in `bin/unix/{amd64,arm64}/` and `bin/windows/`; Windows notes explicitly flag potential source/binary mismatch.
- `irisopcua.so` needs `libopen62541.so.0` and `libcrypto.so.1.1` and has no RUNPATH, so all three must sit in the IRIS `bin` directory, where IRIS's loader path finds them.
- The existing frontend already has IRIS API settings and OPC UA server setup. No duplicate CLI feature is needed.
- Pipeline startup currently can stop another production in the namespace. Dedicated namespace isolation is required; changing pipeline behavior is a separate product task.
- Current browser credential storage remains a separate frontend/backend concern. This installer must not spread or duplicate that storage approach.

## 8. Implementation sequence

1. ~~Prove the connection mechanism~~ — done (§3). Steps 1–5 are implemented in `setup-cli/`; §10 records the evidence and the open items.
2. Implement read-only inspection and the parameterized `ClientInstaller` with explicit result reporting and repeatable steps. Establish compatible artifacts and required privileges.
3. Add the linear UI, review screen, progress, failure recovery, and saved-login flow.
4. Add backend verification, OPC UA API verification, and non-secret webapp handoff. Keep frontend and OPC UA setup out of scope.
5. Exercise the acceptance scenarios below, document supported IRIS versions/server platforms, and update the root README with tested CLI commands while retaining the manual installation path.

Do not mark a platform supported because source code contains a branch for it. Do not add speculative installer features to the README before they work.

## 9. Acceptance scenarios

Use meaningful automated tests for state transitions, request/data handling, redaction, idempotency, and failure recovery, plus an actual disposable IRIS integration environment. Mocked HTTP responses alone do not establish a working installer.

- Fresh instance with no OPC UA classes/API: define connection, authenticate, install, load library, and verify REST response.
- Wrong password: no protected operation occurs; retry works; secret never appears in output or logs.
- URL without a port: the CLI warns and shows the exact URL; nothing is assumed.
- Unreachable URL, non-IRIS URL, and Atelier disabled: each gets its own message; no credentials are sent to a non-IRIS response more than once.
- Relaunch: saved login validates without prompting; expired/changed credential returns to login without losing setup choices; a URL that now reaches a different instance GUID is refused.
- Remember password declined: session-only operation works and `connections.json` holds no password. Accepted: file mode is 0600 and the password appears nowhere else (output, logs, export).
- Two connections: select/switch correctly; credentials and installer state never cross targets.
- Missing IRIS privileges: actionable preflight failure naming the missing privileges, before application changes, with no silent privilege grant.
- IRIS process cannot write to `bin`: stop before changes; manual copy instruction with hashes; Retry continues once the files match.
- Existing unrelated namespace/production or API path: refuse the conflict without altering it.
- Incompatible server platform or library: fail before installation; show the detected mismatch and repair instruction.
- Compile failure or interrupted installation: no false success; rerun inspects state and resumes without duplicate resources or data loss.
- Healthy existing install: verification is read-only; rerun preserves user schemas, database contents, settings, and account policies.
- Backend installed but OPC UA API path unreachable: report partial readiness accurately and allow later verification.
- Narrow terminal, no color, redirected output, and Ctrl+C: readable output, no secret leakage or traceback-only failure, safe recovery.
- Completed handoff: user receives the API connection information and continues in the webapp; the CLI never asks for an OPC UA endpoint or starts a production.

Deliver the CLI, client ObjectScript installer, tests, verified compatibility notes, and concise installation documentation. Include the actual integration-test evidence and any remaining platform limitations in the implementation handoff.

## 10. Implementation notes and evidence

### Deviations from this brief, found during integration testing

- **Namespace creation does not use `%Installer`.** Its manifest writes `^SECURITY` directly, which fails with `<PROTECT>` for an administrator without `%All`, even one holding `%Manager`. `CreateNamespace` uses `Security.Resources`, `SYS.Database.CreateDatabase`, `Config.Databases`, `Config.Namespaces` and `%EnsembleMgr.EnableNamespace` instead. Each step is repeatable, and a database directory the installer started is recorded so an interrupted creation resumes. A database file it did not create is never adopted.
- **An extra precondition: access to the namespace database.** IRIS does not give an administrator access to a database they create. Unless the account has `%All`, an administrator must create `%DB_<NS>` and grant it RW before installing. The preflight checks this (`databaseAccess`) and names the resource. The installer never grants it.
- **The REST contract is one resource plus one role per namespace.** Every app requires resource `OPCUA_API`. Role `OPCUA_API_<NS>` grants `OPCUA_API:USE` and `%DB_<NS>:RW`, is created unassigned, and the handoff says to grant it to webapp accounts. A per-namespace role means a second installation never widens an existing role.
- **Ownership is recorded in `^IRISConfig.ClientInstaller` (in `%SYS`),** covering the files, namespaces, database directories, apps, resource and role it created. "Installed by this tool" in §4C/§4E is read from there.
- **The local lock is an OS file lock** (`File::try_lock`), so a run killed by Ctrl+C releases it. Progress is recorded as `running:<step>` before each step. The next launch reports that outcome as unknown and inspects fresh.
- **Password input is read key by key in raw mode.** `console`'s `read_secure_line` only turns echo off, so Ctrl+C there would leave the terminal without echo.
- **Server identity comes from the Atelier root response.** `GET /api/atelier/` returns `id`, which equals `%SYS.System.InstanceGUID()`. The GUID check therefore happens before anything is uploaded.
- **The server is identified before any credentials are sent.** Unauthenticated `GET /api/atelier/` → 401 means Atelier is present. A 404, combined with the Portal login page answering 200, means Atelier is disabled. Anything else is reported as not IRIS. Redirects are not followed, so the `Authorization` header is never replayed to another address.

### Integration evidence

The tests ran against a disposable `intersystems/iris-community:2025.3` container on Linux ARM64. The CLI was driven through a pseudo-terminal, from macOS and, as a Linux ARM64 binary, from a `rust:1` container.

| Scenario (§9) | Result |
|---|---|
| Fresh instance: install, load library, verify REST | OK. Three libraries uploaded and hash-verified, namespace created, 44 documents compiled, library version 0.4.0, `/ping` 200 |
| Wrong password, then Retry | 401 message names both causes; retry succeeded; password absent from terminal output and `setup.log` |
| URL without port; host without scheme | Warning plus the exact URL; declining asks again; scheme prompt has no default |
| Unreachable, non-IRIS, Atelier disabled, self-signed TLS | Four distinct messages, none sending credentials |
| Relaunch with saved login | No prompt; healthy install recommends the handoff, not the wizard |
| Different instance GUID | Refused, then an explicit opt-in to retarget |
| Remember declined / accepted | No `password` key / key present; `local/` 0700, files 0600 |
| Plain http to a non-localhost host | Confirmation required before credentials are sent |
| `%Developer`-only account | Installer upload refused with IRIS's reason (`#5883`, no write on the `%SYS` routine database) |
| Missing `%Admin_Manage` / `%Admin_Secure` | Listed on the overview and in the preflight; nothing changed |
| `%Manager` + `%Developer` account without `%All` | Preflight names `%DB_<NS>`; after an admin grant, Retry installed fully; `/ping` → "refused … grant `OPCUA_API_<NS>`" |
| Account holding only `OPCUA_API_NS7` | `/ping`, `/pipelines`, `/schemas` 200 on its app; 403 on another namespace's app |
| IRIS cannot write `bin` (mode 0500) | Stopped before changes with files, SHA-256 and destinations; after a manual copy, Retry reused them |
| Namespace with a foreign class | Refused, naming the class |
| REST path owned by another namespace | Refused; Advanced settings path used instead |
| Database file left by an earlier failed attempt | Refused, not adopted |
| Compile error (broken class via `--dist`) | Step FAIL with IRIS's compiler error; next launch offered Resume and completed, reusing the namespace |
| Ctrl+C during installation / at password prompt | Recorded as unknown and resumed without the stale lock blocking / "Cancelled.", terminal restored |
| Forget saved login, Delete connection | Password removed and setup kept / local definition removed |
| Redirected stdin, `--help`, `--version`, bad flag | Clear message, exit code 2 or 0 |

### Not verified

- A native (non-container) Linux install, where `bin` is typically root-owned. The manual-copy path was exercised only by making a container's `bin` read-only.
- amd64 servers: the artifact selection and hashes are unit-tested, but no amd64 IRIS was installed.
- A successful HTTPS sign-in: no TLS-enabled IRIS web server was available. TLS failure classification was tested.
- An IRIS behind a path prefix or an external Web Gateway, and the "not routed" 404 message for the API.
- Whether `OPCUA_API_<NS>` alone is enough to deploy and start pipelines. Production control may need interoperability roles, so for now that role covers the read endpoints only.
- Windows builds of the CLI (not compiled; the only local Rust target was macOS).
- Loader messages when a native dependency is missing: `LoadInto` reads them from `messages.log`, but no missing-dependency failure was staged.
