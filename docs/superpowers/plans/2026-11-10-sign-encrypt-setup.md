# Automated OPC UA Sign & Encrypt Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One managed, per-instance IRIS OPC UA client identity plus per-server pinned trust, used automatically by Node Explorer and pipelines in Sign & Encrypt mode, configured from a new console tab.

**Architecture:** Certificate creation, inspection, key-pair checks, import normalisation and server-certificate pinning move into the C++ connector (0.5.0, OpenSSL 1.1 libcrypto already shipped). ObjectScript `OPCUA.Security.*` owns the store (files under `<mgr>/opcua-pki/`, config in `^%OPCUA.Security`), trust decisions, managed-vs-manual resolution and failure diagnosis; `ClientManager` and `Adapter.Common` both go through one resolver. The console gets an *OPC UA Security* tab and readiness rows in the server form.

**Tech Stack:** C++ (open62541 1.2.1, OpenSSL 1.1), InterSystems IRIS 2025.3 ObjectScript + `%UnitTest`, Angular 19 (standalone, signals, Tailwind), Docker.

**Spec:** `docs/superpowers/specs/2026-11-10-sign-encrypt-setup-design.md` — read it before any task.

## Global Constraints

- Identity is **per IRIS instance**, shared by every namespace.
- Never trust a server silently. Managed Sign & Encrypt with an empty trust list, no pin, or a missing issuer/CRL **refuses before calling the native setup**.
- Never fall back to SecurityMode 1 on any failure.
- No private key bytes in any REST response, event log, error text, native log, or exported global. Key passphrases / PKCS#12 passwords live only for the request.
- Manual connections (`certPath`/`keyPath` set, or adapter `PublicCertificate`/`PrivateKey` set) behave exactly as today.
- No runtime use of `/bin/sh` or an `openssl` executable. Tests may use the container's `openssl` for fixtures.
- Changed pinned certificate message, verbatim: `Server certificate changed—review and approve the replacement.`
- Generated identity: RSA 2048, SHA-256, 3650 days, extensions copied from `demo/certgen/secuac.config`; SAN `URI:<ClientURI>` + `DNS:<hostname>`. The self-signed identity also carries keyUsage `keyCertSign`, because open62541 1.2.1's verifier requires it for trusted self-signed certificates (verified in connector 0e03174).
- Default Client URI: `urn:<hostname>:InterSystems:IRIS:<instance>:OPCUA`, lowercased, allowlist `^[a-z0-9:._-]+$`.
- Expiry warning threshold: 30 days.
- `/security/*` requires `%Admin_Secure:USE`; otherwise 403.
- Native ordinals are **appended** after 47 in `zfCallin.cpp`; never inserted.
- Connector version 0.5.0; installer version 0.5.0.
- CLAUDE.md gotchas apply: no `$Get(obj.prop)`; `SETTINGS` stays one line; signals for any field feeding a `computed`.
- Commit connector work in `/Users/fijnhaar/Documents/Work/OPCUA/cpp-build` (repo root there), everything else in `iris-opcua`, on a feature branch `feat/sign-encrypt-setup` in each.

## Review Focus

1. **Server reached by a different URL form** (`opc.tcp://Certified-Server:4840/` vs `opc.tcp://certified-server`) — must map to the same pin; tested in Task 4 (`TestNormaliseURL`).
2. **Pinned certificate expired** — must refuse even though the fingerprint matches; tested in Task 2 self-test (`expired_pinned_rejected`) and Task 9 E2E.
3. **Identity files deleted or replaced on disk after "use existing files"** — status must turn not-ready with `unreadable`/`keyMismatch`, managed connects refuse; tested in Task 5 (`TestUseFilesThenDeleted`).
4. **Upload of a passphrase-protected PEM key without the passphrase / wrong PKCS#12 password** — clear 400 naming the password, no partial files left in `own/`; tested in Task 3 (`TestImportWrongPassword`).
5. **Replacement confirmed against a stale screen** (identity replaced in another tab) — 409, nothing written; tested in Task 5 (`TestReplaceStaleFingerprint`).

---

## Part A — Connector (repo: `cpp-build`)

### Task 1: Native PKI operations

**Files:**
- Create: `opc-ua-master/IrisOPCUA/UACPki.h`, `opc-ua-master/IrisOPCUA/UACPki.cpp`
- Create: `opc-ua-master/docker/pki-selftest.cpp`, `opc-ua-master/docker/run-selftest.sh`
- Modify: `opc-ua-master/IrisOPCUA/IrisOPCUA.h`, `IrisOPCUA.cpp`, `zfCallin.cpp` (append ordinals 48–51), `OpcuaClient.cpp` (version 0.5.0)
- Modify: `opc-ua-master/IrisOPCUA/IrisOPCUA.mak` (link `-lcrypto`), `docker/build-win64.sh` (OpenSSL 1.1.1 headers + import lib generated from the shipped `libcrypto-1_1-x64.dll` with `gendef`/`llvm-dlltool`), `docker/Dockerfile.linux-*` (already have `libssl-dev` 1.1.1 on Ubuntu 20.04; confirm)

