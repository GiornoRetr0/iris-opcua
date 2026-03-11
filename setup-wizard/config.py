"""Constants and configuration for the IRIS OPC UA Setup Wizard."""

import os
import sys

# Version — read from VERSION file at runtime
VERSION_FILE = "VERSION"

# Default namespace
DEFAULT_NAMESPACE = "OPCUA"

# Library ID used by IRIS for the OPC UA native library
IRIS_OPCUA_LIBRARY_ID = 1039

# Web app configuration
WEB_APP_PATH = "/csp/opcua/api"
WEB_APP_DISPATCH_CLASS = "OPCUA.REST.Handler"
WEB_APP_AUTH_ENABLED = 64  # Basic Auth

# Demo credential
DEMO_CREDENTIAL_NAME = "IrisOpcUaDemo"
DEMO_CREDENTIAL_USER = "SuperUser"
DEMO_CREDENTIAL_PASS = "sys"

# Windows binaries (relative to project root irisopcua/)
WINDOWS_BINARIES = [
    "IrisOPCUA.dll",
    "open62541.dll",
]
WINDOWS_LIBCRYPTO = "libcrypto-1_1-x64.dll"

# Linux binaries (relative to project root irisopcua/)
LINUX_BINARIES = [
    "irisopcua.so",
    "libopen62541.so.0",
]
LINUX_LIBCRYPTO = "libcrypto.so.1.1"

# Windows binary source directory (relative to irisopcua/)
WINDOWS_BIN_SRC = os.path.join("windows", "bin")

# Linux binary source directory (relative to irisopcua/)
LINUX_BIN_SRC = os.path.join("image-iris", "uacbin")

# ObjectScript source directory (relative to irisopcua/)
OBJECTSCRIPT_SRC = os.path.join("image-iris", "src")

# IRIS detection paths
WINDOWS_IRIS_SEARCH_DIRS = [
    r"C:\InterSystems",
    r"D:\InterSystems",
]
LINUX_IRIS_SEARCH_DIRS = [
    "/usr/irissys",
    "/opt/intersystems",
    "/usr/local/intersystems",
]

# Windows registry key for IRIS instances
WINDOWS_REGISTRY_KEY = r"SOFTWARE\InterSystems\IRIS\Configurations"

# irissession binary name per platform
IRISSESSION_WINDOWS = "irissession.exe"
IRISSESSION_LINUX = "irissession"

# Sentinel strings for irissession output parsing
SENTINEL_OK = "WIZARD_OK"
SENTINEL_ERROR = "WIZARD_ERROR"
SENTINEL_NS_DONE = "NS_DONE"
SENTINEL_IMPORT_DONE = "IMPORT_DONE"
SENTINEL_WEBAPP_DONE = "WEBAPP_DONE"
SENTINEL_LIB_DONE = "LIB_DONE"
SENTINEL_CRED_DONE = "CRED_DONE"
SENTINEL_AUTOSTART_DONE = "AUTOSTART_DONE"

# Wizard window dimensions
WINDOW_WIDTH = 700
WINDOW_HEIGHT = 520

# Step count
TOTAL_STEPS = 8


def get_version():
    """Read version from VERSION file."""
    # Try bundled location first (PyInstaller)
    if getattr(sys, '_MEIPASS', None):
        path = os.path.join(sys._MEIPASS, VERSION_FILE)
    else:
        # Development: look relative to this file
        path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            VERSION_FILE,
        )
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except FileNotFoundError:
        return "unknown"
