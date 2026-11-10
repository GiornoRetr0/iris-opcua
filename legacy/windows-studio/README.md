# Windows Studio project

`IrisOPCUA_prj-20261030.xml` is a Studio export of the application classes as of
2026-10-30. It has no generator in this repository: it was exported by hand from IRIS and
is not regenerated per release.

It does **not** contain `OPCUA.Security.*` (managed Sign & Encrypt, `/security/*`
endpoints) and matches the connector before 0.5.0. For managed Sign & Encrypt on Windows,
install the 0.5.0 `IrisOPCUA.dll` from `backend/native/windows-x64/` and load
`backend/src/OPCUA/` (or use the terminal installer in `installer/`) instead of this
project.
