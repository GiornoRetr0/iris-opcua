# IRIS OPC UA terminal installer — implementation plan

Status: approved product direction, implementation pending. This document is the implementation brief; it supersedes the terminal onboarding suggestions in [setup-improvements.md](setup-improvements.md).

## 1. Purpose and scope

Build a lightweight, attractive terminal tool that installs and verifies the OPC UA backend on an existing local IRIS instance. It must be usable by an administrator seeing this repository for the first time.

The first launch starts with instance selection and authentication. No installation, configuration, or operational menu is available until authentication succeeds. Remember the connection securely so subsequent launches normally need no login prompt.

After login, guide the user through namespace selection, prerequisites, installation, verification, and a clear handoff to the existing webapp.

**The terminal must not configure or connect to OPC UA servers.** Server profiles, OPC UA certificates, browsing, schemas, device binding, pipelines, and collection belong exclusively in the webapp. Do not duplicate those screens or build a terminal monitoring product.

Other exclusions for the first release:

- Installing IRIS itself, remote SSH administration, and automatic container discovery.
- Building or hosting the frontend, configuring web-server TLS, or installing a Web Gateway.
- Starting/stopping productions or the IRIS instance automatically.
- Account creation, password-policy changes, broad permission grants, or a general secrets-management system.
- Uninstall, automatic upgrades of incompatible native libraries, and unattended installation.

Implement and validate local Linux installation first, covering amd64 and arm64 only where the supplied artifacts are verified compatible. Structure OS-specific code so Windows can be added later. Detect unsupported platforms early and explain them clearly; do not advertise untested Windows/macOS support.

## 2. Keep the implementation small

Use a Python CLI with the standard library for prompts, subprocesses, configuration, and orchestration. Use **Rich** for consistent colors, status lines, compact tables, and progress, and **keyring** for OS-backed credential storage. These are the only direct third-party runtime dependencies planned. Do not add a full-screen TUI framework, prompt-toolkit, a web service, Node.js, or a background daemon.

Use normal numbered choices and Enter to accept a visible default. Arrow-key menus are unnecessary. Use masked password input. Keep terminal output in scrollback instead of repeatedly clearing the screen.

Put IRIS-specific inspection and installation logic in a separate parameterized ObjectScript installer. Keep the current Docker demo installer working independently. Do not reuse its top-level `Install()` method for client installations.

Suggested layout:

```text
tools/installer/
  pyproject.toml                  # dependencies and iris-opcua-setup entry point
  README.md                      # install/run instructions and supported platforms
  iris_opcua_setup/
    cli.py                       # authentication gate and small workflow
    ui.py                        # shared prompts, colors, progress, messages
    platform.py                  # local discovery, OS checks, credential-store access
    iris.py                      # authenticated subprocess bridge and result parsing
    installer.py                 # inspect, plan, apply, verify
    config.py                    # profile metadata and credential references
  tests/
src/objectscript/IRISConfig/ClientInstaller.cls
```

The exact module boundaries can be simplified if useful. Package one command, `iris-opcua-setup`, and document a reproducible isolated installation. Do not modify the system Python environment. The CLI must locate the source/library payload reliably when launched outside the repository directory; accept an explicit distribution path when necessary.

## 3. Resolve authentication and bootstrap first

Before building the full interface, prove the supported mechanism for enumerating local IRIS instances, authenticating the supplied credentials, and running administrative ObjectScript as that identity. Verify against the target IRIS version and official documentation; do not invent command-line authentication flags or depend on scraping unstable terminal prompts.

This must work on a clean instance **before the OPC UA REST application exists**. Do not make login depend on `/csp/opcua/api`, and do not treat successful OS-owner access to an IRIS session as verification of the supplied username/password. Keep discovery read-only; loading the installer itself is a post-authentication operation.

Use the same bridge for inspection, importing the client installer, and structured installation calls. Supply values as data, not interpolated ObjectScript or shell fragments. Do not use `shell=True`. Secrets must not appear in command arguments, generated scripts, logs, URLs, or exception dumps. Use a supported protected input mechanism.

