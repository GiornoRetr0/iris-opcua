# Client setup: recommended product improvements

> Updated scope: implement the backend-only CLI described in [terminal-installer-plan.md](terminal-installer-plan.md). OPC UA server connections, certificates, schemas, and pipelines stay in the webapp. The first-run wizard discussion below is a broader webapp proposal, not terminal-installer scope.

An administrator can assemble the current components manually. A wizard is optional for that workflow, but documentation alone does not make installation self-service. Prioritize a configurable installer, readiness diagnostics, and credential handling before adding wizard screens.

This proposal reflects the current source. These features have not been implemented as part of the documentation change.

## What already works

- Settings accepts an IRIS API URL and credentials without rebuilding the frontend.
- `GET /ping` checks API access, returning a timestamp and fixed version string.
- Test Connection tests an OPC UA profile through IRIS and the native connector.
- Settings accepts server-side certificate/key/trust paths.
- Existing screens support schema creation, device validation, deployment, and explicit pipeline startup.
- Docker automates a demo installation.

## 1. Configurable installer and matched releases

Provide an administrator-run installer accepting namespace, source directory, library location, API path, and application resource. Support creating a dedicated namespace or using an existing dedicated one. Keep demo provisioning separate.

Check prerequisites before changes, propagate import/compile failures, support reruns, and document upgrades and rollback. Preserve existing productions and account policies. The current installer assumes Docker paths, creates demo credentials, and changes default-account password settings.

Ship matched frontend, ObjectScript, and native-library versions with checksums and a tested IRIS/OS/CPU/dependency matrix. Resolve the Windows source/binary compatibility caveat. Include an example production web-server configuration and tested API permission profile.

## 2. Readiness diagnostics

Add an independent **Test IRIS connection** action and a backend readiness endpoint. Report:

- Target namespace and backend version.
- Required classes and native-library path/load/version.
- Interoperability availability and conflicting running production.
- Explicit administrator checks for compilation, database writes, and production-management permissions without starting collection.
- For a server profile: endpoint reachability, authentication, security compatibility, readable certificate files, trust failures, and certificate expiry where available.

Show the failing layer with a concrete corrective action. Do not expose secrets or sensitive host details to unauthorized callers. `/ping` alone cannot verify any of these prerequisites; a successful OPC UA connection also does not prove data will be stored. Finish onboarding with an explicitly initiated sample collection.

## 3. Credentials and production isolation

Replace persistent browser passwords with authenticated sessions and backend-held server profiles/credential references. Establish and test application roles. Pipeline deployment currently also copies OPC UA username/password into adapter settings; address that storage path as part of the same work.

Refuse to start the console production if another production is running in the namespace. Currently `DeployService.StartOrUpdateProduction()` stops it automatically. The README requires a dedicated namespace, but the product should enforce that boundary.

## 4. A short first-run wizard

Build it on the installer and diagnostics:

1. **Connect to IRIS:** URL and sign-in; confirm the actual namespace and backend version.
2. **Verify installation:** show readiness results, corrective instructions, and retry.
3. **Add an OPC UA server:** endpoint, security settings, certificate guidance, and connection test.
4. **Verify data:** reuse the existing schema and binding screens, then offer an explicit start-and-check action.

Make the wizard resumable and available later from Settings. Separate administrator host installation from operator configuration. A browser wizard cannot install native libraries or import an absent backend before it has a working backend connection; provide the installation package and instructions at that stage.

Managed certificate import/export, trust approval, expiry monitoring, and shared server profiles would improve ongoing operation. They require backend support beyond adding file inputs to the current path-based settings.

## Client-handoff acceptance criteria

A new administrator can install a matched release on a supported IRIS instance, configure the frontend/API, connect to their server, and verify stored measurements using the guide. Failed prerequisites identify specific repairs. Re-running setup preserves data and configuration, credentials do not persist in browser storage, and setup/start actions never stop an unrelated production.
