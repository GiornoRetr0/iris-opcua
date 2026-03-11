"""Step 8: Summary — recap of what was done with clickable links."""

import webbrowser
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from config import WEB_APP_PATH, get_version


class SummaryStep(WizardStep):
    title = "Summary"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Installation Summary",
            font=("Segoe UI", 12, "bold"),
        ).pack(anchor=tk.W, pady=(5, 8))

        # Summary table
        self.table_frame = ttk.Frame(self)
        self.table_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        columns = ("item", "status", "detail")
        self.tree = ttk.Treeview(
            self.table_frame, columns=columns, show="headings", height=8
        )
        self.tree.heading("item", text="Item")
        self.tree.heading("status", text="Status")
        self.tree.heading("detail", text="Detail")
        self.tree.column("item", width=160)
        self.tree.column("status", width=80)
        self.tree.column("detail", width=380)
        self.tree.pack(fill=tk.BOTH, expand=True)

        self.tree.tag_configure("pass", foreground="green")
        self.tree.tag_configure("fail", foreground="red")
        self.tree.tag_configure("skip", foreground="gray")

        # Links frame
        self.links_frame = ttk.LabelFrame(self, text="Quick Links")
        self.links_frame.pack(fill=tk.X, pady=(0, 5))

        self.portal_link = tk.Label(
            self.links_frame,
            text="",
            fg="blue",
            cursor="hand2",
            font=("Segoe UI", 9, "underline"),
        )
        self.portal_link.pack(anchor=tk.W, padx=8, pady=(5, 2))
        self.portal_link.bind("<Button-1>", lambda e: self._open_link(self.portal_url))

        self.api_link = tk.Label(
            self.links_frame,
            text="",
            fg="blue",
            cursor="hand2",
            font=("Segoe UI", 9, "underline"),
        )
        self.api_link.pack(anchor=tk.W, padx=8, pady=(2, 5))
        self.api_link.bind("<Button-1>", lambda e: self._open_link(self.api_url))

        self.portal_url = ""
        self.api_url = ""

        ttk.Label(
            self,
            text="Click Finish to close the wizard.",
            foreground="gray",
        ).pack(anchor=tk.W, pady=(5, 0))

    def on_enter(self):
        """Populate summary from state."""
        self.tree.delete(*self.tree.get_children())

        instance = self.state.get("iris_instance")
        prefix = self.state.get("iis_prefix", "")
        version = get_version()

        # Instance
        if instance:
            self.tree.insert("", tk.END, values=(
                "IRIS Instance", "OK", f"{instance.name} — {instance.install_dir}"
            ), tags=("pass",))
        else:
            self.tree.insert("", tk.END, values=(
                "IRIS Instance", "N/A", "Not selected"
            ), tags=("skip",))

        # Version
        self.tree.insert("", tk.END, values=(
            "Adapter Version", "OK", version
        ), tags=("pass",))

        # Binaries
        if self.state.get("binaries_installed"):
            self.tree.insert("", tk.END, values=(
                "Native Binaries", "OK", "Copied to bin/"
            ), tags=("pass",))
        else:
            self.tree.insert("", tk.END, values=(
                "Native Binaries", "SKIP", "Not installed"
            ), tags=("skip",))

        # IRIS Configuration
        if self.state.get("iris_configured"):
            ns = self.state.get("namespace", "OPCUA")
            self.tree.insert("", tk.END, values=(
                "Namespace", "OK", ns
            ), tags=("pass",))
            self.tree.insert("", tk.END, values=(
                "Classes", "OK", "Imported into " + ns
            ), tags=("pass",))
            self.tree.insert("", tk.END, values=(
                "Web App", "OK", WEB_APP_PATH
            ), tags=("pass",))
            self.tree.insert("", tk.END, values=(
                "Library", "OK", "Registered and initialized"
            ), tags=("pass",))
        else:
            self.tree.insert("", tk.END, values=(
                "IRIS Config", "SKIP", "Not configured"
            ), tags=("skip",))

        # Build URLs
        self.portal_url = f"http://localhost{prefix}/csp/sys/UtilHome.csp"
        self.api_url = f"http://localhost{prefix}{WEB_APP_PATH}/ping"

        self.portal_link.config(text=f"Management Portal: {self.portal_url}")
        self.api_link.config(text=f"REST API Ping: {self.api_url}")

    def _open_link(self, url):
        if url:
            webbrowser.open(url)
