"""Step 2: Locate IRIS instance — auto-detect or manual browse."""

import tkinter as tk
from tkinter import ttk, filedialog

from wizard import WizardStep
from iris_utils import discover_instances, validate_iris_dir, IRISInstance


class LocateIRISStep(WizardStep):
    title = "Locate IRIS Instance"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Select the IRIS instance to install the OPC UA adapter into.",
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 10))

        # Instance list
        list_frame = ttk.LabelFrame(self, text="Detected Instances")
        list_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        columns = ("name", "directory")
        self.tree = ttk.Treeview(
            list_frame, columns=columns, show="headings", height=6, selectmode="browse"
        )
        self.tree.heading("name", text="Instance Name")
        self.tree.heading("directory", text="Install Directory")
        self.tree.column("name", width=180)
        self.tree.column("directory", width=440)

        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(5, 0), pady=5)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 5), pady=5)

        self.tree.bind("<<TreeviewSelect>>", self._on_select)

        # Buttons row
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill=tk.X, pady=(0, 5))

        self.refresh_btn = ttk.Button(
            btn_frame, text="Refresh", command=self._scan_instances
        )
        self.refresh_btn.pack(side=tk.LEFT)

        self.browse_btn = ttk.Button(
            btn_frame, text="Browse...", command=self._browse_folder
        )
        self.browse_btn.pack(side=tk.LEFT, padx=(8, 0))

        # Status
        self.status_var = tk.StringVar(value="")
        self.status_label = ttk.Label(self, textvariable=self.status_var, foreground="gray")
        self.status_label.pack(anchor=tk.W)

        self.instances = []

    def on_enter(self):
        if not self.instances:
            self._scan_instances()

    def _scan_instances(self):
        """Detect IRIS instances and populate the tree."""
        self.tree.delete(*self.tree.get_children())
        self.instances = discover_instances()

        if self.instances:
            for inst in self.instances:
                self.tree.insert("", tk.END, values=(inst.name, inst.install_dir))
            self.status_var.set(f"Found {len(self.instances)} instance(s)")
            # Auto-select first
            first = self.tree.get_children()[0]
            self.tree.selection_set(first)
            self.tree.focus(first)
            self._on_select(None)
        else:
            self.status_var.set("No instances found. Use Browse to select manually.")

    def _browse_folder(self):
        """Manual folder selection."""
        path = filedialog.askdirectory(title="Select IRIS Installation Directory")
        if not path:
            return
        if validate_iris_dir(path):
            import os
            name = os.path.basename(path)
            inst = IRISInstance(name, path)
            # Add to list if not already present
            existing_dirs = [i.install_dir.lower() for i in self.instances]
            if path.lower() not in existing_dirs:
                self.instances.append(inst)
                self.tree.insert("", tk.END, values=(inst.name, inst.install_dir))
            # Select it
            for item in self.tree.get_children():
                vals = self.tree.item(item, "values")
                if vals[1].lower() == path.lower():
                    self.tree.selection_set(item)
                    self.tree.focus(item)
                    break
            self._on_select(None)
        else:
            self.status_var.set(f"Invalid IRIS directory: irissession not found in {path}/bin/")

    def _on_select(self, event):
        """Handle tree selection change."""
        sel = self.tree.selection()
        if sel:
            vals = self.tree.item(sel[0], "values")
            name, directory = vals[0], vals[1]
            # Find matching instance
            for inst in self.instances:
                if inst.install_dir == directory:
                    self.state["iris_instance"] = inst
                    self.state["iris_dir"] = inst.install_dir
                    self.status_var.set(f"Selected: {inst.name}")
                    return

    def on_leave(self):
        if not self.state.get("iris_instance"):
            self.status_var.set("Please select an IRIS instance to continue.")
            return False
        return True

    def can_go_next(self):
        return self.state.get("iris_instance") is not None
