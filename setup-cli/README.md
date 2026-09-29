# iris-opcua-setup

A terminal installer for the IRIS OPC UA backend. It connects to an existing IRIS instance over the built-in Atelier REST API (`/api/atelier`), installs the native connector, namespace, ObjectScript classes, and REST application, verifies them, and then hands off to the webapp. OPC UA servers, certificates, schemas, and pipelines are configured in the webapp, not here.

It needs no access to the IRIS host beyond its web server, so it can run on the server or on your own machine.

## Build

Rust 1.89 or later:

```bash
cd setup-cli
cargo build --release          # → target/release/iris-opcua-setup
cargo test                     # unit tests (no IRIS needed)
```

## Run

```bash
./target/release/iris-opcua-setup
```

The tool finds the payload (`src/objectscript/` and `bin/`) in the repository checkout that contains it. If you copy the binary elsewhere, pass the checkout path: `iris-opcua-setup --dist /path/to/iris-opcua`.

It is interactive and needs a terminal. Each step fills the terminal window as its own screen: move with ↑/↓ and press Enter, or press an item's number or letter directly. Esc goes back and Ctrl+C quits. With redirected output or `TERM=dumb`, the screens are printed one after another and you type the key instead.

You define a connection with:

- a **name**,
- a **base URL**: `http(s)://host(:port)/pathPrefix`, or just a host name, in which case you are asked for the scheme. If you leave out the port, you get a warning and the URL is used exactly as typed. No port is assumed.
- a **username** and **password**.

## What the IRIS account needs

| Privilege | Used for |
|---|---|
| `%Development:USE` | Atelier API: uploading and compiling code |
| `%Admin_Manage:USE` | Creating the namespace and database |
| `%Admin_Secure:USE` | Creating the REST application, its resource and role |
| `%DB_IRISSYS:WRITE` | Loading the installer class `IRISConfig.ClientInstaller` into `%SYS` |
| RW on the namespace database resource | Importing classes into the namespace |

The last row is only automatic for accounts with the `%All` role. IRIS does not give an administrator access to a database they create. For another account, have an administrator create the resource `%DB_<NAMESPACE>` (for example `%DB_OPCUA`) and grant it RW through a role *before* installing. The preflight check tells you if this is missing. The tool never grants privileges.

## What it changes on the IRIS server

- **Native libraries:** `irisopcua.so`, `libopen62541.so.0`, and `libcrypto.so.1.1` go into the IRIS `bin` directory.
  - They are uploaded to a staging file, checked against their SHA-256, and then moved into place.
  - An identical existing file is reused. A different existing file is never overwritten, and the install stops.
  - An existing crypto library is always kept.
  - If IRIS cannot write its `bin` directory, nothing is changed. The tool prints the exact files, their hashes, and their destinations for a server administrator to copy by hand, then verifies them on Retry.
- **Namespace:** the namespace (default `OPCUA`) and its database are created in the manager directory, with interoperability enabled.
  - This uses the `Security.Resources`, `SYS.Database`, `Config.*`, and `%EnsembleMgr` APIs, not `%Installer`, whose manifest needs `%All`.
  - An existing namespace is reused only if it is empty, was created by this tool, or already holds the OPC UA backend. A namespace with other classes or another production is refused.
- **ObjectScript:** `OPCUA/Constants.inc` and the `OPCUA` classes are uploaded. `Tests/`, `Examples/`, and `IRISConfig/` are left out.
- **REST application** (default `/csp/opcua/api`):
  - It uses password authentication and dispatches to `OPCUA.REST.Handler`.
  - It requires the resource `OPCUA_API`.
  - The role `OPCUA_API_<NAMESPACE>` grants `OPCUA_API:USE` plus RW on the namespace database. It is created but assigned to nobody: **grant it to the accounts that use the webapp.**
  - An existing application with the same path is reused only if it serves the same namespace with the same dispatch class. Its settings are never changed.
- **Ownership record:** `^IRISConfig.ClientInstaller` in `%SYS` records what the tool created, so reruns can reuse its own resources and never adopt foreign ones.

Reruns are safe. Each step inspects the server first and reuses what is already correct, so an interrupted or failed installation resumes without creating anything twice.

## Local files

Everything lives in `setup-cli/local/`, which is git-ignored. When you run a binary outside the checkout, it uses `local/` next to that binary.

| File | Contents |
|---|---|
| `connections.json` | Connection definitions, recorded instance identity, setup choices and progress. **Passwords are stored here in plain text** if you choose to remember them. |
| `setup.log` | Step log. Passwords are redacted. |
| `<name>-summary.txt` | Optional non-secret export for the webapp handoff. |
| `<name>.lock` | OS lock that prevents two installations of one connection at the same time. |

On Linux and macOS the folder is created with mode 0700 and the files with mode 0600. On Windows they inherit the folder's permissions.

A remembered password is only used for the URL, user, and IRIS instance (instance GUID) it was saved with. If the URL starts reaching a different instance, the tool refuses to continue.

## Limitations

- **Server platforms:** Linux x86-64 and ARM64 only. Windows and macOS IRIS servers are detected and refused. The CLI itself builds for Linux, macOS, and Windows.
- **TLS:** only certificates from public CAs (the bundled Mozilla roots) are trusted. An IRIS web server whose certificate comes from an internal CA fails with a TLS error.
- **Atelier API:** it must be enabled and routed by the web server. Its 401 cannot tell a wrong password from an account without `%Development`.
- **Upgrades:** a native library that differs from the supplied one is never replaced automatically.

Tested against InterSystems IRIS Community 2025.3 (Linux ARM64 container); see `docs/terminal-installer-plan.md` §10 for the evidence and what remains unverified.
