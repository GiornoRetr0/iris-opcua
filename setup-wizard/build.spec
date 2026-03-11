# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for IRIS OPC UA Adapter Setup Wizard.

Bundles:
  - Platform binaries (DLLs on Windows, .so on Linux)
  - ObjectScript source files (48 .cls + 1 .inc)
  - VERSION file

Build:
  cd irisopcua/setup-wizard
  pyinstaller build.spec
"""

import os
import sys
import platform

block_cipher = None

# Paths relative to this spec file (irisopcua/setup-wizard/)
# SPECPATH is set by PyInstaller to the directory containing the spec file
SPEC_DIR = os.path.abspath(SPECPATH)
IRISOPCUA_DIR = os.path.dirname(SPEC_DIR)

# Determine platform-specific binaries to bundle
if platform.system() == "Windows":
    bin_src = os.path.join(IRISOPCUA_DIR, "windows", "bin")
    binary_files = [
        (os.path.join(bin_src, "IrisOPCUA.dll"), os.path.join("windows", "bin")),
        (os.path.join(bin_src, "open62541.dll"), os.path.join("windows", "bin")),
        (os.path.join(bin_src, "libcrypto-1_1-x64.dll"), os.path.join("windows", "bin")),
    ]
else:
    bin_src = os.path.join(IRISOPCUA_DIR, "image-iris", "uacbin")
    binary_files = [
        (os.path.join(bin_src, "irisopcua.so"), os.path.join("image-iris", "uacbin")),
        (os.path.join(bin_src, "libopen62541.so.0"), os.path.join("image-iris", "uacbin")),
        (os.path.join(bin_src, "libcrypto.so.1.1"), os.path.join("image-iris", "uacbin")),
    ]

# Collect ObjectScript source files
objectscript_src = os.path.join(IRISOPCUA_DIR, "image-iris", "src")
objectscript_data = []
for root, dirs, files in os.walk(objectscript_src):
    for f in files:
        if f.endswith((".cls", ".inc")):
            src_path = os.path.join(root, f)
            # Preserve directory structure under image-iris/src/
            rel_path = os.path.relpath(root, IRISOPCUA_DIR)
            objectscript_data.append((src_path, rel_path))

# VERSION file
version_data = [(os.path.join(IRISOPCUA_DIR, "VERSION"), ".")]

# Combine all data files
all_datas = objectscript_data + version_data

# Filter out binaries that don't exist (e.g., building on wrong platform)
existing_binaries = [(src, dst) for src, dst in binary_files if os.path.isfile(src)]

a = Analysis(
    ["main.py"],
    pathex=[SPEC_DIR],
    binaries=existing_binaries,
    datas=all_datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="IRISOPCUASetup",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # GUI app, no console window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
