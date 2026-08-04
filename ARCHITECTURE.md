# IRIS OPC UA Adapter -- Architecture Summary

This document explains how the ObjectScript (IRIS-level) code in this project works, how the pieces connect, and how data flows from an OPC UA server into IRIS database tables. Domain-specific terms are explained inline.

---

## Table of Contents

1. [The Big Picture](#1-the-big-picture)
2. [Loading the C++ Library](#2-loading-the-c-library)
3. [The Client: Talking to OPC UA Servers](#3-the-client-talking-to-opc-ua-servers)
4. [The Type System: How OPC UA Values Become IRIS Data](#4-the-type-system-how-opc-ua-values-become-iris-data)
5. [DataSource Classes: Auto-Generated Tables](#5-datasource-classes-auto-generated-tables)
6. [The Projection System: Compile-Time Magic](#6-the-projection-system-compile-time-magic)
7. [The REST API: How the Web App Talks to IRIS](#7-the-rest-api-how-the-web-app-talks-to-iris)
8. [Browsing an OPC UA Server](#8-browsing-an-opc-ua-server)
9. [Deploying a Pipeline](#9-deploying-a-pipeline)
10. [The Production: IRIS's Background Job Engine](#10-the-production-iriss-background-job-engine)
11. [Adapters: The Connection Managers](#11-adapters-the-connection-managers)
12. [Services: The Data Processors](#12-services-the-data-processors)
13. [Polling vs Subscriptions](#13-polling-vs-subscriptions)
14. [v2 Pipelines: Multiple Devices, One Table](#14-v2-pipelines-multiple-devices-one-table)
15. [Nesting: Handling Folder Hierarchies](#15-nesting-handling-folder-hierarchies)
16. [Managing Pipelines After Deployment](#16-managing-pipelines-after-deployment)
17. [Security and Certificates](#17-security-and-certificates)
18. [Global Variables: The Shared State](#18-global-variables-the-shared-state)
19. [End-to-End Data Flow](#19-end-to-end-data-flow)
20. [Class Dependency Map](#20-class-dependency-map)

---

## 1. The Big Picture

The project bridges two worlds:

- **OPC UA servers** -- industrial devices (PLCs, sensors, SCADA systems) that expose their data through the OPC UA protocol (an industry-standard protocol for machine-to-machine communication in automation).
- **InterSystems IRIS** -- a database platform with a built-in integration engine called "Ensemble" (now "Interoperability") that can run background jobs, manage message routing, and persist data.

The bridge works like this:

```
OPC UA Server (industrial device)
       |
       | OPC UA protocol (TCP)
       v
C++ Library (open62541 + our wrapper)
       |
       | $ZF callout (IRIS's way to call C/C++ functions)
       v
ObjectScript Client (OPCUA.Client)
       |
       | Method calls
       v
Ensemble Adapters & Services (background jobs)
       |
       | Object persistence
       v
IRIS SQL Tables (queryable data)
```

The C++ library handles all the low-level OPC UA protocol work. Our ObjectScript code wraps it, manages connections, processes results, and stores data into SQL-queryable tables.

---

## 2. Loading the C++ Library

**Key files:** `OPCUA/Utils.cls`, `OPCUA/Constants.inc`

Before any OPC UA operation can happen, IRIS needs to load the C++ shared library (`irisopcua.so` on Linux, `IrisOPCUA.dll` on Windows) into memory. This is handled by `OPCUA.Utils.Initialize()`.

**How it works:**

1. Check if the library is already loaded (stored in a process-level variable `%ZUtilsIrisOpcuaLibraryId`)
2. Find the library file: first check a global variable (`^OPCUA.Library.Pathname`), then try default filenames
3. Load it using `$ZF(-4, 1, pathname)` -- this is IRIS's built-in function for loading shared libraries (DLL/SO files). It returns a "library ID" (just a number) that you use for all subsequent calls
4. Validate it works by calling a simple test function
5. Store the library ID for reuse

**The constants file** (`OPCUA/Constants.inc`) defines all the "function ordinals" -- numbered indices (1 through 52) that map to specific C++ functions. When you call `$ZF(-5, libraryId, 3, ...)`, that `3` means "call the third function in the library." The constants give them readable names:

```objectscript
#define zfConnectB        3    ;; Connect to server
#define zfDisconnectB     4    ;; Disconnect
#define zfBrowse          5    ;; Browse child nodes
#define zfReadBulkSetupC  21   ;; Set up a bulk read query
#define zfReadBulkPollC   24   ;; Execute the bulk read
```

The file also defines enums for OPC UA concepts like data types (Boolean=0, Int32=6, Double=11, String=12, etc.), security modes (None=1, SignAndEncrypt=3), and node ID types (Numeric=0, String=3).

---

## 3. The Client: Talking to OPC UA Servers

**Key file:** `OPCUA/Client.cls`

`OPCUA.Client` is the central class that wraps every C++ function call. Think of it as the ObjectScript-side remote control for the C++ library.

### Lifecycle

```
Create a new client object
  -> Initialize() loads the C++ library if needed
  -> Create() allocates a C++ client handle (a pointer to a C++ object)
  -> SetupClient() configures timeouts, security mode, certificates
  -> Connect(url) establishes a TCP session with the OPC UA server
  -> ... do work (read, write, browse, subscribe) ...
  -> Disconnect() closes the session
  -> OnClose() / Destroy() frees the C++ client handle
```

### Key operations

| What | Method | What it does |
|------|--------|-------------|
| **Browse** | `Browse()` | Lists the children of a given node in the OPC UA server's address space (like listing files in a directory) |
| **Set up bulk read** | `ReadBulkSetupC()` | Tells the C++ library "I want to read these specific nodes" -- creates a reusable query handle |
| **Execute bulk read** | `ReadBulkPollC()` | Executes the query -- returns all values at once as a `$ListBuild` list (IRIS's binary list format, similar to a tuple) |
| **Subscribe** | `CreateSubscriptionSetB()` | Tells the OPC UA server "notify me when these values change" |
| **Poll subscription** | `PollSubscriptionSet()` | Asks "any changes since last time?" and gets back the changed values |
| **Single read** | `ReadValueAttribute()` | Reads one node's value right now (used by REST API, not by pipelines) |
| **Single write** | `WriteValueAttribute()` | Writes a value to one node |

### How C++ calls work ($ZF)

Every method in `OPCUA.Client` ultimately calls `$ZF(-5, libraryId, functionOrdinal, arg1, arg2, ...)`. The arguments and return values are passed as `$ListBuild` lists -- IRIS's internal binary format for ordered lists of values. The C++ side knows how to parse these using the "callin helper" library.

**Error handling:** Every C++ call returns a result whose first element is an error code. `DecodeError()` parses this: error code 0 means success; anything else gets mapped to an error type (Info, Application, Callin, OPCUA protocol, Client-side, Server-side) with a human-readable message.

---

## 4. The Type System: How OPC UA Values Become IRIS Data

**Key files:** `OPCUA/Types/*.cls`

OPC UA values aren't just raw numbers -- they come with timestamps (when the source produced the value, when the server processed it) and a status code (quality indicator). Our type system wraps these.

### Base class: `OPCUA.Types.AbstractDataValue`

Every OPC UA value in IRIS is stored as a "serial object" (`%SerialObject` -- an object that serializes into a compact binary format for storage inside a parent object's row). It contains:

- `SourceTimeStamp` -- when the device generated the value
- `ServerTimeStamp` -- when the OPC UA server processed it
- `Status` -- OPC UA status code (0 = good)

### Concrete types

Each extends AbstractDataValue and adds a `Value` property:

| Class | Value type | Example |
|-------|-----------|---------|
| `BooleanDataValue` | %Boolean | true/false |
| `IntegerDataValue` | %Integer | 42 |
| `FloatDataValue` | %Float | 3.14 |
| `DoubleDataValue` | %Double | 3.14159265 |
| `StringDataValue` | %String | "Hello" |
| `TimeStampDataValue` | %TimeStamp | "2026-04-14 12:34:56" |
| `ArrayDataValue.Boolean` | list of %Boolean | [true, false, true] |
| `ArrayDataValue.Integer` | list of %Integer | [1, 2, 3] |
| `Multidimensional` | %List + dimensions | matrices |

### Type inference

When generating a DataSource class, the system reads a sample value from the OPC UA server and guesses the right type:

1. Looks like `YYYY-MM-DD HH:MM:SS`? -> `TimeStampDataValue`
2. All digits (with optional minus)? -> `IntegerDataValue`
3. Has decimal point or scientific notation? -> `DoubleDataValue`
4. Is a `$List` (binary list)? -> appropriate `ArrayDataValue`
5. Fallback -> `StringDataValue`

This happens in `OPCUA.DataSource.Generator.InferTypeFromValue()`.

---

## 5. DataSource Classes: Auto-Generated Tables

**Key files:** `OPCUA/DataSource/Definition.cls`, `OPCUA/DataSource/Generator.cls`, `OPCUA/REST/DeployService.cls`

This is one of the most important concepts in the system. A **DataSource class** is a dynamically generated ObjectScript class that:

1. Extends `%Persistent` (meaning IRIS auto-creates a SQL table for it)
2. Extends `OPCUA.DataSource.Definition` (our base class with OPC UA metadata)
3. Has properties that map to specific OPC UA nodes

### What a generated class looks like

When you select nodes like "Temperature" and "Humidity" from an OPC UA server and deploy a pipeline, the system generates something like:

```objectscript
Class OPCUA.DS.MyPipeline Extends (%Persistent, OPCUA.DataSource.Definition)
{
  Parameter OPCUADATASOURCE = "MyPipeline";

  Property Temperature As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "Temperature", OPCUANAMESPACE = 2);
  Property Humidity As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "Humidity", OPCUANAMESPACE = 2);
}
```

Each property has parameters (metadata annotations) that tell the system which OPC UA node it maps to:
- `OPCUANODENAME` -- the node's identifier in the OPC UA server
- `OPCUANAMESPACE` -- the OPC UA namespace index (servers organize nodes into numbered namespaces; namespace 0 is the standard OPC UA namespace, higher numbers are vendor-specific)
- `OPCUAATTRIBUTEID` -- which attribute to read (default 13 = Value; OPC UA nodes have many attributes like DisplayName, Description, etc.)

### How classes are generated

DataSource classes are created in **two ways**, depending on where they come from:

**Hand-authored (declarative):** the Examples and the `OPCUA.Tests` harness ship `.cls` files that extend `(%Persistent, OPCUA.DataSource.Definition)` and declare one typed `OPCUA.Types.*` property per node. These run under `TCPPollingService` / `TCPSubscriptionService` and exist to validate the C++ type marshalling. They are *not* generated.

**Generated (device schemas):** `SchemaService.GenerateSchemaClass()` builds the class **in memory** via the `%Dictionary` API (`%Dictionary.ClassDefinition` + `%Dictionary.PropertyDefinition`), then calls `$System.OBJ.Compile()`. Nested folders are emitted first as `%SerialObject` subclasses (`GenerateSerialClasses()`). Columns are flattened to plain IRIS types (`MapToPlainType()`), not the `OPCUA.Types.*` wrappers.

Generated schemas extend `OPCUA.DataSource.DeviceSchema` (itself an abstract subclass of `Definition`). That common superclass is what lets the `DataSourceClass` production setting render as a dropdown of exactly the classes the row-source services can consume — the hand-authored Examples don't appear in it.

Crucially, schema generation **has no production side effects and stores no device information**. A schema describes a device *type*: the column names and their types. Which concrete devices get read is a separate, later decision — see [section 14](#14-v2-pipelines-multiple-devices-one-table).

### What happens when a class compiles

When IRIS compiles a DataSource class, two things happen automatically:
1. **IRIS creates a SQL table** -- each property becomes a column. So `OPCUA.DS.MyPipeline` becomes the SQL table `OPCUA_DS.MyPipeline` with columns `Temperature`, `Humidity`, etc.
2. **The Projection fires** -- more on this next.

---

## 6. The Projection System: Compile-Time Magic

**Key file:** `OPCUA/DataSource/Projection.cls`

A "projection" in IRIS is a class that gets a callback whenever another class that references it is compiled. `OPCUA.DataSource.Definition` declares `Projection P As OPCUA.DataSource.Projection`, so every time a DataSource class compiles, `Projection.CreateProjection()` runs automatically.

### What the Projection does

It builds a "configuration spec" -- a compact binary description of what OPC UA nodes this DataSource needs -- and stores it in a global variable.

**Step by step:**

1. Read the class's `OPCUADATASOURCE` parameter (the human-friendly name)
2. Walk through every property in the class
3. For each property, extract:
   - The OPC UA node name (`OPCUANODENAME`)
   - The namespace (`OPCUANAMESPACE`)
   - The attribute ID (`OPCUAATTRIBUTEID`, usually 13 for Value)
   - The type classification: is it a simple value (type code 1), an OPCUA.Structure (type code 2), or a nested serial object (recurse into its properties)?
4. Build a spec entry: `$LB(typeCode, propertyPath, namespace, nodeName, attributeId)`
5. Store everything in `^OPCUA.DataSource(className)`:
   ```
   $LB(dataSourceName, storageGlobal, $LB("", spec1, spec2, spec3, ...))
   ```

**Why this matters:** The adapters and services read this spec at startup to know which OPC UA nodes to poll or subscribe to. The Projection is the bridge between the class definition (which is static metadata) and the runtime behavior (which needs a compact, machine-readable description).

The Projection also generates the `SaveSourcedData()` class method -- this is a code-generated method (written into the class programmatically) that knows how to take a `$ListBuild` list of values and persist them as a row in the table. It's essentially: allocate a new row ID, set each property from the corresponding list position, save.

---

## 7. The REST API: How the Web App Talks to IRIS

**Key files:** `OPCUA/REST/Handler.cls`, `OPCUA/REST/ClientManager.cls`, `OPCUA/REST/*.cls`

The Angular web app (the OPC UA console) communicates with IRIS through a REST API. IRIS has built-in REST support through `%CSP.REST` (CSP = Cache Server Pages, IRIS's web framework).

### The Handler (router)

`OPCUA.REST.Handler` extends `%CSP.REST` and defines URL routes:

| URL Path | Method | What it does |
|----------|--------|-------------|
| `/ping` | GET | Health check -- returns timestamp |
| `/browse` | GET/POST | Browse OPC UA server nodes |
| `/read` | GET/POST | Read a single node's value (and infer its type) |
| `/generate` | GET/POST | Generate a DataSource class from selected nodes |
| `/test` | GET/POST | Test connection to an OPC UA server |
| `/schemas` | GET | List device schemas, with the pipelines using each |
| `/schemas` | POST | Create a device schema (no production side effects) |
| `/schemas/:name` | GET | One schema, including its column list |
| `/schemas/:name` | DELETE | Delete a schema — refuses while a pipeline uses it |
| `/schemas/:name/validate` | POST | Dry-run a device list against a schema |
| `/deploy` | POST | Bind devices to an existing schema → a pipeline, **created stopped** |
| `/pipelines` | GET/POST | List all deployed pipelines |
| `/pipelines/rebind` | POST | Change a pipeline's device list |
| `/pipelines/toggle` | POST | Start/stop a pipeline — the only route that starts collection |
| `/pipelines/delete` | POST | Delete a pipeline (keeps its schema) |

The two halves are deliberately separate: `/schemas` creates a reusable device *type*, and `/deploy` binds concrete devices to one. A schema can exist with no pipeline, and several pipelines can share one schema.

Each route maps to a method in Handler that delegates to a specialized service class.

### Request parsing

`Handler.GetRequestParams()` tries to read a JSON body first, then falls back to query parameters. This allows both `POST` with JSON body and `GET` with URL parameters to work.

### Response format

Every response follows the same envelope:

```json
{
  "status": "ok",
  "data": { ... the actual response ... }
}
```

or on error:

```json
{
  "status": "error",
  "error": "Human-readable error message"
}
```

### ClientManager: per-request connections

`OPCUA.REST.ClientManager` is a helper that creates a fresh OPC UA client for each REST request:

1. `ExtractConnectionParams()` -- pulls `url`, `securityMode`, `username`, `password`, cert paths from the request JSON
2. `Connect()` -- creates an `OPCUA.Client`, configures security, connects to the server
3. Returns the client by reference so the service class can use it
4. `Disconnect()` -- safely closes the connection (swallows errors since the request is done)

This means every REST call (browse, read, test) opens a fresh OPC UA connection, does its work, and closes it. The long-lived connections are managed by the Ensemble adapters (see below).

---

## 8. Browsing an OPC UA Server

**Key file:** `OPCUA/REST/BrowseService.cls`

When you expand a node in a tree view, the frontend calls `/browse` with the node's coordinates (namespace + node ID). Here's what happens:

1. `BrowseService.Browse()` receives the request
2. Creates a temporary OPC UA client via `ClientManager.Connect()`
3. Calls `Client.Browse(nodeTypes, namespaces, nodeIds)` -- this calls the C++ library, which sends an OPC UA BrowseRequest to the server
4. The C++ library returns a list of "references" (children of the browsed node)
5. `ParseBrowseResults()` classifies each child. The **`nodeClass` the server itself reports** decides the coarse kind — Object, Variable, Method, View — because that is the server's own answer and no heuristic can beat it. TypeDefinition and reference type then refine it where this UI needs finer categories than OPC UA has:
   - **Object** → `folder` if the type definition is FolderType (ID 61), or if there's no type definition and the reference is "Organizes"; otherwise `object`
   - **Variable** → `property` if the reference type is "HasProperty" or the type definition is PropertyType (68); otherwise `variable`
   - **Method** → `method`. This is the case inference could never get right: methods arrive over ordinary `HasComponent` references, so before nodeClass was available every one of them was mislabelled `object`
   - **View** → `folder`, since to someone browsing it behaves as one
6. **Probes one level ahead** (`ProbeChildCounts()`) to find out which children are actually expandable, then returns a JSON array with each child's display name, namespace, node ID, category, raw `nodeClass`, and `hasChildren`

### Why expandability needs a second browse

A browse response says what a node **is**, never whether it **has children** — so `hasChildren` can only be guessed from the category, and the guess is optimistic: every variable is marked expandable, because some variables genuinely do carry child properties (`EURange` under an `AnalogItemType`). On a server whose tags are bare — which the `plc` mock is — that draws an expand arrow on every leaf, and clicking it opens nothing.

`Client.Browse` takes *lists* of node IDs, so the fix is one extra browse covering **all** the siblings at once: count each one's children, keep the counts, throw the grandchildren away. Cost is **2 round trips per expand, not N+1** (~7 ms for 19 children against the local mock). Depth stays lazy — this looks exactly one level past what's being rendered, never deeper, and never pre-walks the tree.

Two details carry the correctness:

- **The count must apply the same non-child filter as the walk.** Every bare variable carries a `HasTypeDefinition` reference, so a naive count returns 1 and marks every leaf expandable — the original bug, reintroduced. `IsNonChildReference()` exists so `WalkBrowseResults()` and `CountChildReferences()` cannot drift apart.
- **Results are positional.** If the server returns a count that doesn't match what was asked, the pairing can't be trusted, so every guess is left alone rather than risk mislabelling a different node.

It's best-effort and opt-out (`probeChildren: 0`). When the probe is skipped or fails, `CategoryHasChildren()`'s guess stands — deliberately optimistic, since an arrow that opens to nothing is a smaller failure than a subtree the user cannot open at all.

`nodeClass` is optional, not required. The C++ layer exports it at browse reference position `[6]` (`UACExport::UA2CL_ReferenceDescription`), but prebuilt binaries older than that export send an empty value — so an empty `nodeClass` falls back to the pure TypeDefinition inference, which is what shipped before. `OPCUA.Tests.ResolverTest` asserts both that a live server populates it and that the derived categories are the ones the webapp expects, so a stale `.so` shows up as a test failure rather than as a subtly wrong tree.

The webapp uses this to render the expandable trees: the node explorer, the schema builder's column picker, and the device picker on the binding screen.

---

## 9. Deploying a Pipeline

**Key file:** `OPCUA/REST/DeployService.cls`

Deploying **generates nothing**. By the time you deploy, the schema class already exists (created via `/schemas`), so a deploy is just "bind these devices to that schema and wire it into the production". `DeployService.Deploy()` requires a `schemaClass` and forwards to `BindExistingSchema()`.

That is why adding a second pipeline over an existing schema costs one config item and **no compilation**.

### Binding devices to a schema

1. **Validate the schema:** it must exist, be compiled, and be an `OPCUA.DataSource.DeviceSchema` subclass.

2. **Parse the device list** (`Resolver.ParseDeviceNodePaths()`): newline-separated nodepaths, so an unusable entry is reported per-line now rather than failing at connect time.

3. **Ensure the production exists:** create `OPCUA.Pipeline.Production` (an empty production class) on first deploy if missing.

4. **Add a service item** (`AddServiceItem()`):
   - Create an `Ens.Config.Item`, set its class to `OPCUA.Service.TCPPollingRowSourceService` or `OPCUA.Service.TCPSubscriptionRowSourceService` (chosen by `mode`)
   - Configure settings: `DataSourceClass`, **`DeviceNodePaths`**, `URL`, poll/subscription intervals, security parameters
   - Add it with **`Enabled = 0`**, save the production, call `SaveToClass()`

5. **Stop.** The production is deliberately **not** started, and the item is created switched off.

**A deploy is a pure configuration write.** Nothing connects to the server and no rows are written until the pipeline is explicitly started — `PipelineService.Toggle()` from the dashboard's play button, or the Enabled checkbox in the Portal. Deploying and collecting are separate decisions: the operator gets to look the pipeline over first, and a mistaken bind costs nothing but a delete.

`BindExistingSchema()` therefore returns `started: 0` and `enabled: 0` always. `Toggle()` is the only path that starts a production from the API, and it starts the production if it isn't running.

**The device list is an ordinary production setting.** It lives in the config item, which means it is visible and editable in the Management Portal — adding a device is a one-line edit there, needing no regeneration and no recompile. There is no metadata global to keep in sync.

> The hand-authored Examples/Tests classes use `TCPPollingService` / `TCPSubscriptionService` instead — see [section 12](#12-services-the-data-processors).

---

## 10. The Production: IRIS's Background Job Engine

**Key concept:** In IRIS Interoperability (Ensemble), a **production** is a named collection of "business hosts" (services, processes, operations) that run as background jobs. Think of it as a supervisor that manages multiple workers.

Our project uses a single production: `OPCUA.Pipeline.Production`. Every deployed pipeline becomes one "business service item" in this production.

**Production lifecycle:**
- `Ens.Director.StartProduction("OPCUA.Pipeline.Production")` -- starts all enabled items
- `Ens.Director.UpdateProduction()` -- picks up configuration changes (new items, changed settings) without restarting everything
- `Ens.Director.StopProduction()` -- stops all items
- Each item can be individually enabled/disabled

**Production configuration** is stored as XML inside the class's `XData ProductionDefinition` block. When we modify the production programmatically (via `Ens.Config.Production` API), we call `SaveToClass()` to write changes back to this XData block.

Each service item has:
- A **Name** (e.g., "MyPipelineData")
- A **ClassName** (which service class to run)
- An **Enabled** flag
- A collection of **Settings** (key-value pairs like `URL=opc.tcp://plc:4840`, `CallInterval=5`, `DataSourceClass=OPCUA.DS.MyPipeline`)

---

## 11. Adapters: The Connection Managers

**Key files:** `OPCUA/Adapter/Common.cls`, `OPCUA/Adapter/TCPPollingInboundAdapter.cls`, `OPCUA/Adapter/TCPSubscriptionInboundAdapter.cls`

An "adapter" in Ensemble is the component that handles the actual external communication. A "service" (see next section) delegates the I/O work to its adapter.

### Common adapter (`OPCUA.Adapter.Common`)

This is the base class that both adapters extend. It manages:

- **Client lifecycle:** Creates an `OPCUA.Client` instance, configures it, connects to the OPC UA server
- **Connection settings:** URL, security mode, certificates, credentials, timeouts
- **Reconnection logic:** If the connection drops:
  - Check if we've exceeded `ConnectionRetryTimeout` (default 600 seconds)
  - If `AlwaysConnect=1`, keep retrying with warnings
  - If `AlwaysConnect=0`, give up and stop the adapter
  - If `ResetClientFlag` is set, destroy the old client object entirely and create a fresh one

### Configuring a pipeline from the Management Portal

`Common` declares a `SETTINGS` parameter, which is what makes every pipeline
configurable in the Production Configuration UI with no webapp involved:

```objectscript
Parameter SETTINGS = "...,DataSourceClass:Data:selector?context={Ens.ContextSearch/SubclassOf?class=OPCUA.DataSource.DeviceSchema},DeviceNodePaths:Data,..."
```

- **`DataSourceClass`** renders as a **dropdown** of available schemas, populated by
  `Ens.ContextSearch.SubclassOf` from the common superclass. Note the parameter is
  named `class` (not `super`), and it already excludes abstract classes, so the
  `DeviceSchema` base itself never appears.
- **`DeviceNodePaths`** is a free-text list, one device per line.

Two consequences worth knowing:

- A pipeline can be built **entirely from the Portal** — add a service item, pick a
  schema from the dropdown, type the device roots, start. No REST call required.
- `SETTINGS` must be a **single line**; a multi-line concatenation does not parse.
  Entries are also first-wins per name, so a `-Name` suppression entry earlier in
  the string removes that setting outright.

### Polling adapter (`TCPPollingInboundAdapter`)

Used for periodic reading of values (like checking a sensor every 5 seconds).

**Initialization:**
1. `Configure(specification)` -- receives the config spec (from the Projection) that describes which nodes to read
2. During `Connect()`, calls `Client.ReadBulkSetupC(spec)` -- this tells the C++ library "prepare to read these nodes." Returns a query handle (a reusable reference to this prepared query)

**Each poll cycle (OnTask):**
1. Called automatically by Ensemble at the configured interval (`CallInterval`)
2. Calls `Client.ReadBulkPollC(queryHandle)` -- executes the prepared query
3. Gets back a `$ListBuild` list containing all values with timestamps
4. Passes the result to the business service via `BusinessHost.ProcessInput()`
5. If there's an error, checks client state and decides whether to retry or reconnect

### Subscription adapter (`TCPSubscriptionInboundAdapter`)

Used for change-based data collection (the OPC UA server pushes changes to us).

**Initialization:**
1. During `Connect()`, calls `Client.CreateSubscriptionSetB(spec, publishingInterval, ...)` -- this tells the OPC UA server "monitor these nodes and notify me of changes"
2. Additional settings:
   - `RequestedPublishingInterval` (default 1000ms) -- how often the server batches notifications
   - `RequestedSamplingInterval` (default 500ms) -- how often the server checks for changes
   - `RequestedQueueSize` (default 1) -- how many changes the server buffers per node

**Each poll cycle (OnTask):**
1. Calls `Client.PollSubscriptionSet(queryHandle, timeout)` -- asks "any changes?"
2. Gets back a batch of notifications (could be 0 to many)
3. Loops through each notification, passes to `BusinessHost.ProcessInput()` one at a time
4. Monitors queue health: warns if data loss detected (queue overflow), logs batch size statistics

---

## 12. Services: The Data Processors

**Key files:** `OPCUA/Service/TCPPollingService.cls`, `OPCUA/Service/TCPSubscriptionService.cls`, `OPCUA/Service/TCPPollingRowSourceService.cls`, `OPCUA/Service/TCPSubscriptionRowSourceService.cls`

A "business service" in Ensemble is the high-level component that owns an adapter and processes its output. Think of it as: the adapter handles "how to get data," the service handles "what to do with it."

### Declarative Polling Service (`TCPPollingService`)

Runtime for hand-authored DataSource classes (Examples + `OPCUA.Tests`). Not used by generated schemas.

**OnInit** (runs once at startup):
1. Reads the DataSourceClass setting (e.g., `"OPCUA.DS.MyPipeline"`)
2. Calls `OPCUA.DataSource.Projection.GetOPCUAConfigSpec(className)` to get the compiled spec from `^OPCUA.DataSource`
3. Passes the spec to the adapter via `Adapter.Configure()`

**OnProcessInput** (runs each time the adapter delivers data):
1. Receives a `$ListBuild` list from the adapter: `$LB(metadata, value1, value2, ...)`
2. Calls `DataSourceClass.SaveSourcedData(list)` -- the code-generated method that persists it as a table row
3. That's it -- one row saved per poll cycle

### Declarative Subscription Service (`TCPSubscriptionService`)

Same as the declarative polling service, but receives data from the subscription adapter. Each notification becomes one row.

### Row-source services (generated schemas)

The runtime for every deployed pipeline (the v2 row-source model) -- more complex, see [section 14](#14-v2-pipelines-multiple-devices-one-table).

---

## 13. Polling vs Subscriptions

These are the two fundamental ways to get data from OPC UA servers. Understanding the difference is key:

### Polling

```
Every N seconds:
  IRIS: "Hey server, what are the current values of Temperature, Humidity, Pressure?"
  Server: "Temperature=20.5, Humidity=65%, Pressure=1013"
  IRIS: *saves row to table*
```

- **Pro:** Simple, predictable, you always get a complete snapshot
- **Con:** You might miss changes between polls; wastes bandwidth if values rarely change
- **IRIS class:** `TCPPollingInboundAdapter` + `TCPPollingService`
- **Key setting:** `CallInterval` (seconds between polls)

### Subscriptions

```
Once:
  IRIS: "Server, monitor Temperature, Humidity, Pressure and tell me when they change."
  Server: "OK, I'll check every 500ms and batch notifications every 1000ms."

Ongoing:
  IRIS: "Any changes?"
  Server: "Temperature changed to 21.0 at 12:34:56"
  IRIS: *saves row to table*
  
  IRIS: "Any changes?"
  Server: "Nothing new."
  
  IRIS: "Any changes?"
  Server: "Humidity changed to 63%, Pressure changed to 1012"
  IRIS: *saves rows to table*
```

- **Pro:** Only get data when it changes; lower bandwidth; faster reaction time
- **Con:** More complex; can lose data if queue overflows; need to handle server disconnects
- **IRIS class:** `TCPSubscriptionInboundAdapter` + `TCPSubscriptionService`
- **Key settings:** `PublishingInterval`, `SamplingInterval`, `QueueSize`

---

## 14. v2 Pipelines: Multiple Devices, One Table

**Key files:** `OPCUA/Service/TCPPollingRowSourceService.cls`, `OPCUA/Service/TCPSubscriptionRowSourceService.cls`

### The problem v2 solves

Imagine you have 10 identical PLCs (programmable logic controllers) on a factory floor. Each has Temperature and Humidity nodes. In v1, you'd need 10 separate pipelines and 10 separate tables. With v2, you get one table with a `NodePath` column that identifies which PLC each row came from:

| NodePath | Temperature | Humidity |
|----------|-------------|----------|
| /PLC/Unit1 | 20.5 | 65 |
| /PLC/Unit2 | 21.0 | 62 |
| /PLC/Unit3 | 19.8 | 68 |

### How it works

**Row sources** = the devices (e.g., Unit1, Unit2, Unit3). Each is identified by its OPC UA node path.

**Columns** = the union of all properties across all row sources. Not every device has to have every column -- missing ones get NULL.

**Column masks** tell the runtime which columns each row source actually has. For example:

```
Columns:    [Temperature, Humidity, Pressure]
Unit1 mask: [1, 1, 1]   -- has all three
Unit2 mask: [1, 1, 0]   -- no Pressure sensor
```

### Where devices come from: name-based resolution

Devices are **not** frozen into the schema at deploy time. Two settings on the config item are the whole binding:

- `DataSourceClass` — the schema (which columns exist)
- `DeviceNodePaths` — one device root per line, e.g. `ns=2;s=Plant.AC1|AC1`

At **connect time**, `OPCUA.DataSource.Resolver.ResolveSpecification()` browses each device root and matches its children **by name** against the schema's column names. That produces the read spec and the column masks fresh on every connect.

This is why:
- Adding a device is a one-line edit to a production setting — no regeneration, no recompile
- A device that is offline at startup begins reporting on its own once it becomes reachable, because resolution re-runs on every reconnect
- Nothing needs to be stored: masks are *derived*, not remembered

Note the asymmetry with the deploy-time gate below: `/deploy` refuses a device it
cannot browse, but a device that *becomes* unreachable later is kept and simply
stores NULL. The gate proves a binding is worth making; it is not a liveness check.

Unresolved columns store NULL and log a warning naming the device and column, and
the pipeline keeps collecting everything that did resolve. There is deliberately no
refuse-to-collect mode: coverage is reported *before* deploy by
`POST /schemas/:name/validate`, so a partially matching device is bound knowingly,
and one missing node must not cost the operator the columns that work.

#### The deploy-time usability gate

`SchemaService.RequireUsableDevices()` is called by **both** `POST /deploy` and
`POST /pipelines/rebind`. A device is bindable only when the server answered its
browse **and** at least one schema column matched:

| Browse | Matches | Verdict |
|--------|---------|---------|
| error | — | **refused** — unreachable, or the NodeId does not exist |
| `Good` | 0 | **refused** — every row would be entirely NULL, forever |
| `Good` | ≥1 | accepted (missing columns store NULL) |

Distinguishing the first two rows is why `Resolver.ResolveSpecification()` reports a
per-device `pBrowseOK` list: a zero-match device means something quite different
depending on whether the server was reachable, and the two have different fixes.

This is a **deploy-time gate only**, and deliberately not enforced on connect. A
device that drops offline mid-session must keep storing NULL and warning, not take
the pipeline down — enforcing it at runtime would recreate `StrictSchemaMatch`,
which was removed for exactly that reason. The cost is that a device cannot be bound
before it exists; adding it afterwards is a rebind, which is one settings edit.

### v2 Service startup (OnInit / Connect)

1. `OnInit()` reads the schema's column layout from the compiled class (via `^OPCUA.DataSource`) and derives the nesting spec.
2. On **connect**, the adapter's `ResolveSpecification()` hook browses every device in `DeviceNodePaths` and builds the combined spec: for each device, for each resolved column, one read entry.
3. The combined spec goes to the adapter -- so one poll cycle reads ALL nodes for ALL devices.

The ordering matters: the session must be established *before* the spec is built, because building it requires browsing. Both adapters connect first, then resolve, then prepare the read/subscription query.

### v2 Data processing (OnProcessInput)

The adapter returns one big flat list of values (all devices, all columns). The service:

1. Splits the list by row source (using the known counts from the mask)
2. For each row source:
   - Extracts the leaf values
   - Applies nesting if needed (see next section)
   - Builds the row: `$LB("", nodePath, serverTimestamp, sourceTimestamp, value1, value2, ...)`
   - Calls `SaveSourcedData()` to persist it

---

## 15. Nesting: Handling Folder Hierarchies

**Key concept in:** `OPCUA/REST/DeployService.cls`, `OPCUA/Service/TCPPollingRowSourceService.cls`

OPC UA servers often organize nodes in folder hierarchies:

```
Unit1/
  Temperature          (leaf - readable value)
  Humidity             (leaf)
  StateCondition/      (folder)
    CurrentState       (leaf)
    LastSeverity       (leaf)
```

When you select both top-level leaves AND leaves inside sub-folders, the system needs to represent this hierarchy in the IRIS table. It does this using `%SerialObject` classes (embedded objects):

```objectscript
Class OPCUA.DS.MyPipeline Extends (%Persistent, OPCUA.DataSource.Definition)
{
  Property Temperature As OPCUA.Types.DoubleDataValue;
  Property Humidity As OPCUA.Types.DoubleDataValue;
  Property StateCondition As OPCUA.DS.MyPipeline.StateCondition;  // embedded serial object
}

Class OPCUA.DS.MyPipeline.StateCondition Extends %SerialObject
{
  Property CurrentState As OPCUA.Types.StringDataValue;
  Property LastSeverity As OPCUA.Types.IntegerDataValue;
}
```

In SQL, this appears as flattened columns: `Temperature`, `Humidity`, `StateCondition_CurrentState`, `StateCondition_LastSeverity`.

The **nesting spec** describes this tree structure so the v2 runtime services know how to assemble the nested `$ListBuild` structures from flat leaf values. It is *derived at startup* by `Resolver.DeriveNestingSpec()`, which walks the compiled class's storage order — nothing is stored. Each entry is either:
- `$LB("leaf", index)` -- a direct value at a specific position
- `$LB("serial", folderName, innerSpec...)` -- a nested object with its own entries

`BuildNestedValues()` in the row source services recursively walks this spec to assemble the proper nested `$LB` structure.

---

## 16. Managing Pipelines After Deployment

**Key file:** `OPCUA/REST/PipelineService.cls`

### Listing pipelines

`PipelineService.List()`:
1. Opens `OPCUA.Pipeline.Production` configuration
2. Walks through all Items in the production
3. For each item, returns: name, class, enabled state, settings (URL, interval, etc.), runtime status, row count (via SQL query on the DataSource table)
4. Describes the devices by parsing the item's `DeviceNodePaths` setting against the schema's column list (`GetRowSourceInfo()`)
5. Reports **health** (`GetHealth()`), which is not the same as "enabled": a pipeline that can't connect or whose columns don't resolve stays enabled and keeps retrying while writing nothing. The adapters publish an OK/Error verdict per cycle via `$$$SetHostMonitor`, and this reads it back — so the UI can distinguish `ok`, `error`, `starting`, `disabled` and `stopped`.

### Toggling (enable/disable)

`PipelineService.Toggle()`:
1. Finds the item by name in the production
2. Flips its `Enabled` flag
3. Saves production, calls `UpdateProduction()` to apply

### Deleting

`PipelineService.Delete()`:
1. Removes the item from the production's Items collection
2. Saves and updates the production
3. **Leaves the schema alone.** A schema is a reusable asset that may back several pipelines, so deleting one pipeline must not destroy it — that would break every sibling still bound to it and, since the schema class owns the table, discard the collected rows. The response reports `schemaRetained` and `schemaStillUsedBy` so a caller can decide for itself.

Deleting a schema is `SchemaService.Delete()`, which refuses while any pipeline still references it.

### Editing: rebinding devices

`PipelineService.Rebind()` (`POST /pipelines/rebind`):
1. Parses and validates the new device list
2. Applies the same usability gate as deploy, using the pipeline's own schema and
   connection settings (read back by `DescribeItem()`, including the security
   settings — a secured pipeline's coverage check would otherwise fail to connect
   and reject every device)
3. Writes the `DeviceNodePaths` setting
4. Calls `UpdateProduction()` — the service re-resolves on its next connect

That is the whole of editing a pipeline. Because devices are resolved by name at connect time, changing the list is a **settings update**: no regeneration, no recompile, no metadata to migrate.

Changing a schema's **columns** is deliberately not possible here, and currently not possible anywhere — the regenerating edit path was removed along with the combined create-and-deploy wizard that drove it. Recreating the schema is the supported route, which does drop the table and its data. An `ALTER`-style schema edit is the obvious thing to build if that becomes painful.

### The webapp flow

There is no combined "create everything at once" wizard, and deliberately so:
schema creation and device binding are separate screens because they are separate
decisions, made at different times and often by different people.

1. **Schemas** (`/schemas`) — the library. Lists every schema with the pipelines
   using it, so deleting one that is still in use is refused rather than silently
   breaking a pipeline.
2. **New Schema** (`/schemas/new`) — browse **one representative device** and tick
   the nodes that define the type. Its node IDs are not stored; each ticked column
   is read once to infer its storage type. Ends at "Save Schema" and never touches
   a production.
3. **Bind Devices** (`/pipelines/bind/:schema`) — pick device roots from the live
   address space, or paste nodepaths as text. Both views read and write the same
   list, so pasting lights up the tree. Each device is dry-run against the schema
   **as it is added** (`/schemas/:name/validate`) and carries its own verdict in the
   list: `3/3` green, a `2/3` amber row naming the columns that will be NULL, or a
   red row that blocks deploy. There is no separate coverage step — a manual button
   could be skipped, and skipping it meant Deploy looked ready and then failed on
   the backend gate. Results are cached per device, so adding a device never
   re-browses the ones already checked.
4. **Pipelines** (`/pipelines`) — the dashboard. Shows real collection health, not
   just enabled/disabled. Editing a pipeline reopens the binding screen: the schema
   and name are fixed, only the device list changes.

Reusing a schema across more devices therefore costs one visit to step 3.

---

## 17. Security and Certificates

OPC UA supports two security modes:

### SecurityMode 1: None
No encryption, no authentication (anonymous). Used for development/testing.

### SecurityMode 3: Sign & Encrypt
Mutual TLS -- both client and server verify each other's certificates. Requires:

- **Client certificate** (DER format) -- our identity card
- **Private key** (DER format) -- proof we own the certificate
- **Trust directory** -- folder containing certificates we trust (the server's CA cert goes here)
- **CRL directory** -- Certificate Revocation Lists (list of revoked certificates)
- **Client URI** -- must match the `subjectAltName` in our certificate (e.g., `urn:secuac`)

These are passed through `Client.SetupClient()` before connecting. The C++ library handles the actual TLS handshake.

For Docker, `certgen/certgen.bash` generates all necessary certificates using OpenSSL.

---

## 18. Global Variables: The Shared State

IRIS "globals" are persistent key-value trees (like a hierarchical NoSQL store). The project uses several:

| Global | Set by | Read by | Contains |
|--------|--------|---------|----------|
| `^OPCUA.DataSource(className)` | Projection (on class compile) | Services (on startup) | Config spec: `$LB(name, storageGlobal, specList)` |
| `^OPCUA.Library.Pathname` | Installer | Utils.Initialize() | Path to the C++ shared library |

There is deliberately **no** device-metadata global. An earlier design stored row sources, column masks, absolute node IDs and the nesting spec in `^OPCUA.RowSource`; all of that is now derived — masks and node IDs by browsing at connect time, the nesting spec from the compiled class's storage order. Removing it is what made "add a device" a settings edit rather than a regeneration.
| `%ZUtilsIrisOpcuaLibraryId` | Utils.Initialize() | Client (every call) | Loaded library handle (process-scoped, not persistent) |

These globals are the "glue" between compile-time (class generation, projection) and runtime (service startup, data collection).

---

## 19. End-to-End Data Flow

Here's the complete journey of a data point from an OPC UA server to a SQL query result:

### Setup phase (happens once)

```
--- Step A: create the schema (once per device TYPE) ---

1. User opens Schemas > New Schema in browser
2. Angular app calls /browse -> BrowseService -> Client.Browse() -> C++ -> OPC UA server
3. User browses ONE representative device and ticks "Temperature" and "Humidity".
   Its node IDs are NOT captured — only the column names.
4. Each ticked column is read once (/read) to infer its type
5. User clicks Save Schema -> POST /schemas

6. SchemaService.GenerateSchemaClass() builds the class via %Dictionary:
     Class OPCUA.DS.MyData Extends (%Persistent, OPCUA.DataSource.DeviceSchema) { ... }

7. $System.OBJ.Compile() compiles the class:
   a. IRIS creates SQL table OPCUA_DS.MyData
   b. Projection.CreateProjection() fires:
      - Walks properties, reads OPCUANODENAME parameters
      - Builds spec: $LB("MyData", "^OPCUA.DS.MyDataD", $LB("", $LB(1,"[MyData].Temperature",2,"Temperature",13), ...))
      - Stores in ^OPCUA.DataSource("OPCUA.DS.MyData")
      - Generates SaveSourcedData() method

   No production is touched. The schema now exists on its own.

--- Step B: bind devices (once per PIPELINE; repeatable per schema) ---

8. User opens Bind Devices and picks device roots from the tree (or pastes
   nodepaths). Each new device is validated as it lands (/schemas/:name/validate);
   an unusable one is flagged in place and Deploy stays locked until it is removed

9. POST /deploy {schemaClass, devices} -> DeployService.BindExistingSchema()
   adds an item to OPCUA.Pipeline.Production. It GENERATES NOTHING:
   - ClassName: OPCUA.Service.TCPPollingRowSourceService
   - Settings: DataSourceClass=OPCUA.DS.MyData, URL=opc.tcp://plc:4840,
               DeviceNodePaths="ns=2;s=Unit1|Unit1<newline>ns=2;s=Unit2|Unit2",
               CallInterval=5
   The item is created with Enabled=0 and the production is NOT started.

10. User reviews the pipeline on the dashboard and presses play
    (POST /pipelines/toggle) -> Ens.Director starts it. Only now does anything
    connect to the server or write a row.
```

### Runtime phase (repeats continuously)

```
11. Ensemble calls TCPPollingRowSourceService.OnInit():
    - Reads the ^OPCUA.DataSource(...) spec template for the column layout
      and derives the nesting spec from the compiled class

12. Adapter.Connect():
    - Creates OPCUA.Client, calls $ZF to load C++ library
    - Calls SetupClient() and Connect(url)   <-- session established FIRST
    - ResolveSpecification(): browses each device in DeviceNodePaths and matches
      children BY NAME against the schema's columns, producing the combined spec
      + per-device column masks. Unmatched columns -> NULL + a warning.
    - Calls ReadBulkSetupC(spec) -> C++ prepares the query

    Because this runs on every (re)connect, editing DeviceNodePaths takes effect
    without a recompile, and a device that was offline starts reporting on its own.

13. Every 5 seconds, Ensemble calls Adapter.OnTask():
    - Calls ReadBulkPollC(queryHandle) -> $ZF -> C++ -> OPC UA server
    - Server returns: Temperature=20.5 (source time: 12:00:05, server time: 12:00:05)
                      Humidity=65.2    (source time: 12:00:05, server time: 12:00:05)
    - C++ packs into $LB and returns to ObjectScript

14. Adapter passes result to TCPPollingRowSourceService.OnProcessInput():
    - Splits the flat result by row source / column mask, then for each row source
      calls OPCUA.DS.MyData.SaveSourcedData($LB("", nodePath, serverTS, sourceTS, 20.5, 65.2))
    - SaveSourcedData() creates one row per row source per poll

15. Data is now queryable (v2 stores plain values + a NodePath column):
    SELECT NodePath, Temperature, Humidity FROM OPCUA_DS.MyData
    -> Objects, 20.5, 65.2
```

---

## 20. Class Dependency Map

```
                    OPCUA.Constants.inc  (function ordinals, enums)
                           |
                    OPCUA.Utils  (library loading)
                           |
                    OPCUA.Client  (C++ wrapper)
                      /        \
                     /          \
        OPCUA.Adapter.Common     OPCUA.REST.ClientManager
           /          \                    |
          /            \          OPCUA.REST.Handler (router)
         /              \          /    |    |    \     \
TCPPolling    TCPSubscription   Browse Read Deploy Pipeline
InboundAdapter InboundAdapter   Svc   Svc   Svc    Svc
         \              /              |
          \            /        OPCUA.DataSource.Generator
    OPCUA.Service.*                     |
     /    |    \              OPCUA.DataSource.Projection
  decl  decl  rowsource                 |
  Poll   Sub   Poll/Sub    OPCUA.DataSource.Definition
 (tests/examples)(generated)
    \     |     /                       |
     \    |    /               Generated DataSource classes
      \   |   /               (OPCUA.DS.MyPipeline, etc.)
    SaveSourcedData()                   |
           |                  OPCUA.Types.* (value wrappers)
           v
    ^StorageGlobal  ->  SQL Table
```

**Reading this map:**
- Arrows point in the direction of "uses" or "calls"
- The left side (Adapters/Services) is the runtime data collection path
- The right side (REST/Handler) is the web API path
- They meet at the DataSource classes in the middle
- Everything ultimately depends on `OPCUA.Client` and the C++ library

---

## Quick Reference: "Where do I look for...?"

| If you want to understand... | Look at... |
|------------------------------|-----------|
| How IRIS calls C++ functions | `OPCUA/Client.cls`, `OPCUA/Constants.inc` |
| How the library gets loaded | `OPCUA/Utils.cls` |
| What types of data we store | `OPCUA/Types/*.cls` |
| How tables are auto-created | `OPCUA/DataSource/Definition.cls`, `Projection.cls` |
| How the REST API works | `OPCUA/REST/Handler.cls` |
| How browsing works | `OPCUA/REST/BrowseService.cls` |
| How schemas are generated | `OPCUA/REST/SchemaService.cls` |
| How devices are bound to a schema | `OPCUA/REST/DeployService.cls` |
| How devices are matched by name at connect time | `OPCUA/DataSource/Resolver.cls` |
| Why `DataSourceClass` is a dropdown | `OPCUA/DataSource/DeviceSchema.cls`, `SETTINGS` in `Adapter/Common.cls` |
| How polling works at runtime | `OPCUA/Adapter/TCPPollingInboundAdapter.cls`, `OPCUA/Service/TCPPollingService.cls` |
| How subscriptions work | `OPCUA/Adapter/TCPSubscriptionInboundAdapter.cls`, `OPCUA/Service/TCPSubscriptionService.cls` |
| How multi-device (v2) works | `OPCUA/Service/TCPPollingRowSourceService.cls` |
| How pipelines are managed | `OPCUA/REST/PipelineService.cls` |
| How the Docker image is set up | `IRISConfig/Installer.cls` |
| How certificates work | `certgen/certgen.bash`, security settings in `OPCUA/Adapter/Common.cls` |
