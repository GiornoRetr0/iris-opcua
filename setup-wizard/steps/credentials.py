"""Step 3: Credentials and IIS prefix configuration."""

import threading
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from iris_utils import check_iris_running
from config import SENTINEL_OK


class CredentialsStep(WizardStep):
    title = "Credentials"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text=(
                "Enter credentials for the IRIS REST API (used for testing).\n"
                "The irissession tool typically uses OS authentication."
            ),
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 12))

        # Form grid
        form = ttk.Frame(self)
        form.pack(fill=tk.X, pady=(0, 8))

        # Username
        ttk.Label(form, text="Username:").grid(row=0, column=0, sticky=tk.W, pady=4)
        self.username_var = tk.StringVar(value="SuperUser")
        ttk.Entry(form, textvariable=self.username_var, width=30).grid(
            row=0, column=1, sticky=tk.W, padx=(8, 0), pady=4
        )

        # Password
        ttk.Label(form, text="Password:").grid(row=1, column=0, sticky=tk.W, pady=4)
        self.password_var = tk.StringVar()
        ttk.Entry(form, textvariable=self.password_var, width=30, show="*").grid(
            row=1, column=1, sticky=tk.W, padx=(8, 0), pady=4
        )

        # IIS URL prefix
        ttk.Label(form, text="IIS URL prefix:").grid(row=2, column=0, sticky=tk.W, pady=4)
        self.prefix_var = tk.StringVar()
        prefix_entry = ttk.Entry(form, textvariable=self.prefix_var, width=30)
        prefix_entry.grid(row=2, column=1, sticky=tk.W, padx=(8, 0), pady=4)
        ttk.Label(
            form,
            text='e.g. /iris251 — leave empty if not using IIS',
            foreground="gray",
        ).grid(row=2, column=2, sticky=tk.W, padx=(8, 0), pady=4)

        # Test connection button
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill=tk.X, pady=(5, 0))

        self.test_btn = ttk.Button(
            btn_frame, text="Test irissession", command=self._test_connection
        )
        self.test_btn.pack(side=tk.LEFT)

        self.test_status = tk.StringVar(value="")
        self.test_label = ttk.Label(btn_frame, textvariable=self.test_status)
        self.test_label.pack(side=tk.LEFT, padx=(10, 0))

        # Result display
        self.result_frame = ttk.LabelFrame(self, text="Test Output")
        self.result_frame.pack(fill=tk.BOTH, expand=True, pady=(10, 0))

        self.result_text = tk.Text(
            self.result_frame, height=8, wrap=tk.WORD, font=("Consolas", 9),
            state=tk.DISABLED,
        )
        self.result_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

    def on_enter(self):
        # Pre-fill from state
        if self.state.get("username"):
            self.username_var.set(self.state["username"])
        if self.state.get("password"):
            self.password_var.set(self.state["password"])
        if self.state.get("iis_prefix"):
            self.prefix_var.set(self.state["iis_prefix"])

    def _test_connection(self):
        """Test irissession connectivity in a background thread."""
        instance = self.state.get("iris_instance")
        if not instance:
            self.test_status.set("No IRIS instance selected")
            return

        self.test_btn.config(state=tk.DISABLED)
        self.test_status.set("Testing...")
        self._set_result_text("")

        def run():
            user = self.username_var.get().strip()
            pwd = self.password_var.get()
            running, msg = check_iris_running(instance, username=user, password=pwd)
            self.after(0, lambda: self._show_test_result(running, msg))

        threading.Thread(target=run, daemon=True).start()

    def _show_test_result(self, success, output):
        self.test_btn.config(state=tk.NORMAL)
        if success:
            self.test_status.set("OK — irissession is working")
            self.test_label.config(foreground="green")
        else:
            self.test_status.set("FAILED")
            self.test_label.config(foreground="red")
        self._set_result_text(output)

    def _set_result_text(self, text):
        self.result_text.config(state=tk.NORMAL)
        self.result_text.delete("1.0", tk.END)
        self.result_text.insert(tk.END, text)
        self.result_text.config(state=tk.DISABLED)

    def on_leave(self):
        self.state["username"] = self.username_var.get().strip()
        self.state["password"] = self.password_var.get()
        self.state["iis_prefix"] = self.prefix_var.get().strip()
        return True
