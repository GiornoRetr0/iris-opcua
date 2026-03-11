"""Step 5: Copy native binaries to IRIS bin directory."""

import threading
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from file_utils import copy_binaries, get_binaries_to_copy


class InstallBinariesStep(WizardStep):
    title = "Install Binaries"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Copy OPC UA native libraries to the IRIS bin/ directory.",
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 10))

        self.install_btn = ttk.Button(
            self, text="Install Binaries", command=self._install
        )
        self.install_btn.pack(anchor=tk.W, pady=(0, 10))

        # Progress bar
        self.progress = ttk.Progressbar(self, mode="determinate", length=600)
        self.progress.pack(fill=tk.X, pady=(0, 8))

        # Result list
        self.result_frame = ttk.LabelFrame(self, text="Results")
        self.result_frame.pack(fill=tk.BOTH, expand=True)

        columns = ("file", "status", "detail")
        self.tree = ttk.Treeview(
            self.result_frame, columns=columns, show="headings", height=6
        )
        self.tree.heading("file", text="File")
        self.tree.heading("status", text="Status")
        self.tree.heading("detail", text="Detail")
        self.tree.column("file", width=180)
        self.tree.column("status", width=80)
        self.tree.column("detail", width=340)
        self.tree.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        self.status_var = tk.StringVar(value="")
        ttk.Label(self, textvariable=self.status_var, foreground="gray").pack(
            anchor=tk.W, pady=(5, 0)
        )

    def on_enter(self):
        instance = self.state.get("iris_instance")
        if instance:
            binaries, libcrypto = get_binaries_to_copy()
            total = len(binaries) + 1  # +1 for libcrypto
            self.progress["maximum"] = total
            self.progress["value"] = 0

    def _install(self):
        instance = self.state.get("iris_instance")
        if not instance:
            self.status_var.set("No IRIS instance selected.")
            return

        self.install_btn.config(state=tk.DISABLED)
        self.tree.delete(*self.tree.get_children())
        self.progress["value"] = 0
        self.status_var.set("Installing...")
        self.file_count = 0

        def progress_cb(filename, status, detail):
            self.after(0, lambda f=filename, s=status, d=detail: self._on_file_done(f, s, d))

        def run():
            results = copy_binaries(instance.bin_dir, progress_callback=progress_cb)
            errors = [r for r in results if r[1] == "ERROR"]
            self.after(0, lambda: self._on_complete(results, errors))

        threading.Thread(target=run, daemon=True).start()

    def _on_file_done(self, filename, status, detail):
        self.file_count += 1
        self.progress["value"] = self.file_count

        # Color-code status
        tag = status.lower()
        self.tree.insert("", tk.END, values=(filename, status, detail), tags=(tag,))
        self.tree.tag_configure("copied", foreground="green")
        self.tree.tag_configure("skipped", foreground="orange")
        self.tree.tag_configure("error", foreground="red")

    def _on_complete(self, results, errors):
        self.install_btn.config(state=tk.NORMAL)
        if errors:
            self.status_var.set(f"Completed with {len(errors)} error(s)")
            self.state["binaries_installed"] = False
        else:
            copied = sum(1 for r in results if r[1] == "COPIED")
            skipped = sum(1 for r in results if r[1] == "SKIPPED")
            self.status_var.set(f"Done: {copied} copied, {skipped} skipped")
            self.state["binaries_installed"] = True