Return structured results with step identifier, outcome, concise explanation, and diagnostic details. Isolate those results from IRIS startup text and compile output. Handle process exit status, IRIS `%Status`, malformed results, timeouts, and unexpected EOF explicitly. A process exiting normally is not proof that compilation succeeded.

If a secure authentication/administration bridge cannot be established for a target, report it as unsupported. Do not quietly bypass login or create a new privileged HTTP endpoint as a workaround.

## 4. User workflow

### A. First launch: select instance and sign in

Show a small title followed immediately by detected local instances. Include names, locations, and running/stopped status. No dashboard or feature menu yet.

```text
IRIS OPC UA Setup

Choose an IRIS instance

  1  IRIS-PROD    /opt/iris       Running
  2  IRIS-TEST    /opt/iris-test  Stopped

Instance [1]:
Username:
Password:
```

Offer manual instance location when discovery finds none or misses the intended instance. Validate it rather than asking the user to guess library paths. A stopped instance gets a clear instruction to start it through their normal administration process and a Retry action.

After successful authentication, remember the instance and username. Save the credential in the OS credential store when available, with a visible explanation and a session-only choice. If no secure store is available or it is locked, offer session-only use and explain how to enable remembering; never fall back to plaintext files or home-grown encryption.

On later launches, validate the saved credential against the remembered instance and identity. Show the authenticated target before offering any action. If it fails, preserve non-secret setup choices and return to sign-in with a short explanation. Do not fall back to another instance silently.

### B. Inspect and show the next action

Automatically inspect version/platform, privileges, installed artifacts, namespace/application configuration, and prerequisites. Inspection is read-only.

```text
IRIS OPC UA Setup
IRIS-PROD · /opt/iris · signed in as installer-admin

  OK    IRIS connection
  OK    Platform and native artifacts
  OK    Interoperability available
  TODO  OPC UA backend installation

  1  Set up backend                  Recommended
  2  Check installation
  3  Switch instance / sign out
  Q  Exit
```

Adapt the recommended action to actual state: Set up backend, Resume setup, Repair installation, or Show connection details. Do not force healthy installations through the wizard again. No upgrade option until a tested upgrade policy exists.

### C. Choose a dedicated namespace

Recommend creating `OPCUA` with an appropriately located database. Offer compatible existing dedicated namespaces after inspection. Present instance, namespace, and whether each resource will be created or reused.

Do not assume that an existing namespace called `OPCUA` belongs to this tool. Check its content, mappings, application ownership, and production configuration. Refuse an unrelated production/application conflict and explain how to select a separate namespace. Never stop a production to make installation proceed.

Derive normal paths and API application defaults from the chosen instance. Hide optional overrides behind one Advanced settings choice. Prompt only for missing decisions; validate answers immediately and preserve them when the user goes Back.

### D. Preflight and review

Complete prerequisite checks before copying libraries or importing application code. Check OS/CPU and artifact compatibility, instance/database directory permissions, source payload completeness, dependencies, IRIS privileges, namespace suitability, and web-application conflicts.

IRIS authentication does not provide OS filesystem privileges. If elevated file access is needed, explain the exact path and operation, stop before partial changes, and provide a narrow administrator action. Do not launch the entire CLI under sudo by default or switch credential stores unexpectedly.

Present one review of the concrete changes:

