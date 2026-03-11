"""Step 1: Welcome screen with overview of what will be installed."""

import platform
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from config import get_version
from file_utils import count_objectscript_files


class WelcomeStep(WizardStep):
    title = "Welcome"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        self.is_macos = platform.system() == "Darwin"
        version = get_version()

        # Main description
        desc = ttk.Label(
            self,
            text=f"IRIS OPC UA Adapter Setup — v{version}",
            font=("Segoe UI", 12, "bold"),
        )
        desc.pack(anchor=tk.W, pady=(10, 8))

        intro = ttk.Label(
            self,
            text=(
                "This wizard will install the OPC UA adapter into an existing\n"
                "InterSystems IRIS instance. The following will be configured:"
            ),
            wraplength=620,
            justify=tk.LEFT,
        )
        intro.pack(anchor=tk.W, pady=(0, 10))

        # What will be installed
        cls_count, inc_count = count_objectscript_files()
        file_desc = f"{cls_count} classes + {inc_count} include file(s)"

        items = [
            ("Native binaries", "IrisOPCUA.dll + open62541.dll (Windows) or .so equivalents (Linux)"),
            ("OPCUA namespace", "Dedicated namespace and database for OPC UA classes"),
            ("ObjectScript classes", file_desc),
            ("REST web application", "/csp/opcua/api — browse, read, generate, test endpoints"),
            ("Library registration", "Register and verify the native OPC UA library"),
        ]

        for label, detail in items:
            row = ttk.Frame(self)
            row.pack(fill=tk.X, pady=2)
            bullet = ttk.Label(row, text="\u2022", font=("Segoe UI", 11))
            bullet.pack(side=tk.LEFT, padx=(10, 5))
            ttk.Label(row, text=label, font=("Segoe UI", 10, "bold")).pack(
                side=tk.LEFT
            )
            ttk.Label(row, text=f" — {detail}", wraplength=480, justify=tk.LEFT).pack(
                side=tk.LEFT, padx=(4, 0)
            )

        # macOS warning
        self.macos_frame = ttk.Frame(self)
        if self.is_macos:
            self.macos_frame.pack(fill=tk.X, pady=(20, 0))
            warn = ttk.Label(
                self.macos_frame,
                text=(
                    "macOS is not supported for native IRIS installation.\n"
                    "Please use the Docker-based setup instead:\n\n"
                    "    cd irisopcua && docker-compose up"
                ),
                foreground="red",
                font=("Segoe UI", 10),
                wraplength=600,
                justify=tk.LEFT,
            )
            warn.pack(anchor=tk.W, padx=10)

        # Platform info
        plat_text = f"Detected platform: {platform.system()} ({platform.machine()})"
        ttk.Label(self, text=plat_text, foreground="gray").pack(
            anchor=tk.W, pady=(20, 0)
        )

    def can_go_next(self):
        return not self.is_macos
