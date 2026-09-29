# Redesign plan: understand the system, then simplify it

**Status:** proposal. Stage 1 has since been implemented, together with a
storage change the plan did not originally include: generated schemas now keep
each measurement's value, status, source timestamp and server timestamp instead
of a bare value plus one row-level timestamp pair. See
`OPCUA.DataSource.RowWriter` and `OPCUA.Tests.MeasurementMetadataTest`. Stages 2
onwards remain proposals.  
**Basis:** source inspection on 22 September 2026, including the current working tree.  
**Objective:** make the backend and frontend easier for a human to understand and maintain while preserving their functionality.

This is a guide for working through the redesign with an AI assistant. You should not need to understand every line before starting. You should be able to understand the responsibility being changed, find its implementation, and verify its behavior before moving to the next stage.

No application tests or performance benchmarks were run while drafting this plan. The verification steps below are future work, not claims that the current application has passed them.

Existing filenames below are links. Method names are search landmarks: open the file and search for the name. **Proposed names are explicitly marked and do not exist yet.** They describe a responsibility; they are not a requirement to create a large new framework.

## 1. The decision in plain language

Keep the current platforms: InterSystems IRIS, ObjectScript, Angular, and the native OPC UA client. Keep reusable schemas, device bindings, polling, subscriptions, nested data, certificates, the Management Portal, and the hand-authored examples.

Simplify the connections between these pieces:

1. Give collected-row construction one implementation shared by polling and subscriptions.
2. Give schema interpretation one owner instead of reconstructing its meaning in several places.
3. Put protocol helpers below both REST and background collection, so either can use them.
4. Put schema operations together and pipeline operations together.
5. Make each frontend page coordinate an understandable workflow, with shared browsing and validation logic where appropriate.
6. Evaluate a simpler database write mechanism after the existing behavior is captured and protected.

The earlier suggestion to flatten all generated schemas is **not part of the default plan**. Nested ObjectScript objects are existing functionality. Replacing them could preserve a similar SQL view while still breaking object consumers. We can simplify their implementation without removing them.

The main test of success is: **can you explain where a behavior lives, change it in one place, and demonstrate that it still works?** A smaller line count is useful evidence, but moving code into more files does not itself reduce complexity.

### How to read this document

