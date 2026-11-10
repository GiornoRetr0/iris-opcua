# Automated OPC UA Sign & Encrypt setup

**Date:** 2026-11-10 · **Repos:** `iris-opcua` (ObjectScript, console, docs) and the
local connector repo `cpp-build/` (C++, no remote) · **Prior art:** branch
`feature/sign-encrypt` (commit `ffd4121`, backend only, 109 commits behind `main`,
old `src/objectscript/` layout) and the mockup `docs/notes/opcua-security-ux.html`.

## Why

Sign & Encrypt works today only for someone who generates DER files with OpenSSL,
copies them onto the IRIS server and types a Client URI and four paths into every
server profile and pipeline. Any of those steps can go wrong silently, and the
failure is a bare `BadSecurityChecksFailed` that doesn't say which side has to act.
Our SuperUsers run IRIS on **Windows and Linux** and should be able to secure a
connection from the console without opening a shell.

Success: a SuperUser opens the console, creates (or imports) the instance's client
identity once, then for each server picks *Sign & Encrypt*, reviews and trusts the
server certificate, gets the server administrator to approve IRIS's certificate,
and sees a passing secure test. Pipelines deployed for that server use the same
setup with no certificate settings of their own.

## Goals

1. **One default client identity per IRIS instance** (the user's decision): a
   certificate, its private key and a Client URI. All namespaces share it, so a
   server administrator approves an IRIS instance once.
2. Create an identity, import an existing certificate/key pair, or point at
   existing files on the IRIS server. Detect and validate a configured identity
   before generating anything.
3. Validate every identity: the key matches the certificate, the certificate is
   valid now (expiry checked), and it carries the Client URI.
4. Replace an identity only after explicit confirmation that names the affected
   pipelines (across all namespaces) and trusted servers.
5. Fetch a server's certificate for review (subject, application URI, issuer,
   validity, SHA-256 fingerprint). Trust it only after explicit confirmation of
   that fingerprint.
6. Download the public client certificate (DER and PEM) for approval on the server.
7. Node Explorer (all console REST calls) and pipelines (business services) use the
   default identity automatically in Sign & Encrypt mode.
8. Actionable errors, above all "the OPC UA server has not approved IRIS's
   certificate yet", with our fingerprint and the download.

## Non-goals

- Changing IRIS console sign-in (JWT / Basic) in any way.
- Changing username/password authentication or anonymous sessions. Security mode
  and user identity stay independent settings.
- `Sign` (without encrypt) mode: the native layer refuses it today and that stays.
- Approving IRIS on the OPC UA server. We can't, and must say so plainly.
- Automatic renewal of an expiring identity. We warn; a person replaces it.
- Testing on Windows. The DLL is built here; running it is the user's separate pass.

## Anti-goals (would be failure even if it "works")

- **Silently trusting a server.** Includes the open62541 1.2.1 trap: an **empty
  trust list installs an allow-all verifier** (`ua_pki_openssl.c:695-698`).
  Managed Sign & Encrypt with nothing trusted for that server must refuse to
  connect and say why, never connect.
- **Falling back to an unencrypted connection** when the secure one fails.
- A private key leaving IRIS: not in a REST response, an event log entry, an error
  message, the native library log, or an exported global.
- Breaking existing manual setups: pipelines and server profiles with explicit
  `PublicCertificate` / `PrivateKey` / `TrustListDir` / `RevocationListDir` /
  `ClientURI` keep working exactly as now, including the demo `SecureExample`.
- Shelling out to `/bin/sh` or an `openssl` executable for anything the product
  does at runtime (it won't exist on Windows). Tests may use the container's
  `openssl` to make fixtures.

## What the native connector can do today (verified)

- `zfSetupClientC` (39): DER certificate + DER key + trust directory + CRL directory
  + ClientURI. Every regular non-dot file in the trust/CRL directories is loaded
  (the multi-file bug is fixed in the shipped build). `UAC_ENABLE_SECURITY` is on.
- `zfGetEndpoints` (47): discovery with no trust in either direction; returns each
  endpoint's mode, policy URI and security level, plus the server certificate as
  hex. **Present in the shipped Linux amd64/arm64 and Windows binaries** but not
  yet declared in `Constants.inc` or called from ObjectScript on `main`. After the
  call the client must be set up again (`setResetRequired`).
- open62541 1.2.1 verifies a non-empty trust list with OpenSSL chain verification.
  A self-signed server certificate in the list is its own anchor. A CA-signed one
  needs the issuer **and the issuer's CRL** in the lists (otherwise
  `BadCertificateIssuerRevocationUnknown`).
