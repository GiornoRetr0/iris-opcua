# IRIS OPC UA for Windows versions of IRIS

These are the native files for 64-bit Windows IRIS servers. Copy all three into the
instance's `bin` directory, which is where IRIS's loader looks for a DLL's
dependencies. The terminal installer (`installer/`) does this for you.

| File | What it is |
|------|------------|
| `IrisOPCUA.dll` | The connector, built from the same C++ sources as the Linux `irisopcua.so` |
| `open62541.dll` | open62541 v1.2.1, unchanged |
| `libcrypto-1_1-x64.dll` | OpenSSL 1.1, needed by `open62541.dll` |

## libcrypto-1_1-x64.dll

IMPORTANT: do not overwrite IRIS's copy of this file if one already exists in the
`bin` directory. The copy here is only for instances that lack it. The terminal
installer never replaces an existing copy.

## How IrisOPCUA.dll is built

`IrisOPCUA.dll` is cross-built with llvm-mingw (UCRT) by
`opc-ua-master/docker/build-win64.sh` in the closed-source C++ repository. It
links against the `open62541.dll` here and uses the same Universal CRT. Because
libc++ is linked statically, it needs no Visual C++ redistributable of its own.
`open62541.dll` still needs `VCRUNTIME140.dll`, which IRIS for Windows ships.

The previous `IrisOPCUA.dll` was an MSVC build from 2021. It predated
`zfGetEndpoints` and the change that keeps Bad readings in bulk polls.