**Interfaces (all `"Bb"` entries; input `$LB`, output via `UAC_MakeReturnValue`, bytes as uppercase hex):**
- Produces ordinal **48** `zfPkiCreateIdentity` in `$LB(certPath, keyPath, clientURI, hostname, commonName, days, keyBits)` → `$LB(0, status)`; writes DER cert and DER PKCS#8 key; key file created with mode 0600 on non-Windows, written to a temp name then renamed.
- Produces ordinal **49** `zfPkiInspectCert` in `$LB(source, isPath)` (source = path or hex DER/PEM) → `$LB(0, status, subject, issuer, notBeforeUTC, notAfterUTC, $LB(sanUris…), $LB(sanDns…), $LB(sanIps…), sha256, selfSigned, isCA, keyType, keyBits, $LB(keyUsage…), derHex)`; timestamps `YYYY-MM-DD HH:MM:SS`; sha256 `AA:BB:…` uppercase.
- Produces ordinal **50** `zfPkiCheckKeyPair` in `$LB(certPath, keyPath)` → `$LB(0, status, match)`.
- Produces ordinal **51** `zfPkiNormalise` in `$LB(kind, dataHex, password, outCertPath, outKeyPath)` where kind ∈ `cert|key|p12|crl`; writes DER (key → PKCS#8 DER 0600, p12 → both cert and key); wrong/missing password → app error text `The password for the key or PKCS#12 file is wrong or missing.`; unparsable → `The file is not a certificate/key/CRL in PEM, DER or PKCS#12 form.`
- Error texts never contain key bytes.

- [ ] **Step 1: Write the self-test** `pki-selftest.cpp` calling the four functions through `UACPki.h` (plain C++ API: `UACPki::createIdentity(...)`, `inspect(...)`, `checkKeyPair(...)`, `normalise(...)`, each returning `UACErr`). Cases: `create_then_inspect` (SAN URI == input, keyBits 2048, notAfter−notBefore ≈ 3650 d, selfSigned, !isCA), `pair_matches`, `pair_mismatch` (two identities crossed → false), `normalise_pem_cert_roundtrip` (fingerprint equal to DER original), `normalise_encrypted_key_wrong_password` (error text above), `normalise_p12` (fixture made with `openssl pkcs12 -export` in the script), `key_mode_0600`.
- [ ] **Step 2: Run** `docker run --rm -v "$PWD:/src" irisopcua-build-arm64 /src/opc-ua-master/docker/run-selftest.sh` from `cpp-build` — Expected: compile failure (UACPki.h missing).
- [ ] **Step 3: Implement `UACPki.cpp`** with OpenSSL 1.1 APIs (`EVP_PKEY_keygen` RSA, `X509V3_EXT_conf_nid` for extensions, `X509_sign(EVP_sha256)`, `X509_digest(EVP_sha256)`, `X509_check_private_key`, `PEM_read_bio_*`/`d2i_*`, `d2i_PKCS12_bio` + `PKCS12_parse`). Wire the zf entries (append 48–51 after 47 with the existing comment convention), bump `UAC_version_minor` to 5 with a comment line naming the new ordinals.
- [ ] **Step 4: Run self-test** — Expected: `ALL PKI SELFTESTS PASSED`.
- [ ] **Step 5: Commit** (cpp-build) `feat(pki): create, inspect, pair-check and import certificates natively`.

### Task 2: Server certificate pinning and discovery application URI

**Files:**
- Create: `opc-ua-master/IrisOPCUA/UACPin.h`, `UACPin.cpp`
- Modify: `OpcuaClient.h/.cpp` (store pins; install wrapper after `setupWithEncryption`; `getEndpoints` appends server `applicationUri` as list element 6), `OpcuaStatic.cpp/.h`, `IrisOPCUA.cpp/.h`, `zfCallin.cpp` (append **52** `zfSetServerPin`)
- Modify: `docker/pki-selftest.cpp`

**Interfaces:**
- Produces ordinal **52** `zfSetServerPin` in `$LB(handle, $LB(fp…), host)` → `$LB(0, status)`. Must be called after `zfSetupClientC` (mode 3) and before connect; an empty fp list is an app error `No pinned server certificate.`.
- Wrapper: replace `config->certificateVerification` with a context struct `{inner CertificateVerification copy, pins, host}`; `verifyCertificate` = inner verify first (chain, CRL, validity), then SHA-256 compare against pins (`BADCERTIFICATEUNTRUSTED` on mismatch), then `X509_check_host`/`X509_check_ip_asc` on `host` (`BADCERTIFICATEHOSTNAMEINVALID`); `verifyApplicationURI` and `clear` delegate to the inner one.
- `zfGetEndpoints` return gains `[6] applicationUri` of the first endpoint's server description.

- [ ] **Step 1: Self-test cases** using a pure function `UACPin::check(const UA_ByteString& cert, pins, host)` (the part after inner verification): `pin_match_ok`, `pin_mismatch_untrusted`, `host_dns_ok`, `host_mismatch_hostnameinvalid`, `ip_host_ok`; plus `expired_pinned_rejected` running the full wrapper over an inner `UA_CertificateVerification_Trustlist` holding an expired self-signed fixture → not GOOD.
- [ ] **Step 2: Run** — Expected: fail to compile.
- [ ] **Step 3: Implement** wrapper + ordinal 52 + applicationUri.
- [ ] **Step 4: Run self-test** — PASS.
- [ ] **Step 5: Build all three platforms** with the existing scripts (`build-amd64.sh` under `--platform=linux/amd64`, `build-arm64.sh`, `build-win64.sh`); copy `irisopcua.so` ×2 and `IrisOPCUA.dll` into `iris-opcua/backend/native/{linux-amd64,linux-arm64,windows-x64}/`. Check `strings` shows `zfSetServerPin` in all three and `llvm-objdump -p IrisOPCUA.dll | grep -i libcrypto-1_1-x64.dll` lists the dependency. Update `windows-x64/README.md` (0.5.0, links libcrypto).
- [ ] **Step 6: Rebuild the IRIS image** `docker compose build iris && docker compose up -d iris`; in OPCUA run `do ##class(OPCUA.Utils).GetVersion(.v) w $LTS(v)` — Expected contains `0.5.0`.
- [ ] **Step 7: Commit** cpp-build `feat(pin): pin server certificates and check the endpoint host`; iris-opcua `build(native): connector 0.5.0 with PKI and pinning`.

## Part B — Backend (repo: `iris-opcua`, `backend/`)

### Task 3: ObjectScript native bindings and version gate

**Files:**
- Modify: `backend/src/OPCUA/Constants.inc` (`zfGetEndpoints 47`, `zfPkiCreateIdentity 48`, `zfPkiInspectCert 49`, `zfPkiCheckKeyPair 50`, `zfPkiNormalise 51`, `zfSetServerPin 52`)
- Create: `backend/src/OPCUA/Security/Native.cls`
- Modify: `backend/src/OPCUA/Client.cls` (two methods), `backend/src/OPCUA/Utils.cls` (`SupportsPki()`)
- Test: `backend/tests/OPCUA/Tests/Live/NativePkiTest.cls`

**Interfaces (Produces):**
- `OPCUA.Utils.SupportsPki() As %Boolean` — library loaded and version ≥ 0.5.
- `OPCUA.Security.Native` ClassMethods, each `As %Status`, each first checking `SupportsPki()` (error `The OPC UA connector on this server is older than 0.5.0 and cannot manage certificates. Reinstall it with iris-opcua-setup.`):
  - `CreateIdentity(pCertPath, pKeyPath, pClientURI, pHostname, pCommonName, pDays As %Integer = 3650, pKeyBits As %Integer = 2048)`
  - `InspectCert(pSource As %String, pIsPath As %Boolean, Output pInfo As %DynamicObject)` — keys: `subject, issuer, notBefore, notAfter, sanUris[], sanDns[], sanIps[], sha256, selfSigned, isCA, keyType, keyBits, keyUsage[], derHex`
  - `CheckKeyPair(pCertPath, pKeyPath, Output pMatch As %Boolean)`
  - `Normalise(pKind, pDataHex, pPassword, pOutCertPath, pOutKeyPath = "")`
- `OPCUA.Client.GetEndpoints(pURL, Output pEndpoints As %DynamicArray, Output pCertHex As %String, Output pAppUri As %String) As %Status` — endpoints `[{url, mode, policyUri, level}]`; caller re-runs `SetupClient` afterwards.
- `OPCUA.Client.SetServerPin(pFingerprints As %List, pHost As %String) As %Status`

- [ ] **Step 1: Write `NativePkiTest`** (Live; skips via `$$$AssertSkipped` unless `SupportsPki()`), working in `/tmp/opcua-pki-test-<job>/`: `TestCreateInspect` (sanUris[0] = `urn:test:opcua`, keyBits 2048, selfSigned 1), `TestPairMatch` / `TestPairMismatch`, `TestImportPemDerP12` (fixtures via `$ZF(-100,"/SHELL","openssl",…)` in the test only), `TestImportWrongPassword` (status text equals the native message; `own`-style output paths do not exist afterwards), `TestExpiredFixtureInspect` (notAfter < now), `TestGetEndpointsCertifiedServer` (`opc.tcp://certified-server:4840`: some endpoint mode 3, certHex non-empty, appUri non-empty; skip if unreachable).
- [ ] **Step 2: Run** `./demo/iris/dev-load.sh` then `Runner.Live()` — Expected: NativePkiTest fails (class/methods missing → compile error first).
- [ ] **Step 3: Implement** the bindings, following `SetupClient`'s `$ZF(-5,…)` + `DecodeError` pattern.
- [ ] **Step 4: Run** — NativePkiTest PASS.
- [ ] **Step 5: Commit** `feat(security): ObjectScript bindings for connector PKI and discovery`.

### Task 4: Store, Client URI and server keys

**Files:**
- Create: `backend/src/OPCUA/Security/Store.cls`
- Test: `backend/tests/OPCUA/Tests/Unit/SecurityStoreTest.cls`

**Interfaces (Produces), ClassMethods on `OPCUA.Security.Store`:**
- `Global() As %String` — `"^%OPCUA.Security"`, unless `^%OPCUA.Security.Override("global")` names another (tests only).
- `Root() As %String` — `##class(%File).NormalizeDirectory($System.Util.ManagerDirectory()_"opcua-pki")`, unless `^%OPCUA.Security.Override("root")`.
- `Dir(pWhich As %String) As %String` — `own`, `previous`, `servers`; `ServerDir(pKey, pWhich)` with `trusted`/`crl`. `EnsureDirs(pPath) As %Status` creates dirs (0700 on non-Windows via `%File.SetAttributes`).
- `NormaliseURL(pURL) As %String` — scheme+host lowercased, default port `4840` made explicit, trailing `/` removed, path kept.
- `ServerKey(pURL) As %String` — first 16 hex chars (lowercase) of SHA-256 of `NormaliseURL`.
- `URLHost(pURL) As %String`.
- `DefaultClientURI() As %String`, `ValidClientURI(pURI) As %Boolean`.
- `GetIdentity(Output pCfg As %DynamicObject) As %Boolean`, `SaveIdentity(pCfg)`, `ClearIdentity()`; `GetServer(pKey, Output pEntry) As %Boolean`, `SaveServer(pKey, pEntry)`, `RemoveServer(pKey)`, `ListServers() As %DynamicArray`. Stored as JSON strings at `@G@("identity")`, `@G@("servers",key)`.
- Identity cfg keys: `source` (`generated|imported|files`), `certPath, keyPath, clientURI, fingerprint, createdAt, replacedAt`. Server entry keys: `url, key, label, fingerprint, certFile, issuerFiles[], crlFiles[], selfSigned, trustedAt, trustedBy`.

- [ ] **Step 1: Write tests:** `TestNormaliseURL` (`opc.tcp://Certified-Server:4840/` and `opc.tcp://certified-server` → `opc.tcp://certified-server:4840`), `TestServerKeyStable` (same key for those two, different for `plc`), `TestDefaultClientURI` (matches `^urn:[a-z0-9.-]+:intersystems:iris:[a-z0-9._-]+:opcua$`), `TestValidClientURI` (rejects newline, space, `;`), `TestOverrideRoot` (override honoured; cleanup kills override), `TestConfigRoundTrip`.
- [ ] **Step 2: Run** `Runner.Offline()` — FAIL.
- [ ] **Step 3: Implement.** Verify during implementation that `^%OPCUA.Security` maps to IRISSYS and is writable from `OPCUA` by SuperUser; record the result in the class doc.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(security): instance-wide store for the OPC UA identity and trust`.

### Task 5: Identity lifecycle

**Files:**
- Create: `backend/src/OPCUA/Security/Identity.cls`
- Test: `backend/tests/OPCUA/Tests/Unit/SecurityIdentityTest.cls`, `backend/tests/OPCUA/Tests/Live/SecurityIdentityLiveTest.cls`

**Interfaces:**
- Consumes: Task 3 `Native.*`, Task 4 `Store.*`.
- Produces (ClassMethods, `As %Status` unless stated):
  - `Evaluate(pInfo As %DynamicObject, pKeyMatch As %Boolean, pNowUTC As %String, Output pErrors As %DynamicArray, Output pWarnings As %DynamicArray)` — pure. Error codes: `unreadable, unparseable, keyMismatch, notYetValid, expired, noUri, notRsa`; warnings: `expiresSoon` (≤30 days), `weakKey` (<2048), `keyUsage` (missing digitalSignature or keyEncipherment). Each entry `{code, message}`.
  - `Status(Output pStatus As %DynamicObject)` — `{configured, ready, source, clientURI, fingerprint, subject, notBefore, notAfter, daysLeft, errors[], warnings[], candidates[], impact{pipelines[{namespace,name,url}], servers[{key,url,label}]}, advanced{certPath,keyPath,storeRoot}}`. Candidates only when not configured: `/usr/irissys/uac/certs/secuac.crt.der` + `.key.der` if both exist.
  - `Create(pClientURI As %String = "", pReplace As %Boolean = 0, pCurrentFp As %String = "", Output pStatus)`
  - `Import(pCertHex, pKeyHex, pP12Hex, pPassword, pReplace = 0, pCurrentFp = "", Output pStatus)` — exactly one of (cert+key) or p12.
  - `UseFiles(pCertPath, pKeyPath, pReplace = 0, pCurrentFp = "", Output pStatus)` — references in place.
  - `GuardReplace(pReplace, pCurrentFp)` — configured & !replace → `OPCUA.REST.Error.Conflict("An IRIS client identity is already configured. Replacing it means every OPC UA server must approve the new certificate.")`; replace & fp ≠ current → `Conflict("The client identity changed since you reviewed it. Reload and review the replacement again.")`.
  - `Active(Output pCert, Output pKey, Output pURI)` — error unless ready; error messages: `No IRIS client identity is set up. Open Settings › OPC UA Security to create one.` / `The IRIS client identity is not usable: <first error message>`.
  - `Impact(Output pImpact As %DynamicObject)` — every namespace where `OPCUA.Adapter.Common` is compiled; production items with adapter `SecurityMode=3` and empty `PublicCertificate`/`PrivateKey`; plus `Store.ListServers()`.
  - `CertificateBytes(pFormat As %String, Output pData As %String, Output pFilename As %String)` — `der`/`pem`; filenames `iris-opcua-client.der` / `.pem`.
- Create/Import/UseFiles: validate new material in a staging dir **before** touching `own/`; on success move the old `own/*` into `previous/<timestamp>/`; never leave partial files on failure. Generated certs: commonName `IRIS OPC UA Client (<hostname>/<instance>)`.

- [ ] **Step 1: Unit tests** (offline, `Evaluate` + `GuardReplace` with a test-override store): `TestEvaluateExpired`, `TestEvaluateNotYetValid`, `TestEvaluateExpiresSoon` (29 days → warning, 31 → none), `TestEvaluateNoUri`, `TestEvaluateKeyMismatch`, `TestEvaluateNotRsa`, `TestGuardNoReplace` (409 text above), `TestReplaceStaleFingerprint` (409, store untouched), `TestStatusNeverHasKey` (serialise `Status` output, assert no `PRIVATE KEY`, no key hex).
- [ ] **Step 2: Live tests** (override root + global): `TestCreateThenReuse` (Create; second Create without replace → 409; `Status` fingerprint unchanged; `Active` paths exist), `TestImportPair`, `TestImportP12`, `TestImportMismatchRejected` (nothing in `own/`), `TestImportExpiredRejected`, `TestImportNoSanUriRejected`, `TestUseFilesDemoSecuac` (ready, clientURI `urn:secuac`), `TestUseFilesThenDeleted` (delete key → `Status.ready=0`, error `unreadable`; `Active` errors), `TestReplaceKeepsPrevious`, `TestImpactListsManagedPipeline` (throwaway production item with SecurityMode 3 and no paths listed; one with paths not listed).
- [ ] **Step 3: Run** both suites — FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** — PASS.
- [ ] **Step 6: Commit** `feat(security): create, import and validate the IRIS client identity`.

### Task 6: Server trust and pins

**Files:**
- Create: `backend/src/OPCUA/Security/Trust.cls`
- Test: `backend/tests/OPCUA/Tests/Unit/SecurityTrustTest.cls`, `backend/tests/OPCUA/Tests/Live/SecurityTrustLiveTest.cls`

**Interfaces:**
- Consumes: Task 3 `Client.GetEndpoints`, `Native.InspectCert/Normalise`; Task 4 `Store`.
- Produces:
  - `Inspect(pURL, Output pResult As %DynamicObject)` — `{url, key, offersSignAndEncrypt, policies[], applicationUri, certificate{subject, issuer, notBefore, notAfter, sha256, sanUris[], sanDns[], sanIps[], selfSigned}, identity{uriMatches, hostMatches, problems[]}, trusted, pinnedFingerprint, changed, needsIssuer, issuerName, previous{…certificate fields}}` (`previous` present when `changed`).
  - `CheckEndpointIdentity(pCertInfo, pAppUri, pHost, Output pProblems As %DynamicArray) As %Boolean` — pure; problem messages `The certificate is for application <sanUri>, but the server says it is <appUri>.` and `The certificate does not name <host>; it names <dns/ip list>.`
  - `Trust(pURL, pFingerprint, pLabel = "", Output pResult)` — re-fetches; mismatch → `Conflict("The server presented a different certificate than the one you reviewed. Review it again.")`; identity problems → `BadRequest(<problems joined>)`; replaces any earlier pin for that key (old cert file deleted); returns `Inspect`-shaped result.
  - `AddIssuer(pURL, pCaHex, pCrlHex, Output pResult)` — requires existing pin; normalises both; verifies the pinned cert chains to the CA with `$System.Encryption.X509VerifyCertChain` (PEM built from DER) and that the CRL is signed by that CA; stores under `trusted/` and `crl/`.
  - `Remove(pKey)`, `List(Output pList As %DynamicArray)` (with expiry and daysLeft).
  - `Pin(pURL, Output pFps As %List, Output pTrustDir, Output pCrlDir, Output pHost)` — errors: not trusted → `IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.`; needs issuer → `This server's certificate was issued by <issuer>. Add that CA certificate and its revocation list before connecting.`; trust dir empty → same not-trusted error (allow-all guard).

- [ ] **Step 1: Unit tests:** `TestIdentityUriMismatch`, `TestIdentityHostMismatch`, `TestIdentityIpHost`, `TestPinRefusesUntrusted`, `TestPinRefusesEmptyTrustDir` (entry present, dir emptied → refuse), `TestPinRefusesMissingIssuer`.
- [ ] **Step 2: Live tests** (certified-server; skip when unreachable): `TestInspectCaSigned` (needsIssuer 1, issuerName contains `myCA` subject, sha256 equals `Native.InspectCert` of `demo/certified-server/certs/secsvr.crt.der` copied into the test dir), `TestTrustWrongFingerprint` (409, no files), `TestTrustThenIssuer` (Trust → Pin errors needs-issuer; AddIssuer with myCA.crt.der + myCA.crl hex → Pin OK, trust dir has 2 files), `TestAddIssuerWrongCa` (a fresh self-signed CA → 400), `TestChangedDetected` (manually overwrite stored pin fingerprint → Inspect `changed=1`, `previous` present).
- [ ] **Step 3: Run** — FAIL. **Step 4: Implement.** **Step 5: Run** — PASS.
- [ ] **Step 6: Commit** `feat(security): review, pin and trust OPC UA server certificates`.

### Task 7: Managed connection resolution and diagnosis

**Files:**
- Create: `backend/src/OPCUA/Security/Connection.cls`, `backend/src/OPCUA/Security/Diagnose.cls`
- Modify: `backend/src/OPCUA/REST/ClientManager.cls` (`Connect` uses `Connection.Setup`), `backend/src/OPCUA/Adapter/Common.cls` (both `SetupClient` call sites → `Connection.Setup`; on connect failure in managed mode log `Diagnose.Run` message)
- Test: `backend/tests/OPCUA/Tests/Unit/SecurityConnectionTest.cls`, `backend/tests/OPCUA/Tests/Live/SecurityConnectionLiveTest.cls`

**Interfaces:**
- `Connection.IsManaged(pMode, pCertPath, pKeyPath) As %Boolean` — `pMode=3 && pCertPath="" && pKeyPath=""`.
- `Connection.Setup(pClient As OPCUA.Client, pURL, pMode, pClientURI, pCertPath, pKeyPath, pTrustDir, pCrlDir, Output pManaged As %Boolean) As %Status` — manual/mode 1: exactly today's `SetupClient(, mode, uri, cert, key, trust, crl)`; managed: `Identity.Active` + `Trust.Pin` (refuse on error, no native call), then `SetupClient` with those, then `pClient.SetServerPin`.
- `Diagnose.Classify(pErrorText As %String, pDiscovery As %DynamicObject, pPinnedFp As %String, pClientFp As %String) As %DynamicObject` — pure; returns `{category, message, clientFingerprint?}`. Categories and messages:
  - `network` — `IRIS could not reach the OPC UA server. Check the URL, port and firewall.` (discovery failed with BadConnectionClosed/BadTimeout/BadCommunicationError/resolve failure)
  - `noSecureEndpoint` — `The server does not offer Sign & Encrypt with a security policy IRIS supports.`
  - `serverChanged` — `Server certificate changed—review and approve the replacement.`
  - `hostMismatch` — from `BadCertificateHostNameInvalid`: `The server's certificate does not name the host in this URL.`
  - `uriInvalid` — `BadCertificateUriInvalid`: `The Client URI does not match IRIS's certificate.`
  - `timeInvalid` — `BadCertificateTimeInvalid`: `A certificate is expired or not yet valid, or the clocks differ.`
  - `clientNotApproved` — remaining security failures (`BadSecurityChecksFailed`, `BadCertificateUntrusted`, `BadCertificateInvalid`, `BadSecureChannelClosed` right after OPN) when discovery shows the pinned cert: `The OPC UA server has not approved IRIS's certificate yet. Download the IRIS client certificate, ask the server administrator to trust it (often: move it from the server's "rejected" to its "trusted" certificates), then test again.` + `clientFingerprint`.
  - `other` — the original error text.
- `Diagnose.Run(pURL, pFailure As %Status) As %DynamicObject` — runs discovery with a fresh mode-1 client, then `Classify`.

- [ ] **Step 1: Unit tests:** `TestIsManaged` (mode 3 no paths → 1; cert set → 0; mode 1 → 0), `TestManualUnchanged` (Setup with explicit paths and a stub client subclass `OPCUA.Tests.StubClient` records the exact `SetupClient` args; no `SetServerPin`), `TestManagedRefusesNoIdentity` (stub never receives `SetupClient`), `TestManagedRefusesUntrusted`, one `TestClassify<Category>` per category above (exact message strings).
- [ ] **Step 2: Live tests** (test store; certified-server): `TestManagedBeforeApproval` (identity created, server trusted + issuer; REST-path `ClientManager.Connect` fails; `Diagnose.Run` → `clientNotApproved`, fingerprint = identity fp), `TestManagedUnreachable` (`opc.tcp://certified-server:4999` → `network`), `TestNoFallback` (after failure, no connect in mode 1 happened: `Connect` status is error, and client state is not connected), `TestMode1Unchanged` (plc browse still works), `TestManualDemoUnchanged` (explicit demo `secuac` paths to certified-server connect as before).
- [ ] **Step 3: Run** — FAIL. **Step 4: Implement.** **Step 5: Run** Offline + Live, including existing `SecuredPipelineTest` and the PollingExample/SubscriptionExample gate — PASS.
- [ ] **Step 6: Commit** `feat(security): managed Sign & Encrypt for Node Explorer and pipelines`.

### Task 8: REST endpoints

**Files:**
- Create: `backend/src/OPCUA/REST/SecurityService.cls`
- Modify: `backend/src/OPCUA/REST/Handler.cls` (routes below), `backend/src/OPCUA/REST/ConnectionService.cls` (`security` block), `backend/src/OPCUA/REST/DeployService.cls` (managed: write only `SecurityMode=3`; ignore `clientURI` when no cert/key)
- Test: `backend/tests/OPCUA/Tests/Unit/SecurityRestTest.cls`

**Routes (real verbs):** `GET /security/identity`, `POST /security/identity`, `POST /security/identity/import`, `POST /security/identity/files`, `GET /security/identity/certificate` (`format=der|pem`; binary response with `Content-Disposition: attachment; filename=…`, content types `application/pkix-cert` / `application/x-pem-file`), `GET /security/servers`, `POST /security/servers/inspect`, `POST /security/servers/trust`, `POST /security/servers/issuer`, `DELETE /security/servers/:key`.

**Bodies:** create `{clientURI?, replace?, currentFingerprint?}`; import `{certificate?, key?, pkcs12?, password?, replace?, currentFingerprint?}` (hex); files `{certPath, keyPath, replace?, currentFingerprint?}`; inspect `{url}`; trust `{url, fingerprint, label?}`; issuer `{url, caCertificate, crl}` (hex).

**`/test` addition** (managed only): `security: {managed: true, identityReady, serverTrusted, diagnosis?: {category, message, clientFingerprint?}}`; on success `diagnosis` absent and `securityMode: 3` echoed.

- Every `/security` handler first: `$System.Security.Check("%Admin_Secure","USE")` else `Error.Forbidden("Managing OPC UA certificates needs the %Admin_Secure:USE privilege (a SuperUser account).")`.
- `LogInternal` masking extended to `key`, `pkcs12`, `password` body fields.

- [ ] **Step 1: Tests** (offline, calling `SecurityService` methods with a test store and no native library where possible): `TestForbiddenWithoutPrivilege` (run as a test user lacking the resource via `$System.Security.Login` in a child job or by stubbing the check method `HasPrivilege()`), `TestIdentityResponseNoKey`, `TestImportBothFormsRejected` (cert+key and pkcs12 → 400), `TestDeployManagedWritesOnlyMode` (no `PublicCertificate`/`PrivateKey`/`ClientURI`/`TrustListDir` settings on the item), `TestDeployManualKeepsPaths`, `TestLogMasksKey`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS; also curl smoke: `curl -s -u SuperUser:SYS localhost:52783/csp/opcua/api/security/identity`.
- [ ] **Step 5: Commit** `feat(rest): /security endpoints and secure connection readiness`.

### Task 9: Demo stack, end-to-end approval script, role test

**Files:**
- Modify: `docker-compose.yml` (named volume `iris-opcua-pki` → `/usr/irissys/mgr/opcua-pki`), `demo/iris/Dockerfile` (create dir, owner irisowner, 0700)
- Create: `demo/iris/secure-e2e.sh`
- Modify: `backend/tests/OPCUA/Tests/Runner.cls` (`Run(pClassOrMethod As %String) As %Boolean`, same summary output)
- Create: `backend/tests/OPCUA/Tests/Live/SecureE2ETest.cls` — methods run by phase, each reads `^%OPCUA.Security.Override` set by phase 1
- Modify: `backend/tests/OPCUA/Tests/Live/ApiRoleTest.cls` (`TestSecurityForbidden`: role-only user → 403 on `/security/identity`; managed `/test` → 403-mapped readiness, not a connect)

**Script phases** (`secure-e2e.sh`, exits non-zero on any failure):
1. Reset certified-server trust: `docker compose up -d --force-recreate certified-server` (image contents = only myCA).
2. `Runner.Run("OPCUA.Tests.Live.SecureE2ETest:TestPhase1")` — test store; create identity; trust certified-server + issuer; managed `/test` → `clientNotApproved`; pin stored; export client DER to `/tmp/opcua-e2e/client.der`.
3. `docker cp` iris:`/tmp/opcua-e2e/client.der` → host → certified-server:`/app/trustdir/iris-e2e.der`; restart certified-server if its log does not show the reload within 5 s.
4. `TestPhase2` — managed `/test` connected; managed polling pipeline (row-source, certified-server node) writes ≥1 row; then swap the pin to a different fingerprint in the test store → `/test` diagnosis `serverChanged` with the exact message; expired-identity case: UseFiles with an expired fixture → `/test` refuses with identity error, no native connect.
5. Cleanup phase: remove overrides, delete test pipeline, recreate certified-server.

- [ ] **Step 1: Write `SecureE2ETest` + script + Runner.Run.**
- [ ] **Step 2: Run** `./demo/iris/secure-e2e.sh` — Expected: `Summary: N passed` for both phases, exit 0.
- [ ] **Step 3: Run** `ApiRoleTest` — PASS.
- [ ] **Step 4: Commit** `test(security): end-to-end approval flow against certified-server`.

## Part C — Console (`webapp/`)

### Task 10: Models and API client

**Files:**
- Modify: `webapp/src/app/core/models/opcua.models.ts`, `webapp/src/app/core/services/api.service.ts`, `api.service.spec.ts`
- Modify: `webapp/src/app/core/services/config.service.ts` (no defaults for cert fields; keep existing values)

**Produces (TypeScript):**
- `IdentityStatus`, `IdentityIssue {code, message}`, `IdentityImpact`, `ServerCertificateReview`, `TrustedServer`, `SecureReadiness {managed, identityReady, serverTrusted, diagnosis?: SecurityDiagnosis}`, `SecurityDiagnosis {category: 'network'|'noSecureEndpoint'|'serverChanged'|'hostMismatch'|'uriInvalid'|'timeInvalid'|'clientNotApproved'|'other', message, clientFingerprint?}` — field names exactly as Task 8.
- `isManaged(server: ServerProfile): boolean` — `securityMode === 3 && !server.certPath && !server.keyPath`.
- `ApiService`: `getIdentity()`, `createIdentity(body)`, `importIdentity(body)`, `useIdentityFiles(body)`, `downloadClientCertificate(format: 'der'|'pem'): Observable<Blob>` (HttpClient `responseType: 'blob'`, so the JWT interceptor applies), `listTrustedServers()`, `inspectServer(url)`, `trustServer(url, fingerprint, label?)`, `addServerIssuer(url, caHex, crlHex)`, `removeTrustedServer(key)`; `buildConnectionBody` sends no cert fields for managed profiles.
- `bytesToHex(buf: ArrayBuffer): string` in `core/util/hex.ts`.

- [ ] **Step 1: Spec tests** (`api.service.spec.ts` with `HttpTestingController`): managed body has no `certPath/keyPath/trustDir/crlDir/clientURI`; manual body keeps them; `downloadClientCertificate('pem')` hits `/security/identity/certificate?format=pem` with blob; `bytesToHex(Uint8Array [0,255,16])` → `'00FF10'`.
- [ ] **Step 2: Run** `npx ng test --watch=false --browsers=ChromeHeadless` — FAIL.
- [ ] **Step 3: Implement.** **Step 4: Run** — PASS; `npx tsc --noEmit` clean.
- [ ] **Step 5: Commit** `feat(webapp): security models and API client`.

### Task 11: OPC UA Security tab

**Files:**
- Create: `webapp/src/app/shared/settings-modal/security-tab/security-tab.component.ts` (+ `.spec.ts`)
- Modify: `webapp/src/app/shared/settings-modal/settings-modal.component.ts` (tab `'security'` between servers and gateway, icon `verified_user`, label `OPC UA Security`; `returnTo` server id signal)

**Behaviour** (layout and copy from `docs/notes/opcua-security-ux.html`):
- States: loading; 403 → "Managing OPC UA certificates needs a SuperUser account."; not configured → *Create client identity* (primary), *Use existing certificate* (file pickers cert+key, or one .pfx/.p12 + password), candidate banner "A certificate was found on IRIS: <clientURI> · expires <date> — Use it"; configured → status line (`Default IRIS client · Ready` / `Expires in N days` amber ≤30 / `Expired` red), Client URI, fingerprint (monospace, copy button), validity, source, *Download certificate* (DER, PEM), *Replace…*.
- Replace dialog (`shared/confirm-dialog`): lists `impact.pipelines` (namespace · name · url) and `impact.servers`, sentence "Each of these servers must approve the new certificate before these connections work again."; confirm sends `replace: true, currentFingerprint`.
- Insecure upload warning when the API base URL is `http:` and host not `localhost`/`127.0.0.1`: "This sends the private key over an unencrypted connection. Prefer “Use files already on IRIS” under Advanced."
- **Advanced** (`<details>` collapsed): Client URI field (only before create), "Use files already on IRIS" (two path inputs), file paths of the active identity, store root, trusted servers list with *Stop trusting*.
- "Return to <server>" link when `returnTo` set.
- Every field feeding a `computed` gate is a signal (`[ngModel]` + `(ngModelChange)`).

- [ ] **Step 1: Component spec tests:** renders *Create client identity* when `configured=false`; shows `Expired` when `errors` contains `expired`; Replace confirm posts `replace:true` with the current fingerprint; private key never echoed back into the DOM after import (file input cleared).
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS; `npm run lint:template` clean.
- [ ] **Step 5: Commit** `feat(webapp): OPC UA Security tab`.

### Task 12: Server form readiness

**Files:**
- Create: `webapp/src/app/shared/settings-modal/server-security/server-security.component.ts` (+ `.spec.ts`)
- Modify: `settings-modal.component.ts` (replace the "Certificate Configuration" block lines ~267–300 and delete `onSecurityModeChange`'s path defaults lines ~835–842; mode text "Sign & Encrypt uses this IRIS instance's client identity."), `webapp/src/app/pages/documentation/documentation.component.ts` (new flow replaces the paths section)

**Behaviour** (managed profiles; Sign & Encrypt selected):
1. *IRIS client identity* — Ready / missing / expired → **Set up identity** (switches to Security tab with `returnTo`).
2. *Server certificate* — Trusted · expires …, or **Review certificate** → inline panel: subject, issuer, application URI, validity, full SHA-256, "Compare this fingerprint with the one the server's administrator gives you." → **Trust this server**. `needsIssuer`: CA + CRL file pickers → **Add issuer**. `changed`: old vs new side by side, headline `Server certificate changed—review and approve the replacement.` → **Approve replacement**. Identity problems shown and Trust disabled. `offersSignAndEncrypt=false`: "This server does not offer Sign & Encrypt." and Trust disabled.
3. *Server approval of IRIS* — "Checked when you test the connection." After `/test`: Approved, or the diagnosis message with **Download IRIS certificate** and fingerprint for `clientNotApproved`.
- *Test connection* result line: `Connected · Sign & Encrypt` on success; diagnosis message otherwise. Never offers switching to None.
- Manual profiles (paths present): readiness shows "Manual certificate files" and the five existing inputs inside **Advanced**; untouched values on save.
- Username/password and credentials controls unchanged.

- [ ] **Step 1: Spec tests:** managed profile shows three rows and no path inputs; manual profile shows "Manual certificate files" with the existing values; `changed=true` shows the exact headline; `clientNotApproved` shows the download button; switching to Sign & Encrypt on a new profile leaves `certPath` empty.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS; `npx tsc --noEmit`; `npx ng build` succeeds.
- [ ] **Step 5: Commit** `feat(webapp): Sign & Encrypt readiness in the server settings`.

## Part D — Ship

### Task 13: Installer, docs, changelog

**Files:**
- Modify: `installer/Cargo.toml` (0.5.0), installer README/CHANGELOG entry; `CHANGELOG.md`; `CLAUDE.md` (both: `/security` row in REST table, Sign & Encrypt model, empty-trust-list rule, ordinals 1–52, `^%OPCUA.Security`, no-native-library note on Offline tests); `docs/architecture.md` (Security section); `legacy/windows-studio/` note that the Studio XML lacks `OPCUA.Security.*` (or regenerate if a generator exists — check `docs/workflow.md`).
- [ ] **Step 1:** `cd webapp && npx ng build`; `cd installer && cargo build --release && cargo test` — Expected: PASS, embedded file list includes the 0.5.0 native files and `OPCUA/Security/*.cls`.
- [ ] **Step 2: Commit** `chore: installer 0.5.0 and docs for managed Sign & Encrypt`.

### Task 14: Full verification

- [ ] `./demo/iris/dev-load.sh` — exit 0.
- [ ] `Runner.Offline()` → `1`, Summary with 0 failed.
- [ ] `Runner.Live()` → `1` (DataTest skipped as documented).
- [ ] `./demo/iris/secure-e2e.sh` — exit 0.
- [ ] Regression gate: enable `PollingExample` + `SubscriptionExample`, rows with non-empty values land.
- [ ] Browser run via the `run` skill against `ng serve`: create identity → trust certified-server (+ issuer) → test fails with `clientNotApproved` → approve via script step 3 → test passes → deploy a pipeline → rows land; screenshot each state.
- [ ] Write the verification report: what passed, and **not verified**: Windows DLL at runtime, Windows key ACLs, Windows paths, servers other than the demo ones.