- IRIS 2025.3 natively has `X509GetField`, `X509VerifyCertChain`, `SHAHash` and RSA
  sign/verify, but **no way to create a certificate** with OPC UA's required
  extensions (the `PKI.*` classes issue only through an IRIS CA). Embedded Python
  `cryptography` exists in the Linux container only via the OS package.

## Decisions

### Certificate operations move into the connector (user approved the rebuild)

Add to the C++ connector (version **0.5.0**), using the OpenSSL 1.1 libcrypto that
already ships beside it on every platform:

- **Create identity:** RSA 2048 key; self-signed X.509 v3 certificate with
  subjectAltName `URI:<ClientURI>` + `DNS:<hostname>`, basicConstraints CA:FALSE,
  keyUsage digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment,
  extendedKeyUsage clientAuth + serverAuth, SHA-256 signature. Copy the extension
  set from `demo/certgen/secuac.config`, which the certified server already
  accepts. Writes key and certificate as DER. The generated certificate also
  carries keyUsage `keyCertSign`: open62541 1.2.1's verifier requires it for a
  trusted self-signed certificate (verified in connector 0e03174).
- **Inspect certificate:** subject, issuer, notBefore/notAfter, SAN URIs and DNS
  names, SHA-256 fingerprint, self-signed?, CA?, key type and bits.
- **Check pair:** does this key belong to this certificate.
- **Normalise for import:** certificate PEM/DER, key PEM (PKCS#1/PKCS#8, optionally
  passphrase-protected) or DER, and **PKCS#12 (.pfx/.p12) with password** (the usual
  Windows export), CRL PEM/DER → DER files.

ObjectScript gates on the library minor version (`OPCUA.Utils.Supports...`), as the
prior branch did for discovery: calling an ordinal an older build lacks is not a
clean failure. Rebuild `linux-amd64`, `linux-arm64` and `windows-x64` with the
scripts in `cpp-build/opc-ua-master/docker/`, commit the sources in `cpp-build`
and the binaries in `iris-opcua/backend/native/`. The exact ordinals and argument
shapes are the builder's call; byte payloads cross the callin boundary as hex, as
`zfGetEndpoints` does.

### Storage (per instance)

- Files under `<manager directory>/opcua-pki/` (`$System.Util.ManagerDirectory()`,
  which is instance-wide on both platforms): `own/` (generated or imported identity),
  `servers/<server-key>/trusted/` and `servers/<server-key>/crl/` per server.
- Configuration in an instance-wide global in IRISSYS (`^%OPCUA.Security`, *my
  call*; the builder confirms it is visible and writable from every namespace with
  SuperUser rights): identity source (`generated` / `imported` / `files`), cert and
  key paths, Client URI, fingerprint, created/replaced timestamps, and one entry per
  trusted server (URL, key, fingerprints, label, trusted-at, by whom).
- The root is overridable (a global node) so tests never touch the real identity.
- Key file permissions: directory 0700 and key 0600 for the IRIS OS user on Linux.
  On Windows the key inherits the manager directory's ACL (IRIS service account
  and Administrators); this is **unverified** and goes on the Windows checklist.
- "Use existing files on IRIS" **references the files in place** (*my call*, so a
  site whose tooling renews them stays in control), validates them when selected,
  and re-validates on every status read. "Import" copies into `own/`.
- Demo docker: add a named volume for `opcua-pki` so rebuilding the image doesn't
  regenerate the identity (and force every server to approve it again).

### Client URI