```text
Ready to install into IRIS-PROD

Namespace       OPCUA                  Create
Native adapter  Linux ARM64             Install
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

1. Install only verified matching native artifacts; compare existing files and refuse unknown/incompatible replacements. Never overwrite an IRIS-provided crypto library blindly. Stage file copies before replacing installer-owned files.
2. Create or reuse the selected dedicated namespace/database with interoperability enabled. Preserve existing data and configuration.
3. Load `OPCUA/Constants.inc` explicitly before loading and compiling the application classes. Exclude `Tests/`, `Examples/`, and the Docker demo installer from the client payload. Compile the installed classes, not every class in the namespace.
4. Register the library using `OPCUA.Utils.Install()` and load/test it using `Initialize()` and the available version call. Registering a path alone is not a successful library installation.
5. Create or verify the REST application pointing to `OPCUA.REST.Handler` in the chosen namespace, with authenticated access and an explicitly defined application resource/permission contract. Do not copy demo credentials, enable anonymous access, grant `%All`, or change password policies.
6. Verify the expected classes, namespace, library, and application configuration. If an HTTP endpoint is provided, check authenticated `/ping` through it as a separate result. Its fixed version string is not native-library compatibility evidence.

The implementation must document and validate required IRIS privileges. Use the authenticated administrator for installation; do not silently convert that account into the permanent webapp login or export its password. A dedicated runtime API user can be provisioned through existing IRIS administration and verified separately.

### F. Finish with a webapp handoff

Ask for or confirm the externally served API base URL when needed. It depends on the web server/gateway and cannot always be inferred from the local instance. Never label a guessed URL verified.

```text
Backend installed

  OK    Classes compiled
  OK    Native connector loaded
  OK    REST application configured
  OK    API responds at the address below

In the webapp, open Settings → IRIS API Gateway:

  API Base URL   https://iris.example.com/csp/opcua/api
  Username       Use your authorized IRIS API account

Then configure your OPC UA servers in the webapp.

  1  Show connection details
  2  Run checks again
  Q  Exit
```

If gateway hosting is incomplete, say **Backend installed; HTTP access not yet verified**, save progress, and show specific routing instructions. Do not roll back a working backend or describe it as fully ready. A local HTTP test does not prove the user's browser can reach the endpoint or that cross-origin requests will work; label the test's scope.

Offer a small export of non-secret connection details and setup status. Do not put passwords in that file, terminal output, frontend URLs, or clipboard data. Do not prompt for an OPC UA endpoint. End the setup here.

## 5. Visual design and interaction rules

- Compact title, consistent spacing, and one restrained accent color. No large ASCII logo, emoji decoration, or heavy nested boxes.
- Green `OK` for verified success; red `FAIL` for blocking errors; amber `ACTION` for incomplete external work; cyan for the current step; muted `WAIT` for pending work.
- Every color has a text label. Use portable ASCII status words by default so rendering and screen readers do not depend on glyph support.
- Show instance and selected namespace on every review, mutation, and result screen. Revalidate the target after switching instance.
- Stable numbered menus; Enter uses a displayed default. `B` goes Back, `R` retries a failed step, `D` shows details, and `Q` saves non-secret progress and exits where relevant.
- During a running mutation, do not display actions that cannot be honored safely. Handle interruption at a safe boundary; otherwise record the outcome as unknown and inspect it on the next run.
- Use a spinner only on an interactive terminal while real work is running. Preserve the final step result and provide a route to detailed logs for long operations.
- Respect `NO_COLOR`, `TERM=dumb`, non-TTY output, and narrow terminals. No ANSI animation or cursor control in redirected output. Do not read or echo passwords from noninteractive stdin; first release should explain that interactive authentication is required.
- Normal operation should show concise outcomes; detailed sanitized diagnostics live behind Details and in a log file.

Example failure:

```text
FAIL  Native connector could not load

The required library libexample.so is missing on this host.
Install the matching dependency, then retry this check.

Completed installation steps have been preserved.

