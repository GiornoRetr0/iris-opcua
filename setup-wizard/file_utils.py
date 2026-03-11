"""Binary copy operations with progress callbacks."""

import os
import sys
import shutil
import platform
from typing import Callable, List, Tuple, Optional

from config import (
    WINDOWS_BINARIES,
    LINUX_BINARIES,
    WINDOWS_LIBCRYPTO,
    LINUX_LIBCRYPTO,
    WINDOWS_BIN_SRC,
    LINUX_BIN_SRC,
    OBJECTSCRIPT_SRC,
)


def get_base_dir() -> str:
    """Get the base irisopcua/ directory (handles PyInstaller bundling)."""
    if getattr(sys, '_MEIPASS', None):
        return sys._MEIPASS
    # Development: this file is in irisopcua/setup-wizard/
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_source_bin_dir() -> str:
    """Get the directory containing platform binaries to install."""
    base = get_base_dir()
    if platform.system() == "Windows":
        return os.path.join(base, WINDOWS_BIN_SRC)
    else:
        return os.path.join(base, LINUX_BIN_SRC)


def get_objectscript_source_dir() -> str:
    """Get the directory containing ObjectScript source files."""
    return os.path.join(get_base_dir(), OBJECTSCRIPT_SRC)


def get_binaries_to_copy() -> Tuple[List[str], str]:
    """Return (list of required binaries, libcrypto name) for this platform."""
    if platform.system() == "Windows":
        return WINDOWS_BINARIES, WINDOWS_LIBCRYPTO
    else:
        return LINUX_BINARIES, LINUX_LIBCRYPTO


def copy_binaries(
    target_bin_dir: str,
    progress_callback: Optional[Callable[[str, str, str], None]] = None,
) -> List[Tuple[str, str]]:
    """
    Copy platform binaries to the IRIS bin directory.

    progress_callback(filename, status, detail) is called per file.
    status is one of: COPIED, SKIPPED, ERROR

    Returns list of (filename, status) tuples.
    """
    source_dir = get_source_bin_dir()
    binaries, libcrypto = get_binaries_to_copy()
    results = []

    # Copy required binaries
    for filename in binaries:
        src = os.path.join(source_dir, filename)
        dst = os.path.join(target_bin_dir, filename)
        status, detail = _copy_file(src, dst)
        results.append((filename, status))
        if progress_callback:
            progress_callback(filename, status, detail)

    # Copy libcrypto only if not already present
    src = os.path.join(source_dir, libcrypto)
    dst = os.path.join(target_bin_dir, libcrypto)
    if os.path.isfile(dst):
        status, detail = "SKIPPED", "Already exists in target (not overwriting)"
    else:
        status, detail = _copy_file(src, dst)
    results.append((libcrypto, status))
    if progress_callback:
        progress_callback(libcrypto, status, detail)

    return results


def _copy_file(src: str, dst: str) -> Tuple[str, str]:
    """Copy a single file. Returns (status, detail)."""
    if not os.path.isfile(src):
        return "ERROR", f"Source file not found: {src}"
    try:
        shutil.copy2(src, dst)
        return "COPIED", f"Copied to {dst}"
    except PermissionError:
        return "ERROR", f"Permission denied writing to {dst}"
    except Exception as e:
        return "ERROR", str(e)


def count_objectscript_files() -> Tuple[int, int]:
    """Count .cls and .inc files in the ObjectScript source directory."""
    src_dir = get_objectscript_source_dir()
    cls_count = 0
    inc_count = 0
    if not os.path.isdir(src_dir):
        return 0, 0
    for root, dirs, files in os.walk(src_dir):
        for f in files:
            if f.endswith(".cls"):
                cls_count += 1
            elif f.endswith(".inc"):
                inc_count += 1
    return cls_count, inc_count