Default `urn:<hostname>:InterSystems:IRIS:<instance>:OPCUA`, lowercased and
restricted to `[A-Za-z0-9:._-]`. Editable under Advanced before creating. For an
imported or existing certificate, the URI is taken from its SAN; a certificate
without a SAN URI is rejected (OPC UA requires it). Several URIs: first one,
shown under Advanced.

### Validation rules (identity)

Not ready (blocking): unreadable files, unparseable certificate, key doesn't match,
not yet valid, expired, no SAN URI, non-RSA key (open62541 1.2.1 policies are RSA
only). Warning (usable): expires within 30 days, key below 2048 bits, missing
keyUsage bits. Every rule has its own message.

### Detection before generation

`GET` status reports the configured identity and its validation. With none
configured it also reports **candidates**: the demo/legacy files at
`/usr/irissys/uac/certs/secuac.*` if present (and valid). It offers them but
never adopts them automatically. Create, import and use-files all refuse to run
over a configured identity unless `replace` is confirmed.

### Replacement confirmation

The status response carries an `impact` list: every pipeline in every namespace
that has the adapter installed, whose security mode is 3 and which has no manual
certificate paths (i.e. uses the default identity), plus every trusted server.
Replacing requires `replace: true` **and** the current identity's fingerprint, so a
confirmation given against a stale screen can't replace a different identity. The
UI states: each listed server must approve the new certificate before those
connections work again. The old identity's files are kept in `own/previous/`
(*my call*) so a mistaken replacement can be rolled back by hand.

### Trusting a server

- **Inspect** (`url`): discovery via `zfGetEndpoints`. Returns certificate details,
  whether the server offers a SignAndEncrypt endpoint at all, whether it is already
  trusted, and whether it is self-signed.
- **Trust** (`url`, `fingerprint`): IRIS **fetches the certificate again itself**
  and stores it only if its fingerprint equals the confirmed one. Bytes from the
  browser are never trusted.
- **CA-signed server:** trusting the presented certificate is not enough. The
  response names the issuer; the user supplies that CA certificate and its CRL
  (file upload or paste), IRIS verifies the server certificate chains to it, then
  stores both. This is the case for the demo `certified-server` (issued by `myCA`).
- Trust is **per server**, keyed by the normalised endpoint URL (lowercase host,
  explicit port, no trailing slash). Trusting server A never makes A's certificate
  acceptable for server B. A different URL for the same server (IP vs hostname)
  needs trusting again, and the UI says so.
- Removing trust is available per server (Advanced).

### Pinning (user's decision)

Each managed server connection is **pinned to the exact certificate the user
reviewed**, self-signed or CA-signed. Normal validation stays in force on top of the
pin: chain to a trusted anchor, CRL for CA-issued certificates, validity period
(expiry), and endpoint identity. The pin is an extra condition, never a substitute.

- The connector (0.5.0) takes the pinned SHA-256 fingerprint(s) for the connection
  and wraps open62541's `verifyCertificate`: run the normal verification first,
  then compare the presented certificate's fingerprint. Anything else fails the
  secure channel.
