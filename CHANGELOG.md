## Unreleased — Schema / device decoupling

Creating a schema and choosing which devices to read are now separate operations.
Previously one wizard run produced a single frozen artifact: a generated class whose
device list was baked in at deploy time. Adding a device meant regenerating and
recompiling the class.

### Added
  - `OPCUA.DataSource.DeviceSchema` — abstract superclass for generated schemas. Gives
    the `DataSourceClass` production setting a class family, so it renders as a dropdown.
  - `OPCUA.DataSource.Resolver` — parses `DeviceNodePaths` and matches each device's
    children **by name** against the schema's columns, at connect time.
  - `OPCUA.REST.SchemaService` and `/schemas` endpoints (list, create, get, delete,
    validate). Creating a schema has no production side effects.
  - `POST /pipelines/rebind` — change a pipeline's device list or strictness as a
    settings update: no regeneration, no recompile.
  - `DeviceNodePaths` and `StrictSchemaMatch` adapter settings. A pipeline can now be
    built entirely from the Management Portal, with no webapp involved.
  - Pipeline health reporting: a pipeline that is enabled but failing to connect or
    resolve is reported as `error` rather than looking healthy.
  - Webapp: Schemas library, schema builder, device binding screen with a live
    address-space picker and a Check Coverage dry run.
  - `OPCUA.Tests.ResolverTest`, `OPCUA.Tests.PortalPipelineTest`.

### Changed
  - `POST /deploy` now requires `schemaClass` and **generates nothing** — it binds
    devices to a schema that already exists.
  - Deleting a pipeline no longer deletes its schema. Schemas are reusable and may back
    several pipelines; `DELETE /schemas/:name` refuses while any pipeline uses one.
  - The polling adapter drops its session when query setup fails, so a resolution
    failure reports its real cause on every retry and recovers from a config edit
    instead of stalling until restarted.
  - Schema columns are typed from a sample read instead of all landing as `%String`.

### Removed
  - `^OPCUA.RowSource`. Device metadata, column masks and the nesting spec are now
    derived — masks by browsing at connect time, nesting from the compiled class.
  - The combined create-and-deploy wizard, `DeployService.DeployV2()`, and
    `PipelineService.Edit()` with its `/pipelines/edit` route.
  - The Monitoring tab and its metrics stack (`OPCUA.REST.MetricsService`,
    `OPCUA.Monitor.Metrics`, `/metrics`, and the SAM registration in the installer —
    including the `%DB_OPCUA` grant to `UnknownUser` that existed only to serve it).

### Known limitations
  - A schema's **column set** cannot be changed after creation; recreating the schema
    drops its table and data. An `ALTER`-style schema edit is the obvious next step.
  - `OPCUA.Tests.DataTest` cannot run in the Docker compose setup (no `APPINT`
    namespace, and its target server is unreachable). Use the local `plc` server as the
    declarative-path regression gate.

## 0.3.4 (May 14, 2021)
  - Update README.md, IrisOPCUA_prj-20210513.xml, and 6 more files...
  - Update README.md, IrisOPCUA_prj-20210513.xml, and 6 more files...
  - windows README edit
  - Windows files
  - NodeIdDataValue storage correction
  - Another README edit
  - Removes unnecessary instruction from README
  - Bump version to 0.3.3.

## 0.3.3 (May 07, 2021)
  - hook
  - bumpversion

## 0.3.2 (May 07, 2021)
  - Security changes. Export of arrays and additional data types.
  - Fixing bumpversion script
  - Fixing bumpversion script

## 0.3.1 (May 06, 2021)
  - OPCUA Connector with TCP/IP Pulling available

