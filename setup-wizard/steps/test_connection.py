"""Step 7: Test Connection — REST /ping and OPC UA /test (optional)."""

import threading
import urllib.request
import urllib.error
import base64
import json
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from config import WEB_APP_PATH


class TestConnectionStep(WizardStep):
    title = "Test Connection"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Optionally test the REST API and OPC UA connectivity. You can skip this step.",
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 10))

        # --- REST API Ping ---
        api_frame = ttk.LabelFrame(self, text="REST API Ping")
        api_frame.pack(fill=tk.X, pady=(0, 10))

        row1 = ttk.Frame(api_frame)
        row1.pack(fill=tk.X, padx=8, pady=5)

        self.ping_btn = ttk.Button(row1, text="Ping API", command=self._ping_api)
        self.ping_btn.pack(side=tk.LEFT)

        self.ping_url_var = tk.StringVar()
        ttk.Label(row1, textvariable=self.ping_url_var, foreground="gray").pack(
            side=tk.LEFT, padx=(10, 0)
        )

        self.ping_result_var = tk.StringVar(value="")
        self.ping_result_label = ttk.Label(api_frame, textvariable=self.ping_result_var)
        self.ping_result_label.pack(anchor=tk.W, padx=8, pady=(0, 5))

        # --- OPC UA Test ---
        opc_frame = ttk.LabelFrame(self, text="OPC UA Connection Test")
        opc_frame.pack(fill=tk.X, pady=(0, 10))

        row2 = ttk.Frame(opc_frame)
        row2.pack(fill=tk.X, padx=8, pady=5)

        ttk.Label(row2, text="OPC UA URL:").pack(side=tk.LEFT)
        self.opcua_url_var = tk.StringVar(value="opc.tcp://localhost:48010")
        ttk.Entry(row2, textvariable=self.opcua_url_var, width=40).pack(
            side=tk.LEFT, padx=(8, 8)
        )
        self.test_btn = ttk.Button(row2, text="Test", command=self._test_opcua)
        self.test_btn.pack(side=tk.LEFT)

        self.opc_result_var = tk.StringVar(value="")
        self.opc_result_label = ttk.Label(opc_frame, textvariable=self.opc_result_var)
        self.opc_result_label.pack(anchor=tk.W, padx=8, pady=(0, 5))

        # Response detail
        detail_frame = ttk.LabelFrame(self, text="Response")
        detail_frame.pack(fill=tk.BOTH, expand=True)

        self.detail_text = tk.Text(
            detail_frame, height=6, wrap=tk.WORD, font=("Consolas", 9),
            state=tk.DISABLED,
        )
        self.detail_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

    def on_enter(self):
        prefix = self.state.get("iis_prefix", "")
        url = f"http://localhost{prefix}{WEB_APP_PATH}/ping"
        self.ping_url_var.set(url)

    def _get_auth_header(self):
        """Build Basic Auth header from state credentials."""
        user = self.state.get("username", "SuperUser")
        pwd = self.state.get("password", "")
        creds = base64.b64encode(f"{user}:{pwd}".encode()).decode()
        return f"Basic {creds}"

    def _ping_api(self):
        self.ping_btn.config(state=tk.DISABLED)
        self.ping_result_var.set("Testing...")
        self.ping_result_label.config(foreground="gray")

        url = self.ping_url_var.get()

        def run():
            try:
                req = urllib.request.Request(url)
                req.add_header("Authorization", self._get_auth_header())
                with urllib.request.urlopen(req, timeout=10) as resp:
                    body = resp.read().decode("utf-8")
                    self.after(0, lambda: self._show_ping_result(True, body))
            except Exception as e:
                self.after(0, lambda: self._show_ping_result(False, str(e)))

        threading.Thread(target=run, daemon=True).start()

    def _show_ping_result(self, success, body):
        self.ping_btn.config(state=tk.NORMAL)
        self._set_detail(body)
        if success:
            self.ping_result_var.set("OK")
            self.ping_result_label.config(foreground="green")
        else:
            self.ping_result_var.set(f"FAILED: {body[:100]}")
            self.ping_result_label.config(foreground="red")

    def _test_opcua(self):
        self.test_btn.config(state=tk.DISABLED)
        self.opc_result_var.set("Testing...")
        self.opc_result_label.config(foreground="gray")

        prefix = self.state.get("iis_prefix", "")
        opcua_url = self.opcua_url_var.get().strip()
        url = f"http://localhost{prefix}{WEB_APP_PATH}/test?url={urllib.request.quote(opcua_url, safe='')}"

        def run():
            try:
                req = urllib.request.Request(url)
                req.add_header("Authorization", self._get_auth_header())
                with urllib.request.urlopen(req, timeout=15) as resp:
                    body = resp.read().decode("utf-8")
                    self.after(0, lambda: self._show_opc_result(True, body))
            except Exception as e:
                self.after(0, lambda: self._show_opc_result(False, str(e)))

        threading.Thread(target=run, daemon=True).start()

    def _show_opc_result(self, success, body):
        self.test_btn.config(state=tk.NORMAL)
        self._set_detail(body)
        if success:
            try:
                data = json.loads(body)
                if data.get("status") == "ok":
                    self.opc_result_var.set("OK — Connected to OPC UA server")
                    self.opc_result_label.config(foreground="green")
                    return
            except (json.JSONDecodeError, KeyError):
                pass
            self.opc_result_var.set("Response received (check detail)")
            self.opc_result_label.config(foreground="orange")
        else:
            self.opc_result_var.set(f"FAILED: {body[:100]}")
            self.opc_result_label.config(foreground="red")

    def _set_detail(self, text):
        self.detail_text.config(state=tk.NORMAL)
        self.detail_text.delete("1.0", tk.END)
        # Pretty-print JSON if possible
        try:
            data = json.loads(text)
            text = json.dumps(data, indent=2)
        except (json.JSONDecodeError, TypeError):
            pass
        self.detail_text.insert(tk.END, text)
        self.detail_text.config(state=tk.DISABLED)

    def on_leave(self):
        return True  # Always allow proceeding