- **Endpoint identity:** the presented certificate's SAN URI must equal the
  server's `applicationUri` from discovery, and the URL's host must appear in its
  SAN DNS names or IP addresses. A mismatch refuses the connection and names what
  was expected and what the certificate says. (`zfGetEndpoints` is extended to
  return the server's `applicationUri`.)
- **A changed certificate** (still valid, maybe from the same CA) refuses the
  connection with exactly: **"Server certificate changed—review and approve the
  replacement."** The console then shows the old and new certificates side by side
  and re-runs the review/confirm step. Nothing is ever approved automatically, and
  there is no insecure fallback.
- Pipelines use the same pin; a changed certificate makes the adapter log that
  message and retry on its normal schedule without connecting.
- Trusting a CA (issuer + CRL) is still required for a CA-signed server, but on its
  own it never admits a certificate that isn't pinned.

### Using the setup (managed vs manual)

A connection is **managed** when security mode is 3 and none of `certPath` /
`keyPath` (REST) or `PublicCertificate` / `PrivateKey` (adapter settings) is set.
Managed connections take the default identity and that server's trust and CRL
directories. **Manual** connections are exactly today's behaviour, untouched. Mode 1
ignores all of this.

Managed checks before connecting, each with its own error: no identity, identity
invalid/expired, server not trusted (empty trust list → refuse). No fallback to
mode 1 anywhere.

This one resolution is shared by `ClientManager` (Node Explorer, read, test,
schema validate) and `OPCUA.Adapter.Common` (both polling and subscription
adapters, row-source and declarative). Deploying a managed profile writes only
`SecurityMode=3` to the pipeline, so it follows the default identity.

### Diagnosing failures

After a failed secure connect, run discovery (no trust) and classify:

| Result | Message direction |
|---|---|
| unreachable / timeout | network: check URL, port, firewall |
| no SignAndEncrypt endpoint offered | server doesn't offer Sign & Encrypt with a supported policy |
| server never trusted | IRIS doesn't trust this server yet; review its certificate |
| server presents a different certificate than the pinned one | "Server certificate changed—review and approve the replacement." (show old and new) |
| endpoint identity mismatch (applicationUri or host not in SAN) | name the expected value and what the certificate says |
| CA-signed and issuer/CRL missing | add the issuer CA and its CRL |
| our certificate trusted side is fine, server rejects (`BadSecurityChecksFailed`, `BadCertificateUntrusted`, …) | **the server must approve IRIS's certificate**: our fingerprint, download link, "approve it in the server's trusted/rejected certificate list, then test again" |
| `BadCertificateUriInvalid` | Client URI doesn't match the certificate |
| `BadCertificateTimeInvalid` | a certificate is expired or clocks differ |

The adapter logs the same text to the event log on connect failure.

### REST (`/security`, real verbs; SuperUser only)

| Endpoint | Purpose |
|---|---|
| `GET /security/identity` | status, details, validation, candidates, impact (never the key) |
| `POST /security/identity` | create (`clientURI` optional, `replace`, `currentFingerprint`) |
| `POST /security/identity/import` | certificate + key, or PKCS#12 + password (+ replace fields) |
| `POST /security/identity/files` | use existing cert/key paths on IRIS (+ replace fields) |
| `GET /security/identity/certificate?format=der\|pem` | download the public certificate |
| `GET /security/servers` | trusted servers with expiry |
| `POST /security/servers/inspect` | fetch a server certificate for review |
| `POST /security/servers/trust` | trust after fingerprint confirmation |
| `POST /security/servers/issuer` | add issuer CA + CRL for a CA-signed server |
| `DELETE /security/servers/:key` | stop trusting a server |
| `POST /test` (existing) | managed mode adds a readiness block and the diagnosis category |

Authorisation: require `%Admin_Secure:USE` (*my call*). An `OPCUA_API_<NS>`-only
account gets 403 on `/security`, consistent with it not managing credentials, and
**managed Sign & Encrypt is out of its reach** like credentialed servers are (*my
call*): no privilege escalation path to the identity. Its console shows the
readiness rows as "needs a SuperUser" on a 403 instead of failing; `ApiRoleTest`
gets a case for it. Production jobs are unaffected (they run as the production's
user and read the configuration and files directly).
Passwords for PKCS#12 / key passphrases are used for the one request and dropped.

### Console

- **OPC UA Security** tab in the settings modal between *OPC UA Servers* and *IRIS
  API Gateway*, following the mockup. Shows: no identity (create / use existing
  pair / candidate found), or the identity's Client URI, fingerprint, expiry
  (warning colour within 30 days, error when expired), source, *Download
  certificate (DER/PEM)*, *Replace…* with the impact list and confirmation.
  **Advanced** (collapsed): Client URI editor (before create), file paths, the
  "use existing files on IRIS" form, trusted servers list with remove, store path.
- Import: file pickers for certificate + key, or one PKCS#12 + password. When the
  API URL is plain `http` to a non-localhost host, warn that the key would cross the
  network unencrypted and suggest "use existing files on IRIS" (*my call*).
- **Server form, Sign & Encrypt selected:** the five certificate inputs go away.
  Instead three readiness rows:
  1. *IRIS client identity:* Ready, or missing / expired → **Set up identity**
     (opens the Security tab with a *Return to <server>* link).
  2. *Server certificate:* Trusted, or **Review certificate** → inline panel with
     subject, issuer, expiry, full fingerprint and the instruction to compare it with
     what the server owner provides → **Trust this server**. CA-signed: the issuer +
     CRL step inline.
  3. *Server approval of IRIS:* "Checked when you test the connection." After a
     test: approved, or the actionable message with *Download certificate* and the
     approval explanation.
  Then *Test connection* reports Sign & Encrypt explicitly when it passes.
- Existing profiles with manual paths keep them; their form shows "Manual
  certificate files" under Advanced (still editable), and readiness rows reflect
  manual mode. New profiles never get paths filled in (remove the `onSecurityModeChange`
  defaults to `/usr/irissys/uac/certs/...`).
- Signals rule from CLAUDE.md applies to any field feeding a `computed` gate.
- Documentation page: replace the certificate-paths section with the new flow.

### Installer and mixed versions (*my call*)

The installer is in scope: it embeds the rebuilt 0.5.0 binaries, its version goes
to 0.5.0, and `CHANGELOG.md` says so. It doesn't create `opcua-pki/`; IRIS creates
it on first use with the right permissions. The new ordinals are additions, so
namespaces still on older ObjectScript keep working with the 0.5.0 library and
their manual pipelines are unaffected; managed pipelines can only be created by
upgraded code. No forced upgrade of every namespace.

## Testing

- **Offline (`OPCUA.Tests.Unit`, no native library):** URL normalisation / server
  key, Client URI allowlist and default, managed-vs-manual resolution for REST
  bodies and adapter settings, empty-trust refusal, replacement guard (missing or
  stale fingerprint rejected), diagnosis classification from status codes +
  discovery results, impact listing against a throwaway production, `/security`
  responses never containing key material.
- **Live (`OPCUA.Tests.Live`, native library, test PKI root):** create → reuse for
  two connects without regenerating; import PEM pair, DER pair, PKCS#12; key that
  doesn't match rejected; expired and not-yet-valid certificates rejected (fixtures
  made with the container's `openssl`); no-SAN-URI rejected; use-existing-files
  with the demo `secuac` files; trust fingerprint mismatch refused; pinned certificate swapped for another valid one from the same CA refused with the "changed" message; expired server certificate refused even though pinned; host/applicationUri mismatch refused; CA-signed
  `certified-server` requires issuer + CRL; connect before approval is diagnosed as
  "server must approve IRIS"; after approval the managed REST test and a managed
  pipeline both pass. Live tests run inside IRIS and can't drive docker, so the
  approval case is a **host script** (*my call*, e.g. `demo/iris/secure-e2e.sh`):
  reset `certified-server`'s trust folder to its image contents, run the
  pre-approval Live phase, `docker cp` our certificate into the folder (the IRIS
  stack itself never writes there: approval must stay external), run the
  post-approval phase. Runner gets a way to run one test class/method so the
  script can call each phase; unreachable URL diagnosed as network;
  mode 1 and username/password paths unchanged; `SecuredPipelineTest`,
  `PollingExample` / `SubscriptionExample` regression gate still pass.
- Webapp: `npx tsc --noEmit`, `npx ng build`, and a browser run of the full flow
  against the docker stack.
- **Not verifiable here, reported as such:** the Windows DLL at runtime, Windows key
  file ACLs, IRIS on Windows paths, servers other than the demo ones.

## Left to the builder

Ordinal numbers and argument layouts; class/method names and file split
(`OPCUA.Security.*` suggested); how much of `ffd4121` to port vs rewrite;
console component structure; exact copy text (plain, actionable, matching the
console's existing tone); the fixture-generation details; doc updates
(`CLAUDE.md` ×2, `docs/architecture.md`, `CHANGELOG.md`) to describe the new
model and the empty-trust-list rule.
