"""IRIS instance detection and irissession interaction utilities."""

import os
import sys
import subprocess
import platform
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from config import (
    WINDOWS_IRIS_SEARCH_DIRS,
    LINUX_IRIS_SEARCH_DIRS,
    WINDOWS_REGISTRY_KEY,
    IRISSESSION_WINDOWS,
    IRISSESSION_LINUX,
    SENTINEL_OK,
    SENTINEL_ERROR,
    WINDOWS_BINARIES,
    LINUX_BINARIES,
    WINDOWS_LIBCRYPTO,
    LINUX_LIBCRYPTO,
)


@dataclass
class IRISInstance:
    """Represents a detected IRIS installation."""
    name: str
    install_dir: str
    bin_dir: str = field(init=False)
    irissession_path: str = field(init=False)

    def __post_init__(self):
        self.bin_dir = os.path.join(self.install_dir, "bin")
        exe = IRISSESSION_WINDOWS if platform.system() == "Windows" else IRISSESSION_LINUX
        self.irissession_path = os.path.join(self.bin_dir, exe)

    def __str__(self):
        return f"{self.name} ({self.install_dir})"


def discover_instances() -> List[IRISInstance]:
    """Auto-detect IRIS instances on this machine."""
    instances = {}

    if platform.system() == "Windows":
        # Try Windows registry first
        try:
            import winreg
            key = winreg.OpenKey(
                winreg.HKEY_LOCAL_MACHINE, WINDOWS_REGISTRY_KEY, 0,
                winreg.KEY_READ | winreg.KEY_WOW64_64KEY
            )
            i = 0
            while True:
                try:
                    name = winreg.EnumKey(key, i)
                    sub = winreg.OpenKey(key, name)
                    try:
                        directory, _ = winreg.QueryValueEx(sub, "Directory")
                        if validate_iris_dir(directory):
                            instances[directory.lower()] = IRISInstance(name, directory)
                    except FileNotFoundError:
                        pass
                    finally:
                        winreg.CloseKey(sub)
                    i += 1
                except OSError:
                    break
            winreg.CloseKey(key)
        except (ImportError, OSError):
            pass

        # Path scan fallback
        for search_dir in WINDOWS_IRIS_SEARCH_DIRS:
            _scan_directory(search_dir, instances)
    else:
        # Linux path scan
        for search_dir in LINUX_IRIS_SEARCH_DIRS:
            if os.path.isdir(search_dir):
                # Check if this is itself an IRIS install
                if validate_iris_dir(search_dir):
                    key = search_dir.lower()
                    if key not in instances:
                        name = os.path.basename(search_dir)
                        instances[key] = IRISInstance(name, search_dir)
                # Also scan subdirectories
                _scan_directory(search_dir, instances)

    return list(instances.values())


def _scan_directory(search_dir: str, instances: dict):
    """Scan a directory for IRIS installations."""
    if not os.path.isdir(search_dir):
        return
    try:
        for entry in os.listdir(search_dir):
            full_path = os.path.join(search_dir, entry)
            if os.path.isdir(full_path) and validate_iris_dir(full_path):
                key = full_path.lower()
                if key not in instances:
                    instances[key] = IRISInstance(entry, full_path)
    except PermissionError:
        pass


def validate_iris_dir(path: str) -> bool:
    """Check that the given directory contains a valid IRIS installation."""
    exe = IRISSESSION_WINDOWS if platform.system() == "Windows" else IRISSESSION_LINUX
    return os.path.isfile(os.path.join(path, "bin", exe))


def run_objectscript(
    instance: IRISInstance,
    namespace: str,
    commands: List[str],
    timeout: int = 60,
    username: str = "",
    password: str = "",
) -> Tuple[bool, str]:
    """
    Execute ObjectScript commands via irissession subprocess.

    Prepends username/password for the login prompt, appends HALT.
    Returns (success, output). Success is determined by finding
    SENTINEL_OK in output.
    """
    # irissession prompts for Username/Password before accepting commands
    login_lines = []
    if username:
        login_lines.append(username)
        login_lines.append(password)

    script_lines = login_lines + list(commands) + ["HALT"]
    script_input = "\n".join(script_lines) + "\n"

    cmd = [instance.irissession_path, instance.name, "-U", namespace]

    # On Windows, irissession requires CREATE_NO_WINDOW to accept piped stdin;
    # without it the process hangs waiting for a console.
    kwargs = {}
    if platform.system() == "Windows":
        kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW

    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=instance.bin_dir,
            **kwargs,
        )
        stdout_bytes, stderr_bytes = proc.communicate(
            input=script_input.encode(), timeout=timeout,
        )
        output = stdout_bytes.decode("utf-8", errors="replace") + \
                 stderr_bytes.decode("utf-8", errors="replace")
        success = SENTINEL_OK in output or SENTINEL_ERROR not in output
        # If we explicitly used sentinels, check for them
        if SENTINEL_OK in script_input:
            success = SENTINEL_OK in output
        return success, output
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return False, f"Command timed out after {timeout} seconds"
    except FileNotFoundError:
        return False, f"irissession not found at {instance.irissession_path}"
    except Exception as e:
        return False, str(e)


def check_iris_running(
    instance: IRISInstance, username: str = "", password: str = "",
) -> Tuple[bool, str]:
    """Check if the IRIS instance is running by executing a simple command."""
    commands = [
        f'write "{SENTINEL_OK}",!',
    ]
    success, output = run_objectscript(
        instance, "%SYS", commands, timeout=15,
        username=username, password=password,
    )
    if SENTINEL_OK in output:
        return True, "IRIS is running"
    return False, f"IRIS does not appear to be running: {output[:200]}"


def check_binaries_present(instance: IRISInstance) -> Tuple[bool, List[str]]:
    """Check if OPC UA binaries are already in the IRIS bin directory."""
    if platform.system() == "Windows":
        binaries = WINDOWS_BINARIES + [WINDOWS_LIBCRYPTO]
    else:
        binaries = LINUX_BINARIES + [LINUX_LIBCRYPTO]

    found = []
    for b in binaries:
        if os.path.isfile(os.path.join(instance.bin_dir, b)):
            found.append(b)
    return len(found) > 0, found


def check_namespace_exists(
    instance: IRISInstance, namespace: str,
    username: str = "", password: str = "",
) -> Tuple[bool, str]:
    """Check if the given namespace already exists in IRIS."""
    commands = [
        f'write ##class(%SYS.Namespace).Exists("{namespace}")',
        f'write "{SENTINEL_OK}",!',
    ]
    success, output = run_objectscript(
        instance, "%SYS", commands, timeout=15,
        username=username, password=password,
    )
    # The Exists method returns 1 if namespace exists
    # Look for "1" before SENTINEL_OK
    if SENTINEL_OK in output:
        # Find the line with the result
        if "1" + SENTINEL_OK in output.replace("\n", "").replace("\r", "").replace(" ", ""):
            return True, f"Namespace {namespace} already exists"
        # More robust check
        lines = output.split("\n")
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("1"):
                return True, f"Namespace {namespace} already exists"
    return False, f"Namespace {namespace} does not exist"