R  Retry    D  Details    Q  Save and exit
```

Use the actual detected dependency and corrective instruction, not a generic “Something went wrong.” Distinguish authentication failures, permission failures, incompatible binaries, compilation errors, and unreachable HTTP endpoints.

## 6. Persistence, retries, and credentials

Store non-secret profile data in the OS-appropriate per-user configuration directory with restrictive permissions: stable instance identity/location, username, selected namespace, installation choices, and optional API URL. Store only the keyring reference in that configuration. Bind stored credentials to the instance identity and user, not just a display name or port.

Use a per-target lock to prevent simultaneous installations. Save progress atomically. Redact passwords, authorization headers, and credentials embedded in URLs from all logs and diagnostics. Keep logs private and show their location on failure.

Treat saved progress as a hint, not proof: inspect actual IRIS and filesystem state before skipping or retrying a step. Reruns must preserve databases, collected data, user-created schemas, and application settings. Retry must not create duplicate resources. Track only resources owned by this installer; never clean up arbitrary existing resources.

Do not promise transactional rollback across IRIS and the filesystem. Preserve completed safe steps, record partial/unknown state, and show the recovery action. If an existing binary is in use or needs replacement, stop with a maintenance instruction rather than overwriting it or restarting IRIS automatically.

Provide Switch instance, Sign out, and Forget saved login as distinct actions. Switching re-enters the authentication gate; signing out ends the current authenticated context; forgetting removes the saved credential reference and secret without removing the installation.

## 7. Repository facts to account for

- `src/objectscript/IRISConfig/Installer.cls` is a Docker/demo installer with fixed paths, demo credentials, and password-policy changes. Keep it separate.
- `src/objectscript/OPCUA/Utils.cls` exposes library path registration, initialization, and version retrieval.
- `src/objectscript/OPCUA/REST/Handler.cls` supplies `/ping`; it does not perform comprehensive readiness checks.
- Native artifacts live in `bin/unix/{amd64,arm64}/` and `bin/windows/`; Windows notes explicitly flag potential source/binary mismatch.
- The existing frontend already has IRIS API settings and OPC UA server setup. No duplicate CLI feature is needed.
- Pipeline startup currently can stop another production in the namespace. Dedicated namespace isolation is required; changing pipeline behavior is a separate product task.
- Current browser credential storage remains a separate frontend/backend concern. This installer must not spread or duplicate that storage approach.

## 8. Implementation sequence

1. Prove instance discovery, real credential authentication, secure credential persistence/fallback, and structured ObjectScript execution on a clean supported IRIS instance. Resolve bootstrap limitations before polishing the UI.
2. Implement read-only inspection and a parameterized client installer with explicit result reporting and repeatable steps. Establish compatible artifacts and required permissions.
3. Add the linear UI, review screen, progress, failure recovery, and secure saved-login flow.
4. Add backend verification, optional HTTP verification, and non-secret webapp handoff. Keep frontend and OPC UA setup out of scope.
5. Exercise the acceptance scenarios below, document supported versions/platforms, and update the root README with tested CLI commands while retaining the manual installation path.

Do not mark a platform supported because source code contains a branch for it. Do not add speculative installer features to the README before they work.

## 9. Acceptance scenarios

Use meaningful automated tests for state transitions, command/data handling, redaction, idempotency, and failure recovery, plus an actual disposable IRIS integration environment. Mocked subprocess results alone do not establish a working installer.

- Fresh instance with no OPC UA classes/API: select instance, authenticate, install, load library, and verify REST response.
- Wrong password: no protected operation occurs; retry works; secret never appears in output or logs.
- Local OS account has IRIS access: an incorrect supplied IRIS password still fails the required authentication gate.
- Relaunch: saved login validates without prompting; expired/changed credential returns to login without losing setup choices.
- No secure credential store: session-only operation works and no password file is created.
- Two local instances: select/switch correctly; credentials and installer state never cross targets.
- Insufficient OS or IRIS privileges: actionable preflight failure before application changes, with no silent privilege grant.
- Existing unrelated namespace/production or API path: refuse the conflict without altering it.
- Missing dependency or incompatible architecture/library: fail before installation; show the detected mismatch and repair instruction.
- Compile failure or interrupted installation: no false success; rerun inspects state and resumes without duplicate resources or data loss.
- Healthy existing install: verification is read-only; rerun preserves user schemas, database contents, settings, and account policies.
- Backend installed but gateway unreachable: report partial readiness accurately and allow later verification.
- Narrow terminal, no color, redirected output, and Ctrl+C: readable output, no secret leakage or traceback-only failure, safe recovery.
- Completed handoff: user receives the API connection information and continues in the webapp; the CLI never asks for an OPC UA endpoint or starts a production.

Deliver the CLI, client ObjectScript installer, tests, verified compatibility notes, and concise installation documentation. Include the actual integration-test evidence and any remaining platform limitations in the implementation handoff.
