"""Step 4: Pre-flight checks — IRIS running, existing DLLs, namespace."""

import threading
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from iris_utils import check_iris_running, check_binaries_present, check_namespace_exists


class PreflightStep(WizardStep):
    title = "Pre-flight Checks"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Run pre-flight checks to verify the environment before installation.",
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 10))

        self.run_btn = ttk.Button(self, text="Run Checks", command=self._run_checks)
        self.run_btn.pack(anchor=tk.W, pady=(0, 10))

        # Checklist frame
        self.checks_frame = ttk.LabelFrame(self, text="Checklist")
        self.checks_frame.pack(fill=tk.BOTH, expand=True)

        self.check_rows = {}
        self._add_check_row("iris_running", "IRIS instance is running", "Required")
        self._add_check_row("binaries_present", "OPC UA binaries in bin/", "Info")
        self._add_check_row("namespace_exists", "OPCUA namespace exists", "Info")

        # Status
        self.status_var = tk.StringVar(value="Click 'Run Checks' to begin.")
        ttk.Label(self, textvariable=self.status_var, foreground="gray").pack(
            anchor=tk.W, pady=(8, 0)
        )

        self.checks_passed = False

    def _add_check_row(self, key, label, severity):
        row = ttk.Frame(self.checks_frame)
        row.pack(fill=tk.X, padx=10, pady=4)

        icon_var = tk.StringVar(value="\u25CB")  # empty circle
        icon_label = ttk.Label(row, textvariable=icon_var, width=3)
        icon_label.pack(side=tk.LEFT)

        ttk.Label(row, text=label, width=35, anchor=tk.W).pack(side=tk.LEFT)

        sev_label = ttk.Label(row, text=f"[{severity}]", foreground="gray", width=12)
        sev_label.pack(side=tk.LEFT)

        detail_var = tk.StringVar(value="Not checked")
        detail_label = ttk.Label(row, textvariable=detail_var, foreground="gray")
        detail_label.pack(side=tk.LEFT, fill=tk.X, expand=True)

        self.check_rows[key] = {
            "icon_var": icon_var,
            "icon_label": icon_label,
            "detail_var": detail_var,
            "detail_label": detail_label,
            "severity": severity,
        }

    def _set_check(self, key, passed, detail):
        row = self.check_rows[key]
        if passed:
            row["icon_var"].set("\u2714")  # checkmark
            row["icon_label"].config(foreground="green")
        elif row["severity"] == "Required":
            row["icon_var"].set("\u2718")  # X
            row["icon_label"].config(foreground="red")
        else:
            row["icon_var"].set("\u25CB")  # circle
            row["icon_label"].config(foreground="orange")
        row["detail_var"].set(detail)
        row["detail_label"].config(foreground="black")

    def _run_checks(self):
        instance = self.state.get("iris_instance")
        if not instance:
            self.status_var.set("No IRIS instance selected.")
            return

        self.run_btn.config(state=tk.DISABLED)
        self.status_var.set("Running checks...")

        def run():
            results = {}
            user = self.state.get("username", "")
            pwd = self.state.get("password", "")

            # Check IRIS running
            running, msg = check_iris_running(instance, username=user, password=pwd)
            results["iris_running"] = (running, msg)

            # Check binaries
            present, found = check_binaries_present(instance)
            if present:
                detail = f"Found: {', '.join(found)}"
            else:
                detail = "No OPC UA binaries found"
            results["binaries_present"] = (present, detail)

            # Check namespace
            ns = self.state.get("namespace", "OPCUA")
            exists, msg = check_namespace_exists(instance, ns, username=user, password=pwd)
            results["namespace_exists"] = (exists, msg)

            self.after(0, lambda: self._show_results(results))

        threading.Thread(target=run, daemon=True).start()

    def _show_results(self, results):
        self.run_btn.config(state=tk.NORMAL)

        for key, (passed, detail) in results.items():
            self._set_check(key, passed, detail)

        self.state["preflight_results"] = results

        # Only block if IRIS is not running
        iris_ok = results.get("iris_running", (False, ""))[0]
        self.checks_passed = iris_ok

        if iris_ok:
            self.status_var.set("Pre-flight checks complete. You may proceed.")
        else:
            self.status_var.set("IRIS must be running to continue. Please start IRIS and re-run checks.")

    def on_leave(self):
        if not self.checks_passed:
            self.status_var.set("Please run checks first. IRIS must be running.")
            return False
        return True
