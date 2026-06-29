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

There are two paths:

**v1 (single device):** `DeployService.Deploy()` uses the `%Dictionary` API -- IRIS's way to programmatically create classes at runtime. It creates a `%Dictionary.ClassDefinition`, adds `%Dictionary.PropertyDefinition` entries for each column, then calls `$System.OBJ.Compile()` to compile it. Compiling is what creates the SQL table and the storage structure.

**v2 (multiple devices):** `DeployService.DeployV2()` generates the class as a text string (literal `.cls` file content), writes it to disk, and compiles it. This approach is used because v2 classes can have nested `%SerialObject` subclasses (for folder hierarchies), and it's easier to generate them as text.

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

The Angular web app (pipeline wizard) communicates with IRIS through a REST API. IRIS has built-in REST support through `%CSP.REST` (CSP = Cache Server Pages, IRIS's web framework).

### The Handler (router)

`OPCUA.REST.Handler` extends `%CSP.REST` and defines URL routes:

| URL Path | Method | What it does |
|----------|--------|-------------|
| `/ping` | GET | Health check -- returns timestamp |
| `/browse` | GET/POST | Browse OPC UA server nodes |
| `/read` | GET/POST | Read a single node's value |
| `/generate` | GET/POST | Generate a DataSource class from selected nodes |
| `/test` | GET/POST | Test connection to an OPC UA server |
| `/deploy` | POST | Deploy a new pipeline |
| `/pipelines` | GET/POST | List all deployed pipelines |
| `/pipelines/edit` | POST | Modify an existing pipeline |
| `/pipelines/toggle` | POST | Enable/disable a pipeline |
| `/pipelines/delete` | POST | Delete a pipeline |

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

When you expand a node in the pipeline wizard's tree view, the frontend calls `/browse` with the node's coordinates (namespace + node ID). Here's what happens:

1. `BrowseService.Browse()` receives the request
2. Creates a temporary OPC UA client via `ClientManager.Connect()`
3. Calls `Client.Browse(nodeTypes, namespaces, nodeIds)` -- this calls the C++ library, which sends an OPC UA BrowseRequest to the server
4. The C++ library returns a list of "references" (children of the browsed node)
5. `ParseBrowseResults()` classifies each child:
   - **Is it a folder?** Check if the type definition is FolderType (ID 61), or if the reference type is "Organizes"
   - **Is it a variable?** (something you can read data from) Check against 52 known OPC UA variable type IDs (BaseVariableType, DataItemType, AnalogItemType, etc.)
   - **Is it a property?** Check if the reference type is "HasProperty"
   - **Is it an object?** (a container for other nodes) Everything else
6. Returns a JSON array with each child's display name, namespace, node ID, category (variable/folder/object/property), and whether it has children of its own

The pipeline wizard uses this to render the expandable tree where users check nodes they want to poll.

---

## 9. Deploying a Pipeline

**Key file:** `OPCUA/REST/DeployService.cls`

Deployment is the most complex operation. It takes the user's selections (which nodes to poll, from which server, how often) and sets up everything needed for continuous data collection.

### v1 deployment (single device, simpler)

1. **Generate the DataSource class:**
   - Use `%Dictionary.ClassDefinition` API to create a new class
   - Set it to extend `(%Persistent, OPCUA.DataSource.Definition)`
   - For each selected node, add a `%Dictionary.PropertyDefinition` with the appropriate type and `OPCUANODENAME` parameter
   - Call `$System.OBJ.Compile()` -- this creates the SQL table and triggers the Projection

2. **Ensure the production exists:**
   - Check if `OPCUA.Pipeline.Production` exists (a "production" is IRIS's name for a collection of background services/processes that run together)
   - If not, create it as an empty production class

3. **Add a service item to the production:**
   - An "item" is one background worker in the production
   - Create an `Ens.Config.Item` (the configuration object for a production item)
   - Set its class to `OPCUA.Service.TCPPollingService` or `OPCUA.Service.TCPSubscriptionService`
   - Configure settings: DataSourceClass, URL, poll interval, security parameters
   - Add it to the production's Items collection
   - Save the production and call `SaveToClass()` (which writes the config into the class's XData block -- IRIS's way of embedding structured data in a class definition)

4. **Start or update the production:**
   - If the production is already running, call `Ens.Director.UpdateProduction()` to hot-reload the new item
   - If stopped, start it with `Ens.Director.StartProduction()`

### v2 deployment (multiple devices, union table)

Similar to v1, but:
- The DataSource class text is generated as a string (including potential `%SerialObject` subclasses for nested folders)
- `StoreRowSourceMetadata()` saves additional metadata to `^OPCUA.RowSource` about which devices have which columns (the "column mask")
- The service class used is `TCPPollingRowSourceService` or `TCPSubscriptionRowSourceService`

More on v2 in [section 14](#14-v2-pipelines-multiple-devices-one-table).

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

### v1 Polling Service (`TCPPollingService`)

**OnInit** (runs once at startup):
1. Reads the DataSourceClass setting (e.g., `"OPCUA.DS.MyPipeline"`)
2. Calls `OPCUA.DataSource.Projection.GetOPCUAConfigSpec(className)` to get the compiled spec from `^OPCUA.DataSource`
3. Passes the spec to the adapter via `Adapter.Configure()`

**OnProcessInput** (runs each time the adapter delivers data):
1. Receives a `$ListBuild` list from the adapter: `$LB(metadata, value1, value2, ...)`
2. Calls `DataSourceClass.SaveSourcedData(list)` -- the code-generated method that persists it as a table row
3. That's it -- one row saved per poll cycle

### v1 Subscription Service (`TCPSubscriptionService`)

Same as polling service, but receives data from the subscription adapter. Each notification becomes one row.

### v2 Services (RowSource variants)

More complex -- see [section 14](#14-v2-pipelines-multiple-devices-one-table).

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

### v2 Service startup (OnInit)

1. Load metadata from `^OPCUA.RowSource(className)`:
   - How many row sources
   - How many columns
   - List of row source paths
   - Column masks per row source
   - Nesting spec (for folder hierarchies)
2. Build a combined spec: for each row source, for each active column (mask=1), add one read entry
3. Pass the combined spec to the adapter -- so one poll cycle reads ALL nodes for ALL devices

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

The **nesting spec** stored in `^OPCUA.RowSource` describes this tree structure so the v2 runtime services know how to assemble the nested `$ListBuild` structures from flat leaf values. Each entry is either:
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
4. For v2 pipelines: also reads `^OPCUA.RowSource` metadata to return row source paths and column info

### Toggling (enable/disable)

`PipelineService.Toggle()`:
1. Finds the item by name in the production
2. Flips its `Enabled` flag
3. Saves production, calls `UpdateProduction()` to apply

### Deleting

`PipelineService.Delete()`:
1. Removes the item from the production's Items collection
2. Saves and updates the production
3. Deletes the DataSource class using `$System.OBJ.Delete()` -- which also drops the SQL table
4. For v2: also deletes any generated `%SerialObject` subclasses
5. Cleans up `^OPCUA.DataSource` and `^OPCUA.RowSource` globals

### Editing (v2 only)

`PipelineService.Edit()`:
1. Receives updated columns and row sources
2. Regenerates the DataSource class text
3. Recompiles (this modifies the SQL table schema)
4. Updates `^OPCUA.RowSource` metadata
5. Updates production settings
6. The running service picks up changes on next `UpdateProduction()`

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
| `^OPCUA.RowSource(className)` | DeployService (on v2 deploy) | v2 Services (on startup) | Row source metadata: `$LB(rsCount, colCount, rsList, colPaths, nestingSpec)` |
| `^OPCUA.Library.Pathname` | Installer | Utils.Initialize() | Path to the C++ shared library |
| `%ZUtilsIrisOpcuaLibraryId` | Utils.Initialize() | Client (every call) | Loaded library handle (process-scoped, not persistent) |

These globals are the "glue" between compile-time (class generation, projection) and runtime (service startup, data collection).

---

## 19. End-to-End Data Flow

Here's the complete journey of a data point from an OPC UA server to a SQL query result:

### Setup phase (happens once)

```
1. User opens pipeline wizard in browser
2. Angular app calls /browse -> BrowseService -> Client.Browse() -> C++ -> OPC UA server
3. User sees tree of nodes, checks "Temperature" and "Humidity"
4. User clicks Deploy
5. Angular app calls /deploy with selected nodes + server URL + settings

6. DeployService generates class text:
     Class OPCUA.DS.MyData Extends (%Persistent, OPCUA.DataSource.Definition) { ... }

7. $System.OBJ.Compile() compiles the class:
   a. IRIS creates SQL table OPCUA_DS.MyData
   b. Projection.CreateProjection() fires:
      - Walks properties, reads OPCUANODENAME parameters
      - Builds spec: $LB("MyData", "^OPCUA.DS.MyDataD", $LB("", $LB(1,"[MyData].Temperature",2,"Temperature",13), ...))
      - Stores in ^OPCUA.DataSource("OPCUA.DS.MyData")
      - Generates SaveSourcedData() method

8. DeployService adds item to OPCUA.Pipeline.Production:
   - ClassName: OPCUA.Service.TCPPollingService
   - Settings: DataSourceClass=OPCUA.DS.MyData, URL=opc.tcp://plc:4840, CallInterval=5

9. Production starts (or updates if already running)
```

### Runtime phase (repeats continuously)

```
10. Ensemble calls TCPPollingService.OnInit():
    - Reads ^OPCUA.DataSource("OPCUA.DS.MyData") to get spec
    - Passes spec to adapter

11. Adapter.Connect():
    - Creates OPCUA.Client, calls $ZF to load C++ library
    - Calls SetupClient() and Connect(url)
    - Calls ReadBulkSetupC(spec) -> C++ prepares the query

12. Every 5 seconds, Ensemble calls Adapter.OnTask():
    - Calls ReadBulkPollC(queryHandle) -> $ZF -> C++ -> OPC UA server
    - Server returns: Temperature=20.5 (source time: 12:00:05, server time: 12:00:05)
                      Humidity=65.2    (source time: 12:00:05, server time: 12:00:05)
    - C++ packs into $LB and returns to ObjectScript

13. Adapter passes result to TCPPollingService.OnProcessInput():
    - Calls OPCUA.DS.MyData.SaveSourcedData($LB("", 20.5, "2026-04-14 12:00:05", ..., 65.2, ...))
    - SaveSourcedData() creates a new row in the table

14. Data is now queryable:
    SELECT Temperature_Value, Humidity_Value FROM OPCUA_DS.MyData
    -> 20.5, 65.2
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
    v1    v1    v2                      |
  Poll   Sub   Poll/Sub    OPCUA.DataSource.Definition
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
| How deployment works | `OPCUA/REST/DeployService.cls` |
| How polling works at runtime | `OPCUA/Adapter/TCPPollingInboundAdapter.cls`, `OPCUA/Service/TCPPollingService.cls` |
| How subscriptions work | `OPCUA/Adapter/TCPSubscriptionInboundAdapter.cls`, `OPCUA/Service/TCPSubscriptionService.cls` |
| How multi-device (v2) works | `OPCUA/Service/TCPPollingRowSourceService.cls` |
| How pipelines are managed | `OPCUA/REST/PipelineService.cls` |
| How the Docker image is set up | `IRISConfig/Installer.cls` |
| How certificates work | `certgen/certgen.bash`, security settings in `OPCUA/Adapter/Common.cls` |
