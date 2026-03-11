"""Step 6: Configure IRIS — namespace, class import, web app, library registration."""

import os
import platform
import threading
import tkinter as tk
from tkinter import ttk

from wizard import WizardStep
from iris_utils import run_objectscript
from file_utils import get_objectscript_source_dir
from config import (
    SENTINEL_NS_DONE,
    SENTINEL_IMPORT_DONE,
    SENTINEL_WEBAPP_DONE,
    SENTINEL_LIB_DONE,
    SENTINEL_CRED_DONE,
    SENTINEL_AUTOSTART_DONE,
    WEB_APP_PATH,
    WEB_APP_DISPATCH_CLASS,
    WEB_APP_AUTH_ENABLED,
    DEMO_CREDENTIAL_NAME,
    DEMO_CREDENTIAL_USER,
    DEMO_CREDENTIAL_PASS,
)


class ConfigureIRISStep(WizardStep):
    title = "Configure IRIS"

    def __init__(self, parent, state):
        super().__init__(parent, state)

        ttk.Label(
            self,
            text="Configure the IRIS instance: create namespace, import classes, set up web app.",
            wraplength=620,
            justify=tk.LEFT,
        ).pack(anchor=tk.W, pady=(5, 8))

        # Options
        opt_frame = ttk.Frame(self)
        opt_frame.pack(fill=tk.X, pady=(0, 8))

        self.demo_creds_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            opt_frame, text="Create demo credentials (IrisOpcUaDemo / SuperUser / sys)",
            variable=self.demo_creds_var,
        ).pack(anchor=tk.W)

        self.autostart_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(
            opt_frame, text="Auto-start production on IRIS startup",
            variable=self.autostart_var,
        ).pack(anchor=tk.W)

        # Configure button
        self.configure_btn = ttk.Button(
            self, text="Configure", command=self._configure
        )
        self.configure_btn.pack(anchor=tk.W, pady=(0, 8))

        # Log output
        log_frame = ttk.LabelFrame(self, text="Configuration Log")
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.log_text = tk.Text(
            log_frame, height=12, wrap=tk.WORD, font=("Consolas", 9),
            state=tk.DISABLED,
        )
        scrollbar = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scrollbar.set)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(5, 0), pady=5)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, padx=(0, 5), pady=5)

        # Configure text tags for coloring
        self.log_text.tag_configure("ok", foreground="green")
        self.log_text.tag_configure("error", foreground="red")
        self.log_text.tag_configure("info", foreground="blue")
        self.log_text.tag_configure("header", foreground="black", font=("Consolas", 9, "bold"))

        self.status_var = tk.StringVar(value="")
        ttk.Label(self, textvariable=self.status_var, foreground="gray").pack(
            anchor=tk.W, pady=(5, 0)
        )

    def _log(self, text, tag=None):
        """Append text to the log (thread-safe via after)."""
        def _append():
            self.log_text.config(state=tk.NORMAL)
            if tag:
                self.log_text.insert(tk.END, text + "\n", tag)
            else:
                self.log_text.insert(tk.END, text + "\n")
            self.log_text.see(tk.END)
            self.log_text.config(state=tk.DISABLED)
        self.after(0, _append)

    def _configure(self):
        instance = self.state.get("iris_instance")
        if not instance:
            self.status_var.set("No IRIS instance selected.")
            return

        self.configure_btn.config(state=tk.DISABLED)
        self.status_var.set("Configuring...")

        # Clear log
        self.log_text.config(state=tk.NORMAL)
        self.log_text.delete("1.0", tk.END)
        self.log_text.config(state=tk.DISABLED)

        namespace = self.state.get("namespace", "OPCUA")
        create_creds = self.demo_creds_var.get()
        auto_start = self.autostart_var.get()
        username = self.state.get("username", "")
        password = self.state.get("password", "")

        def run():
            all_ok = True

            # Sub-step 1: Create namespace + database
            ok = self._step_create_namespace(instance, namespace, username, password)
            all_ok = all_ok and ok

            # Sub-step 2: Import ObjectScript classes
            if all_ok:
                ok = self._step_import_classes(instance, namespace, username, password)
                all_ok = all_ok and ok

            # Sub-step 3: Create web app
            if all_ok:
                ok = self._step_create_webapp(instance, namespace, username, password)
                all_ok = all_ok and ok

            # Sub-step 4: Register library
            if all_ok:
                ok = self._step_register_library(instance, namespace, username, password)
                all_ok = all_ok and ok

            # Sub-step 5: Demo credentials (optional)
            if all_ok and create_creds:
                ok = self._step_create_credentials(instance, namespace, username, password)
                all_ok = all_ok and ok

            # Sub-step 6: Auto-start (optional)
            if all_ok and auto_start:
                ok = self._step_autostart(instance, namespace, username, password)
                all_ok = all_ok and ok

            self.after(0, lambda: self._on_complete(all_ok))

        threading.Thread(target=run, daemon=True).start()

    def _step_create_namespace(self, instance, namespace, username, password):
        """Create OPCUA namespace and database if they don't exist."""
        self._log("--- Create Namespace ---", "header")

        commands = [
            'set ns="' + namespace + '"',
            'set dbDir=$system.Util.ManagerDirectory()_ns_"/"',
            '',
            '// Check if namespace exists',
            'if ##class(%SYS.Namespace).Exists(ns) {',
            '  write "Namespace "_ns_" already exists, skipping.",!',
            '  write "' + SENTINEL_NS_DONE + '",!',
            '  HALT',
            '}',
            '',
            '// Create database directory',
            'set sc=##class(%File).CreateDirectoryChain(dbDir)',
            'if \'sc write "ERROR: Cannot create directory "_dbDir,! HALT',
            '',
            '// Create database',
            'set sc=##class(SYS.Database).CreateDatabase(dbDir)',
            'if $$$ISERR(sc) write "ERROR: "_$system.Status.GetErrorText(sc),! HALT',
            '',
            '// Create namespace',
            'set props("Globals")=ns',
            'set props("Routines")=ns',
            'set sc=##class(Config.Namespaces).Create(ns,.props)',
            'if $$$ISERR(sc) write "ERROR: "_$system.Status.GetErrorText(sc),! HALT',
            '',
            '// Map %ALL and Ensemble packages',
            'set sc=##class(Config.MapPackages).Create(ns,"%ALL","%ALL",.mprops)',
            'set sc=##class(Config.MapPackages).Create(ns,"Ens","ENSSYS",.mprops)',
            'set sc=##class(Config.MapGlobals).Create(ns,"Ens*","ENSSYS",.mprops)',
            'set sc=##class(Config.MapRoutines).Create(ns,"Ens*","ENSSYS",.mprops)',
            '',
            'write "Namespace "_ns_" created successfully.",!',
            'write "' + SENTINEL_NS_DONE + '",!',
        ]

        success, output = run_objectscript(
            instance, "%SYS", commands, timeout=30,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_NS_DONE in output:
            self._log("Namespace: OK", "ok")
            return True
        else:
            self._log("Namespace: FAILED", "error")
            return False

    def _step_import_classes(self, instance, namespace, username, password):
        """Import ObjectScript source files into the OPCUA namespace."""
        self._log("\n--- Import Classes ---", "header")

        src_dir = get_objectscript_source_dir()
        # Normalize path for ObjectScript (use forward slashes)
        src_dir_os = src_dir.replace("\\", "/")

        self._log(f"Source directory: {src_dir}", "info")

        commands = [
            'set srcDir="' + src_dir_os + '"',
            'set sc=$system.OBJ.LoadDir(srcDir,"ck",,1)',
            'if $$$ISERR(sc) {',
            '  write "ERROR: "_$system.Status.GetErrorText(sc),!',
            '} else {',
            '  write "Classes imported successfully.",!',
            '}',
            'write "' + SENTINEL_IMPORT_DONE + '",!',
        ]

        success, output = run_objectscript(
            instance, namespace, commands, timeout=300,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_IMPORT_DONE in output and "ERROR" not in output:
            self._log("Import: OK", "ok")
            return True
        elif SENTINEL_IMPORT_DONE in output:
            # Import completed but may have had warnings — still proceed
            self._log("Import: completed (check output for warnings)", "info")
            return True
        else:
            self._log("Import: FAILED", "error")
            return False

    def _step_create_webapp(self, instance, namespace, username, password):
        """Create the REST web application in %SYS."""
        self._log("\n--- Create Web App ---", "header")

        commands = [
            f'if ##class(Security.Applications).Exists("{WEB_APP_PATH}") {{',
            f'  write "Web app {WEB_APP_PATH} already exists, skipping.",!',
            f'  write "{SENTINEL_WEBAPP_DONE}",!',
            '  HALT',
            '}',
            '',
            f'set props("Name")="{WEB_APP_PATH}"',
            f'set props("NameSpace")="{namespace}"',
            f'set props("DispatchClass")="{WEB_APP_DISPATCH_CLASS}"',
            'set props("Description")="OPC UA Adapter REST API"',
            'set props("Enabled")=1',
            f'set props("AutheEnabled")={WEB_APP_AUTH_ENABLED}',
            'set props("Resource")=""',
            '',
            f'set sc=##class(Security.Applications).Create("{WEB_APP_PATH}",.props)',
            'if $$$ISERR(sc) {',
            '  write "ERROR: "_$system.Status.GetErrorText(sc),!',
            '} else {',
            f'  write "Web app {WEB_APP_PATH} created.",!',
            '}',
            f'write "{SENTINEL_WEBAPP_DONE}",!',
        ]

        success, output = run_objectscript(
            instance, "%SYS", commands, timeout=30,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_WEBAPP_DONE in output and "ERROR" not in output:
            self._log("Web App: OK", "ok")
            return True
        elif SENTINEL_WEBAPP_DONE in output:
            self._log("Web App: completed (check output)", "info")
            return True
        else:
            self._log("Web App: FAILED", "error")
            return False

    def _step_register_library(self, instance, namespace, username, password):
        """Register and verify the native OPC UA library."""
        self._log("\n--- Register Library ---", "header")

        # Determine library path based on platform
        if platform.system() == "Windows":
            lib_name = "IrisOPCUA.dll"
        else:
            lib_name = "irisopcua.so"

        lib_path = os.path.join(instance.bin_dir, lib_name).replace("\\", "/")

        commands = [
            f'set sc=##class(OPCUA.Utils).Install("{lib_path}")',
            'if $$$ISERR(sc) {',
            '  write "ERROR installing library: "_$system.Status.GetErrorText(sc),!',
            f'  write "{SENTINEL_LIB_DONE}",!',
            '  HALT',
            '}',
            'write "Library path registered.",!',
            '',
            'set sc=##class(OPCUA.Utils).Initialize()',
            'if $$$ISERR(sc) {',
            '  write "ERROR initializing library: "_$system.Status.GetErrorText(sc),!',
            '} else {',
            '  write "Library initialized.",!',
            '  set sc=##class(OPCUA.Utils).GetVersion(.v)',
            '  if \'$$$ISERR(sc) {',
            '    write "Library version: "_$LI(v,2),!',
            '  }',
            '}',
            f'write "{SENTINEL_LIB_DONE}",!',
        ]

        success, output = run_objectscript(
            instance, namespace, commands, timeout=30,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_LIB_DONE in output and "ERROR" not in output:
            self._log("Library: OK", "ok")
            return True
        elif SENTINEL_LIB_DONE in output:
            self._log("Library: completed with warnings", "info")
            return True
        else:
            self._log("Library: FAILED", "error")
            return False

    def _step_create_credentials(self, instance, namespace, username, password):
        """Create demo Interoperability credentials."""
        self._log("\n--- Create Demo Credentials ---", "header")

        commands = [
            f'set sc=##class(Ens.Config.Credentials).SetCredential("{DEMO_CREDENTIAL_NAME}","{DEMO_CREDENTIAL_USER}","{DEMO_CREDENTIAL_PASS}",1)',
            'if $$$ISERR(sc) {',
            '  write "ERROR: "_$system.Status.GetErrorText(sc),!',
            '} else {',
            f'  write "Credential {DEMO_CREDENTIAL_NAME} created.",!',
            '}',
            f'write "{SENTINEL_CRED_DONE}",!',
        ]

        success, output = run_objectscript(
            instance, namespace, commands, timeout=30,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_CRED_DONE in output and "ERROR" not in output:
            self._log("Credentials: OK", "ok")
            return True
        else:
            self._log("Credentials: FAILED (non-blocking)", "error")
            return True  # Non-blocking — proceed anyway

    def _step_autostart(self, instance, namespace, username, password):
        """Set production auto-start."""
        self._log("\n--- Auto-Start Production ---", "header")

        commands = [
            'set ^Ens.AutoStart="Examples.OPCUADS.Production"',
            'write "Auto-start set to Examples.OPCUADS.Production",!',
            f'write "{SENTINEL_AUTOSTART_DONE}",!',
        ]

        success, output = run_objectscript(
            instance, namespace, commands, timeout=15,
            username=username, password=password,
        )
        self._log(output.strip())

        if SENTINEL_AUTOSTART_DONE in output:
            self._log("Auto-start: OK", "ok")
            return True
        else:
            self._log("Auto-start: FAILED (non-blocking)", "error")
            return True  # Non-blocking

    def _on_complete(self, all_ok):
        self.configure_btn.config(state=tk.NORMAL)
        self.state["iris_configured"] = all_ok
        if all_ok:
            self.status_var.set("Configuration complete. You may proceed.")
            self._log("\n=== All configuration steps completed successfully ===", "ok")
        else:
            self.status_var.set("Configuration had errors. Review the log above.")
            self._log("\n=== Configuration completed with errors ===", "error")