- Start with [the concepts](#2-the-concepts-you-actually-need), [one measurement's journey](#3-follow-one-measurement-through-the-current-system), and [the code map](#4-a-map-of-the-codebase).
- Read [the preservation contract](#5-what-preserve-functionality-means) and [the proposed architecture](#6-the-proposed-architecture) before implementation.
- Work through [the stages](#7-implementation-stages) one at a time. Each includes files, changes, verification, and a question you should be able to answer.
- Use [the AI collaboration guide](#8-how-to-work-with-an-ai-assistant-while-staying-in-control), [excluded changes](#9-changes-deliberately-excluded-from-the-default-redesign), [rollback guidance](#10-migration-and-rollback), and [success measures](#11-how-much-improvement-to-expect-and-how-to-measure-it) during review.

## 2. The concepts you actually need

Imagine two air conditioners exposing temperature and humidity. We want their measurements stored in IRIS so that SQL queries can retrieve them.

| Concept | Meaning in this project | Concrete example |
|---|---|---|
| OPC UA server | The program exposing a device's values over the network. One server can expose many devices. | A local `plc` container. |
| Endpoint | The address used to connect to that server. | `opc.tcp://plc:4840`. |
| Node | An addressable item on the server. Some nodes contain values; others organize children. | A device root with a `Temperature` child. |
| NodeId | The node's identifier within a server, including namespace and identifier type. | `ns=2;s=Plant.AC1`: namespace 2, string identifier `Plant.AC1`. |
| Browse | Ask a server which nodes are related to a particular node. The UI uses this to build its tree; the resolver uses it to find measurement nodes. | Find the temperature node under AC1. |
| Schema | A reusable description of the columns for a device type. It is represented by an ObjectScript class. | `OPCUA.DS.AirConditioner` with temperature and humidity. |
| Device binding | A configured device root to which the schema should apply. | Use the air-conditioner schema for AC1 and AC2. |
| Pipeline | A configured background collector: endpoint, schema, devices, collection mode, and settings. | Collect both air conditioners every five seconds. |
| Production | IRIS's container for background integration services. It owns their configuration and execution. | `OPCUA.Pipeline.Production`. |
| Business service | One running/configurable component in that production. A pipeline uses one such component. | A polling service for the air conditioners. |
| Adapter | The component that manages the OPC UA connection and obtains data for a business service. | Polling adapter or subscription adapter. |
| Resolver | Code that turns schema column names plus device roots into actual node identifiers by browsing a connected server. | Find AC1's and AC2's separate temperature nodes. |
| Persistent class | An IRIS class whose instances can be stored and queried through SQL. | The generated schema class provides the measurement table. |
| Serial object | An object embedded inside a parent row rather than stored as an independent row. | A `Motor` object containing `Temperature`. |
| Global | An IRIS database structure, written with a leading `^`. It is persistent storage, not just a shared variable in memory. | `^OPCUA.DataSource(className)` stores derived metadata. |
| Projection | A hook IRIS invokes when compiling a class. Here it derives OPC UA metadata from the compiled schema. | `Projection.CreateProjection()`. |
| Native bridge | ObjectScript calls into a compiled library that implements protocol operations. | `Client.cls` uses `$ZF` calls. |
| REST API | HTTP endpoints the Angular UI calls to browse, manage schemas, and configure pipelines. | `POST /schemas` creates a schema. |

Two easily confused distinctions matter:

**A schema is not a pipeline.** Creating the schema creates the reusable structure. Deploying a pipeline attaches settings to that structure. Multiple pipelines can use the same schema and table.

**A browser server profile is not a deployed pipeline configuration.** Profiles are saved in browser local storage. A deployed pipeline's settings live in IRIS and must keep working with the browser closed. Editing a browser profile is not automatically editing deployed services.

## 3. Follow one measurement through the current system

The following device names and values are illustrative, not guaranteed fixture data.

### 3.1 Create the schema

In the schema builder, select a representative device and its temperature and humidity nodes. The frontend sends a column description to `POST /schemas`.

Read these files in order:

1. [schema-builder.component.ts](../../webapp/src/app/pages/schema-builder/schema-builder.component.ts): search for `columns`, `relativePath`, and `createSchema`.
2. [api.service.ts](../../webapp/src/app/core/services/api.service.ts): search for `createSchema` to see the HTTP call.
3. [Handler.cls](../../backend/src/OPCUA/REST/Handler.cls): search for `/schemas` and `SchemasCreate` to find the route.
4. [SchemaService.cls](../../backend/src/OPCUA/REST/SchemaService.cls): read `Create()` and `GenerateSchemaClass()`.

The backend builds a class definition and asks IRIS to compile it. The generated class inherits from [DeviceSchema.cls](../../backend/src/OPCUA/DataSource/DeviceSchema.cls). Nested folders also produce serial classes.

Compilation triggers [Projection.cls](../../backend/src/OPCUA/DataSource/Projection.cls), particularly `CreateProjection()` and `ProcessObj()`. This writes the derived OPC UA specification into `^OPCUA.DataSource`.

Separately, [Definition.cls](../../backend/src/OPCUA/DataSource/Definition.cls) contains the `SaveSourcedData()` method generator. It generates a method that appends a binary row to the class's storage global. It is not generated by `Projection.cls`, despite statements in some existing documentation.

**Nothing is collecting yet.** There need not be a pipeline using this schema.

### 3.2 Bind the devices

The binding screen chooses an existing schema, server, device roots, and collection settings. Its device list might contain:

```text
ns=2;s=Plant.AC1|AC1
ns=2;s=Plant.AC2|AC2
```

The text after `|` is the label used to identify rows. The configured device roots are stored in the production setting `DeviceNodePaths`.

Read [device-binding.component.ts](../../webapp/src/app/pages/device-binding/device-binding.component.ts), especially `checkPending()` and `deploy()`, then [DeployService.cls](../../backend/src/OPCUA/REST/DeployService.cls), especially `BindExistingSchema()` and `AddServiceItem()`.

Deployment validates the binding against the server and creates a **disabled** production item. It does not generate the schema, and it does not start collecting. An explicit start action enables collection.

### 3.3 Connect and find the actual measurement nodes

When the pipeline starts, its adapter connects to the server. Only after connecting can it browse each device and resolve the schema's column names.

Read [TCPPollingInboundAdapter.cls](../../backend/src/OPCUA/Adapter/TCPPollingInboundAdapter.cls): `Connect()` calls its parent connection method, then `ResolveSpecification()`, then prepares the read query. Shared resolution starts in [Common.cls](../../backend/src/OPCUA/Adapter/Common.cls), `ResolveRowSourceSpec()`, and continues in [Resolver.cls](../../backend/src/OPCUA/DataSource/Resolver.cls), `ResolveSpecification()`.

Suppose AC1 has both columns, while AC2 has temperature only. Resolution produces node requests plus a coverage mask:

```text
Schema columns:       Temperature, Humidity
AC1 coverage:         yes,         yes
AC2 coverage:         yes,         no
Read-result order:    AC1 temp, AC1 humidity, AC2 temp
```

A mask records which columns have a matching node. Missing columns consume no entry in the native result. The row writer must insert the missing value without shifting later values into the wrong columns.

This resolution happens again after reconnecting. It must not become a permanent list of node IDs captured when the pipeline was deployed.

### 3.4 Collect and save

For polling, the adapter asks the native client for a batch of values. The service receives it and constructs rows. Read [TCPPollingRowSourceService.cls](../../backend/src/OPCUA/Service/TCPPollingRowSourceService.cls), `OnProcessInput()`.

The intended result for this example is:

| NodePath | Temperature | Humidity |
|---|---:|---:|
| AC1 | 21.5 | 45 |
| AC2 | 23.0 | NULL |

Rows also contain timestamps. Currently the row-source services select timestamps from the first suitable resolved value for each device. They extract plain column values; this is different from the hand-authored typed-value path, which can retain per-value timestamps and status in wrapper objects. Preserve these differences during extraction rather than silently choosing a new timestamp or quality policy.

For subscriptions, [TCPSubscriptionInboundAdapter.cls](../../backend/src/OPCUA/Adapter/TCPSubscriptionInboundAdapter.cls), `OnTask()`, unpacks notification batches and passes individual batch entries to the service. [TCPSubscriptionRowSourceService.cls](../../backend/src/OPCUA/Service/TCPSubscriptionRowSourceService.cls) then performs almost the same row construction as the polling service.

**This duplicated last step is the best first implementation change.** Subscription queue handling and reconnect behavior remain the adapter's responsibility.

## 4. A map of the codebase

You do not need to start with the native library or the thousand-line security implementation. Use this map when a specific behavior is being changed.

| Area | Where to look | Question this area should answer |
|---|---|---|
| Native protocol access | [Client.cls](../../backend/src/OPCUA/Client.cls), [Utils.cls](../../backend/src/OPCUA/Utils.cls), [Constants.inc](../../backend/src/OPCUA/Constants.inc) | How do we call the native library and decode its response? |
| Connection and scheduling | [Adapter directory](../../backend/src/OPCUA/Adapter) | When do we connect, retry, poll, and subscribe? |
| Row handling | [Service directory](../../backend/src/OPCUA/Service) | How do received values become stored rows? |
| Schema interpretation | [DataSource directory](../../backend/src/OPCUA/DataSource) | What columns exist, and how do they map to nodes and storage? |
| Schema lifecycle | [SchemaService.cls](../../backend/src/OPCUA/REST/SchemaService.cls) | How is a schema created, listed, inspected, or deleted? |
| Pipeline lifecycle | [DeployService.cls](../../backend/src/OPCUA/REST/DeployService.cls), [PipelineService.cls](../../backend/src/OPCUA/REST/PipelineService.cls) | How do production items get created, edited, started, and removed? |
| HTTP routing | [Handler.cls](../../backend/src/OPCUA/REST/Handler.cls) | Which operation receives a browser request? |
| Security | [Pki.cls](../../backend/src/OPCUA/Security/Pki.cls), [Diagnose.cls](../../backend/src/OPCUA/Security/Diagnose.cls), [SecurityService.cls](../../backend/src/OPCUA/REST/SecurityService.cls) | Which identity and trust files are used, and what does a connection failure mean? |
| Browser configuration and API | [config.service.ts](../../webapp/src/app/core/services/config.service.ts), [api.service.ts](../../webapp/src/app/core/services/api.service.ts), [opcua.models.ts](../../webapp/src/app/core/models/opcua.models.ts) | What is saved in this browser, and what is exchanged with IRIS? |
| Screens | [app.routes.ts](../../webapp/src/app/app.routes.ts), [pages directory](../../webapp/src/app/pages) | Which page implements a user task? |
| Shared tree and settings | [opcua-tree.component.ts](../../webapp/src/app/shared/opcua-tree/opcua-tree.component.ts), [settings-modal.component.ts](../../webapp/src/app/shared/settings-modal/settings-modal.component.ts) | Which interaction is reused across screens? |
| Installation | [Installer.cls](../../demo/iris/IRISConfig/Installer.cls), [Dockerfile](../../demo/iris/Dockerfile), [docker-compose.yml](../../docker-compose.yml) | How do classes, binaries, namespaces, and test servers become available? |

### The second collection path must remain visible

[TCPPollingService.cls](../../backend/src/OPCUA/Service/TCPPollingService.cls) and [TCPSubscriptionService.cls](../../backend/src/OPCUA/Service/TCPSubscriptionService.cls) serve hand-authored `Definition` subclasses. They are small and used by examples and type tests. Their properties use [OPCUA.Types](../../backend/src/OPCUA/Types) wrappers.

The generated multi-device schemas use the two `RowSourceService` classes instead. Forcing both data models into one universal service could create more branching than it removes. Share proven common mechanics, but preserve both public entry paths.

[Generator.cls](../../backend/src/OPCUA/DataSource/Generator.cls) is a terminal tool that generates declarative class files. It is not the web schema generator. Two of its helpers, `InferType()` and `SanitizePropertyName()`, are also used by the web path. It therefore cannot simply be deleted as old code.

## 5. What “preserve functionality” means

Treat this table as the acceptance contract. Some behaviors have tests already; others need a baseline demonstration before their implementation changes.

| Capability | What must remain true |
|---|---|
| Browsing | Node identities, names, categories, expandable children, server selection, and existing fallback behavior for older native binaries remain usable. |
| Individual reads and writes | Explorer reads retain value, quality, timestamps, and failure/freshness presentation. Existing client and terminal write examples remain supported; do not invent a new UI write feature. |
| Schema creation | Creates reusable compiled schemas without creating or starting a pipeline. Preserve type mapping, generated names, and supported nesting. |
| Schema reuse | Multiple pipelines can share a schema and its table. Removing a pipeline does not remove the schema or historical data. |
| Schema deletion | Refuses while the schema is referenced. Preserve existing deletion semantics and explicitly explain data consequences to the operator. |
| Deployment | Binds an existing schema, preserves settings, and creates a disabled service. Starting remains explicit. |
| Portal configuration | A pipeline can be configured using IRIS settings without the webapp. The schema selector remains usable. |
| Rebinding | Editing device settings does not require schema regeneration. Preserve category editing without changing the service's identity. |
| Partial devices | Missing columns are represented as missing values and diagnosed. Preserve the distinction between partial coverage and a device that cannot contribute any columns. |
| Polling and subscriptions | Preserve mode-specific timing, batches, last-value behavior, queue handling, and reconnect behavior. Verify subscriptions separately from polling. |
| Reconnect | Establish a session before browsing, rebuild resolved mappings and native queries, and release old handles. |
| Stored values | Preserve SQL column names and types, nested object access, timestamp selection, zero/false values, strings, arrays, and missing-value behavior for each supported path. |
| Health reporting | Enabled, production running, and successfully collecting remain distinct. Shared-table row counts must not be presented as a particular pipeline's personal output count. |
| Security | Preserve anonymous and configured authenticated connections, managed and explicit certificate configuration, trust operations, certificate identity persistence, and meaningful diagnostics. |
| Frontend workflows | Preserve all existing routes, schema selection, create/edit distinctions, navigation, forms, validation, refresh controls, loading/error/empty states, keyboard access, and confirmations. |
| Browser settings | Existing server profiles, gateway settings, and old saved configurations remain readable. Keep migration at the storage boundary. |
| Native and install compatibility | Preserve library call signatures and supported binary/platform choices. Keep examples, installer import behavior, and terminal tooling functional. |

Preserving functionality does not require silently preserving a newly discovered bug. Record an unexpected behavior, explain its effect, and handle its correction as an explicit change with a focused check. Do not disguise behavior changes as code movement.

## 6. The proposed architecture

### 6.1 Keep two understandable flows

**Configuration flow:**

```text
Angular page
    → REST endpoint
    → schema or pipeline operation
    → IRIS class definition or production settings
```

**Collection flow:**

```text
IRIS production settings + compiled schema
    → adapter connects
    → resolver builds a mapping for this connection
    → polling/subscription adapter obtains a batch
    → shared row writer constructs and stores rows
```

The browser configures collection; it is not required to keep collection alive. REST and background collection may use the same protocol and schema helpers, but background collection should not need a REST service class.

### 6.2 Give each responsibility one owner

The names in this table are proposed. Introduce them only while moving a concrete responsibility and removing its previous implementation.

| Proposed owner | Owns | Does not own |
|---|---|---|
| `OPCUA.DataSource.RowWriter` | Turning a resolved batch into stored device rows, including nested values and timestamps. | Connections, subscription queues, or HTTP. |
| `OPCUA.DataSource.Metadata` | Reading a compiled schema into one consistent description of columns and storage layout. | Browsing devices or keeping a second editable schema database. |
| `OPCUA.Protocol.BrowseDecoder` | Decoding native browse results and their classification rules. | Browser request parsing or production settings. |
| `OPCUA.Security.ConnectionOptions` | Resolving explicit/managed security settings into options for a client connection. | Owning long-lived sessions or changing trust decisions automatically. |
| `OPCUA.DataSource.SchemaManager` | Schema generation, inspection, usage checks, and owned-artifact deletion. | Enabling pipelines. |
| `OPCUA.Pipeline.Manager` | Reading and modifying production items and reporting their status. | Generating schema classes or duplicating IRIS configuration in another database. |

These are a small set of concrete classes, not an instruction to add interfaces, factories, repositories, or plugin registries around every operation. Existing classes can be renamed or moved where compatibility allows; public entry points can delegate temporarily.

### 6.3 Keep three kinds of information separate

**Schema information:** column names, types, relative node names, and nested structure. The compiled class remains authoritative. Derived metadata must be rebuildable from it.

**Pipeline information:** endpoint, schema class, devices, timing, security, labels, enabled state. IRIS production settings remain authoritative. Do not add a competing pipeline configuration store.

**Connection information:** actual resolved node IDs, missing-column masks, and native query handles. This is temporary and must be replaced after reconnecting.

For example, “Temperature is a numeric schema column” survives reconnects; “Temperature is currently node X under device AC1” belongs to that connection's resolution result.

The proposed metadata result should expose named fields such as `propertyPath`, `relativeNodePath`, `type`, and `storagePosition`. The proposed resolution result should keep each device, its coverage, and result positions together. These can be simple ObjectScript objects or documented arrays; avoid a large class hierarchy.

The native library still expects positional binary lists. Keep that format at the native boundary. Likewise, if direct storage writes remain, keep their binary layout inside the writer. A binary list should not force every surrounding operation to know that “item 4 means this.”

## 7. Implementation stages

Do not implement this document in one large change. Each stage should leave a runnable system, have a reviewable diff, and include an explanation of which responsibility moved.

### Stage 0 — Establish a trustworthy baseline

**Purpose:** learn what works today and protect it before rearranging it.

**Read:** [ResolverTest.cls](../../backend/tests/OPCUA/Tests/ResolverTest.cls), [PortalPipelineTest.cls](../../backend/tests/OPCUA/Tests/PortalPipelineTest.cls), [Tests/Production.cls](../../backend/tests/OPCUA/Tests/Production.cls), [DESIGN-QA.md](webapp-design-qa.md), and [package.json](../../webapp/package.json).

**Work:**

1. Use a disposable development IRIS environment. These integration tests create/delete classes and modify production configuration; they are not read-only diagnostics.
2. Run existing relevant tests and record the environment, results, and unavailable prerequisites. Do not claim coverage from a test file merely existing.
3. Demonstrate a flat schema, a nested schema, a partial device, a shared schema, both collection modes, reconnect, and secure connections. Capture expected rows and UI behavior.
4. Add focused tests for gaps that the next change could break. Prioritize row mapping and subscription behavior; avoid a blanket testing project.
5. Correct current documentation contradictions in a documentation-only change. Keep historical decisions clearly labeled as history.

In an IRIS terminal in the disposable environment, the existing local suites are invoked as follows:

```objectscript
zn "OPCUA"
write ##class(OPCUA.Tests.ResolverTest).Run("opc.tcp://plc")
write ##class(OPCUA.Tests.PortalPipelineTest).Run("opc.tcp://plc")
```

`ResolverTest` covers parsing, resolution, nested folders, and browse behavior. `PortalPipelineTest` demonstrates Portal-style configuration, adding a device without compiling, partial coverage, and disabled deployment. Its pipeline fixture uses polling; it does not establish subscription correctness.

`DataTest` has different assumptions and mutates the running production. In the inspected `Tests/Production.cls`, its item points to a public server. Existing documentation disagrees about some test prerequisites. Inspect the actual configuration before running it and do not make an unavailable public server the baseline for local refactoring.

For frontend changes, use the existing production build from `webapp/`:

```sh
npm run build
```

This also runs the existing template check. A successful build establishes compilation, not end-to-end behavior. Exercise the changed workflow in the browser as well. Existing `qa-drive.mjs` is a browser-driving helper, not proof of a complete automated regression suite.

**You should be able to answer:** “What evidence shows that temperature reaches the correct SQL column, and what evidence checks subscriptions separately?”

**Done when:** the expected behavior is recorded, relevant baseline failures are understood, and the next stage has meaningful checks.

### Stage 1 — Extract the shared row writer

**Purpose:** make the final step of collection understandable in one place.

**Read:** `OnInit()`, `DiscoverStorageLayout()`, and `OnProcessInput()` in both row-source services; `BuildNestedValues()` in the polling service; `SaveSourcedData()` in `Definition.cls`.

**Work:**

1. Move common layout discovery, nested-value assembly, and row construction into the proposed `RowWriter`.
2. Give each running service its own writer state. A writer for schema A must not accidentally share mutable layout with schema B.
3. Keep the current direct-write method initially. Do not combine deduplication with a database format change.
4. Make both service classes delegate to the same writer. Preserve their class names, adapter declarations, and production settings.
5. Remove the duplicated implementations. Retain a small forwarding helper only where an existing public caller needs it.

One possible conceptual interface is `Initialize(schemaClass)` followed by `WriteBatch(batch, deviceMapping)`. This is illustrative; first preserve the existing mask/path inputs, then simplify their representation in Stage 3.

**Verify:** compare stored output before/after for flat and nested data, multiple devices, partial masks, zero/false, empty/missing values, and timestamps. Exercise the writer from both adapters. Preserve logged save-failure behavior until any change to it is deliberately reviewed.

**You should be able to answer:** “Where would I change how a missing humidity value is stored?” The answer should be one writer, not two services.

**Done when:** the subscription service no longer depends on the polling service, and both use one tested implementation.

**Outcome (implemented):** row assembly now lives only in
`OPCUA.DataSource.RowWriter`. Each service holds its own writer instance, so two
pipelines on different schemas cannot share layout state. The polling service's
`BuildNestedValues()` forwarding helper was removed once it had no callers.
`OPCUA.Tests.MeasurementMetadataTest` covers flat and nested rows, partial masks,
per-measurement isolation, legacy plain schemas, and both transports live against
`plc`.

The stage also resolved the ambiguity that prompted it: the two collection paths
had disagreed about what a stored measurement contains. They no longer do, because
generated schemas use the same `OPCUA.Types.*` measurement classes as the
hand-authored DataSources.

### Stage 2 — Remove misplaced dependencies

**Purpose:** shared low-level behavior should not live in an HTTP-specific class.

**Read:** `Resolver.BrowseIntoMap()` calls `REST.BrowseService.WalkBrowseResults()`. Read that helper and its classification dependencies. Also compare `REST.ClientManager.ApplyManagedCertificates()` with `Adapter.Common.SetupClientSecurity()`.

**Work:**

1. Move native browse decoding and the rules it requires into the proposed `BrowseDecoder`. Let REST turn its output into JSON and let the resolver use the same decoded children.
2. Preserve BrowseName preference, DisplayName fallback, reference filtering, node-class fallback, and child probing. Do not replace this with a simpler parser that drops supported cases.
3. Introduce one connection-options routine for security defaults. It should accept the caller's mode and explicit settings and return resolved options.
4. Keep session lifetimes separate: REST uses a short-lived client; an adapter manages a long-lived connection and retries. Share option resolution, not a single global client.
5. Preserve old public helper entry points where needed, with small delegates rather than copied code.

The two security paths are similar but not identical: REST defaults managed files when its certificate path is absent; the adapter also has `CertificateSource`. Capture these combinations before consolidating them. Reconciliation that changes behavior belongs in a separate, explained decision.

**Verify:** browse classification tests and resolver tests still pass. Test explicit paths, managed defaults, custom client URI, empty managed trust, trusted/untrusted servers, and reconnect. The current compose working tree includes a second secure server; preserve that multi-server trust scenario.

**You should be able to answer:** “Can background collection interpret a browse response without calling a REST class?”

**Done when:** it can, and connection policy has one implementation with explicit caller inputs.

### Stage 3 — Make schema interpretation explicit

**Purpose:** stop several parts of the application independently interpreting the same schema and storage order.

**Read:** `Projection.ProcessObj()`, `Resolver.GetSchemaColumns()`, `MapSerialFolders()`, `DeriveNestingSpec()`, and the layout discovery now owned by the writer.

**Work:**

1. Define a small schema-description result containing columns, relative node paths, nested structure, and the storage mapping required by the current writer.
2. Build it through the proposed `Metadata` owner. Use actual compiled storage positions; do not reproduce storage order by alphabetically sorting names.
3. Let resolver and writer consume that description. Keep node matching separate from storage packing even if both use the description.
4. Keep the existing compile-time projection contract for declarative classes. Route overlapping schema-walking logic through the shared implementation where safe.
5. Treat `^OPCUA.DataSource` as derived metadata, not a second editable schema. Initially retain it. Remove any part only after tracing all callers and preserving compile/uncompile behavior.
6. Make device/result alignment explicit in the resolution output. Add a small conversion to the native list format, rather than spreading more numeric positions through application code.

Avoid adding a persistent cache at this stage. Build the description at initialization as needed. If caching later proves necessary, specify how compilation invalidates it and how a running service notices a changed schema. “It will probably still match” is not a valid cache policy.

**Verify:** a schema with properties whose declaration and storage orders differ; supported nesting; renamed/sanitized property names; partial coverage; manually authored device schemas; both declarative services. Recompile/uncompile temporary schemas and check derived metadata is refreshed/removed appropriately.

**You should be able to answer:** “Which description says that this OPC UA column belongs in this stored property, and when is it rebuilt?”

**Done when:** there is one documented schema interpretation, with binary encoding limited to explicit boundaries.

### Stage 4 — Put schema and pipeline operations in their own homes

**Purpose:** make a configuration change traceable from HTTP request to one operation.

**Read:** `SchemaService.GenerateSchemaClass()`, `Delete()`, `Validate()`; `PipelineService.DeleteSerialSubclasses()`, `Rebind()`, `UpdateDeviceNodePaths()`, `UpdateItemField()`; `DeployService.AddServiceItem()`.

**Work:**

1. Move schema creation, compiled-schema inspection, and owned serial-class deletion into the proposed `SchemaManager`. Schema deletion should not delegate ownership of its artifacts to pipeline management.
2. Consolidate creation, settings updates, category normalization, and start/stop operations under the proposed `Pipeline.Manager`.
3. Share device-validation mechanics between preview, deploy, and rebind. Let each operation retain its documented acceptance policy; a browser preview must not replace runtime resolution.
4. Use one path to open, modify, and save a production item. Rebind currently updates several fields through separate operations; specify what happens if an update fails partway through. Do not claim a transaction covers class compilation or production restart without verifying that boundary.
5. Keep current URLs, accepted request forms, response fields, and public service-class names. REST wrappers should parse input, call an operation, and format a response.
6. Keep health interpretation coherent. Reuse its rules; do not infer successful collection just because a service is enabled.

There is no need to add HTTP calls between backend classes. A schema manager calls an ordinary helper method when checking production references.

**Verify:** create, list, inspect, validate, deploy-disabled, start, stop, rebind, category/label editing, delete pipeline while preserving data, and reject deletion of an in-use schema. Use both UI and direct API calls, then confirm Portal edits are still reflected. Check multiple pipelines sharing a schema.

**You should be able to answer:** “Where do pipeline settings change, and why does deleting a pipeline leave its schema intact?”

**Done when:** lifecycle operations have obvious owners and REST no longer contains their main implementation.

### Stage 5 — Simplify frontend workflows without changing the product

**Purpose:** each page should be understandable as a user task, without reading hundreds of lines of unrelated state and rendering code.

**Read:** [device-binding.component.ts](../../webapp/src/app/pages/device-binding/device-binding.component.ts), [schema-builder.component.ts](../../webapp/src/app/pages/schema-builder/schema-builder.component.ts), [pipelines-dashboard.component.ts](../../webapp/src/app/pages/pipelines-dashboard/pipelines-dashboard.component.ts), and the shared tree/settings files in section 4.

**Work, one screen at a time:**

1. Start with binding. Extract device-path parsing into pure functions: the same input always produces the same output, with no HTTP call or UI mutation.
2. Give validation requests, pending state, and cached coverage one local owner. It can be a small page-scoped service using the signals already in use; a new global state library is unnecessary.
3. Tie validation results to the schema and connection that produced them. Cancel or ignore old requests when either changes, so a late result cannot appear under a newly selected server.
4. Use complete node identity when constructing internal keys: server context, namespace, identifier type, and identifier. Review this carefully because current helper keys and some responses omit parts. Preserve public payload compatibility while making internal ownership explicit.
5. Separate the device list, collection settings, and category/label editor where they form clear UI sections. Keep create/edit orchestration in the page.
6. For schema building, reuse the existing tree's loading mechanics where practical, or extract their shared behavior. Preserve choosing a device root and relative column paths; do not replace the tree with a universal component full of mode flags.
7. For the dashboard, keep loading/actions in the page and put repeated status/presentation rules together. Preserve real health, counters, display name versus identity, grouping, and refresh behavior.
8. Apply the same ownership principle to settings and node detail: forms own edits; API/config services own persistence; node freshness and automatic reads have one lifecycle with cleanup on navigation.
9. Tighten API types around actual responses. Replace the broad `Pipeline` index signature and scattered `any` where the response shape is known. Keep an explicit compatibility conversion for supported older payloads.
10. Normalize old browser configuration once when loading it. Use one current internal profile model while continuing to read existing saved formats.

Moving templates to `.html` files is optional for readability. **The current [check-templates.mjs](../../webapp/tools/check-templates.mjs) scans inline TypeScript templates.** Extend it to check external templates in the same change; otherwise the build can go green merely because the guard stopped seeing the markup. Update file-based baselines without allowing additional violations.

Frontend input checks improve feedback. Backend checks still own acceptance because callers can bypass the UI. Share test examples across the two languages instead of creating a cross-language validation framework.

**Verify:** build, then exercise the complete create-schema → bind → start → observe → edit → stop flow. Check direct edit URLs, empty states, validation failures, rapid server switching, late responses, multiple servers with similar node IDs, saved profile migration, keyboard controls, and timer/request cleanup. Preserve appearance unless a visual change is explicitly part of the task.

**You should be able to answer:** “Where is the device list parsed, where does server validation happen, and what prevents old results from replacing current results?”

**Done when:** each answer has a clear location, with no new global state framework or duplicate browsing implementation.

### Stage 6 — Decide whether simpler persistence can replace manual row storage

**Purpose:** potentially remove the most specialized code, after its behavior is understood.

**Read:** `Definition.SaveSourcedData()`, the shared writer, the metadata description, and generated flat/nested schemas. Remember that the declarative path has different value wrappers.

This is a bounded experiment followed by a decision, not a promise to change the write engine.

Compare the current writer with **one** straightforward candidate: creating the persistent object, assigning its properties and nested objects, and saving it through IRIS. If SQL insertion is the better fit, evaluate that instead; do not build multiple permanent implementations just to keep options open.

The experiment must check more than rows per second:

| Check | Why it matters |
|---|---|
| SQL and object readback match | Equivalent-looking rows can still differ in nested object behavior. |
| Missing/empty/zero/false behavior matches | Type conversion can change a value during a normal save. |
| Supported arrays, strings, timestamps, and typed wrappers survive | Generated and declarative schemas do not use identical value representations. |
| Existing rows remain readable | A code simplification must not require discarding historical data. |
| Save validation, indexes, and callbacks are understood | The existing direct-global path and ordinary object saving need not have identical side effects. |
| Sustained throughput and latency meet actual needs | One fast test cycle does not prove the subscription queue can keep up. |
| Reconnect and concurrent collectors behave correctly | Several services can target a shared schema/table. |

Record realistic devices, columns, collection rate, hardware, and required throughput before deciding. No such performance target has been established by this review.

If ordinary persistence meets the behavior and performance requirements, adopt it and delete obsolete packing/layout code where no remaining caller needs it. If it does not, retain the optimized writer behind its single clear boundary. The earlier stages still provide most of the maintainability benefit.

Keep generated classes and nested structure either way. Their discoverability in the Portal and their SQL/object interface are part of the product.

**You should be able to answer:** “Why does this project need manual storage packing, or what evidence allowed us to remove it?”

**Done when:** one documented decision selects the maintained implementation; an indefinite feature flag with two competing writers is not the final architecture.

### Stage 7 — Finish the consolidation

**Purpose:** ensure temporary scaffolding does not become the next source of complexity.

1. Remove private implementations superseded by shared owners. Keep public compatibility delegates only where there is a real caller or compatibility commitment.
2. Update the current architecture guide and README to describe the actual flows. Keep this document as the redesign rationale, with completed stages marked.
3. Update import/build tooling and native-install references if any public paths moved. Avoid package-wide renames just for cosmetic consistency.
4. Document how to refresh ObjectScript source in development. The inspected Docker image copies source during build; an edit on disk does not update the running IRIS class automatically.
5. Separate runtime prerequisites from test/demo prerequisites in instructions. Preserve supported mock/secure server scenarios and certificate volumes; do not remove them to reduce a container count.
6. Run the relevant complete regression set and repeat the learning questions without relying on outdated documents.

**Done when:** code, tests, and documentation tell the same story, and the temporary duplicate paths are gone.

## 8. How to work with an AI assistant while staying in control

Use a small implementation request with a visible boundary. For example:

> Implement Stage 1 of `docs/design/redesign-plan.md` only. Before editing, explain the current row-writing path using one concrete two-device example. Name the files and methods you will change. Preserve the native payload, stored data format, timestamps, missing-value behavior, service class names, and both adapters. Extract the shared writer and remove the duplicated implementation. Run the relevant checks. Finish with a before/after explanation and a short reading order for the diff. Do not start the next stage.

For each completed stage, ask for these five things:

1. **The behavior:** what the application does before and after, using a small example.
2. **The ownership change:** which file now owns the rule, and which duplicate code disappeared.
3. **The evidence:** actual commands/results, browser observations, and anything not exercised.
4. **The compatibility:** which names, request formats, table structures, and saved settings remain stable.
5. **The reading exercise:** two or three methods you can open to verify the explanation yourself.

If a helper merely forwards a call without adding a useful boundary, ask why it exists. If a proposal creates many new abstractions, ask which existing concepts they replace. If it cannot identify anything being removed or clarified, it may be increasing complexity.

Do not accept “all tests pass” when the changed behavior has no relevant test or live demonstration. Equally, do not require a new test for every moved line. The purpose is to verify behavior at the boundaries that could break.

## 9. Changes deliberately excluded from the default redesign

| Idea | Why it is excluded | When to revisit |
|---|---|---|
| Flatten nested schemas | Changes object structure and may affect consumers even if SQL columns look similar. | Only after identifying consumers, choosing compatibility behavior, and designing a data migration. |
| Delete declarative services/types/examples | Removes an existing authoring mode and native type coverage. | Only as an explicit product deprecation, not cleanup. |
| Replace IRIS productions with custom workers | Would require rebuilding scheduling, configuration, monitoring, and Portal integration. | Only if IRIS interoperability ceases to be a requirement. |
| Rewrite the native client | Its protocol behavior and binary interface are a separate concern. | Only for a demonstrated capability or compatibility need. |
| Replace generated schemas with one generic JSON/value table | Changes the typed SQL and object interface. | Only if that interface is explicitly no longer needed. |
| Add a global frontend state framework | Adds a new concept and migration without a demonstrated need. | Only if local signals and shared services prove insufficient. |
| Introduce backend-stored connection profiles during cleanup | Changes ownership and deployment semantics of browser settings. | As a separately designed product feature. |
| Remove old API forms immediately | External callers may use them; the UI is not the only interface. | After callers are inventoried and compatibility is deliberately retired. |

The goal is to remove duplicated decisions and unnecessary representations while retaining capabilities. Security behavior, type support, and error handling are not excess complexity merely because they take many lines.

## 10. Migration and rollback

For Stages 1–5, prefer internal substitutions that preserve public class names, schema/table storage, production settings, URLs, and saved browser formats. This keeps rollback mostly a matter of restoring the previous application code and refreshing the environment.

Use a separate branch and small commits. Preserve unrelated working-tree changes. Before touching a stateful environment, export the relevant generated class definitions and production configuration and take an appropriate data backup. Certificate identity and trust files need to survive environment rebuilds; a code rollback does not recreate them.

Schema compilation, data writes, filesystem changes, and production restarts do not all have the same rollback mechanism. Document those boundaries for any stage that touches them. Reverting a Git commit does not undo data changes.

Stage 6 should first compare writers using isolated fixtures. Do not write the same incoming batch twice into a live table for comparison. If the candidate changes storage format or externally visible behavior, stop treating it as an internal replacement and design the migration explicitly before adoption.

## 11. How much improvement to expect, and how to measure it

The inspected production sources contain approximately **9,789 backend lines** and **7,184 frontend application TypeScript lines**, including inline templates, comments, and blank lines. Backend counting includes `.cls` and `.inc` under `OPCUA`, excluding `Tests`; it does not include examples, installer code, bundled C, dependencies, or generated runtime classes. The frontend figure excludes styles and other tooling.

The earlier estimates were rough net source reductions, not measured refactoring results:

| Scope | Rough cumulative reduction | Qualification |
|---|---:|---|
| Shared implementations and straightforward cleanup | 400–700 lines | New helper boundaries and comments can offset some deletions. |
| Also centralize metadata and successfully simplify persistence | 800–1,400 lines | Depends on how much manual packing can actually be removed. |
| Also flatten generated schemas | 1,200–2,200 lines | Outside this functionality-preserving default plan. |

Moving a template to HTML must not count as deleting it. Count both formats afterward. Track production code, tests, and documentation separately: useful new tests or explanations can increase repository size while making the system easier to maintain.

Use these stronger measures of completion:

- One row-building implementation serves both multi-device collection modes.
- One owner interprets the schema/storage mapping; consumers use its result.
- The runtime resolver does not depend on REST classes.
- Connection-option policy has one implementation with explicit inputs.
- Schema and pipeline lifecycle responsibilities have clear owners.
- All current UI workflows, supported data shapes, and Portal configuration remain demonstrably usable.
- Old requests cannot update the wrong frontend context after navigation or server changes.
- A reader can trace schema creation, binding, and one collected row using this document and a small set of named methods.

## 12. The first concrete milestone

Start with **Stage 0, followed by Stage 1**. This yields a small, meaningful change: one shared row writer with unchanged behavior.

Before approving that milestone as complete, you should be able to open the two row-source services, see that they delegate to the same writer, and explain how three returned values become two rows when one device is missing a column.

That is the pattern for the entire redesign: understand one behavior, give it one clear owner, prove it still works, and then move on.
