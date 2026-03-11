"""Main wizard window with frame-swapping navigation."""

import tkinter as tk
from tkinter import ttk, messagebox

from config import WINDOW_WIDTH, WINDOW_HEIGHT, TOTAL_STEPS


class WizardStep(ttk.Frame):
    """Base class for all wizard steps."""

    title = "Step"

    def __init__(self, parent, state):
        super().__init__(parent)
        self.state = state

    def on_enter(self):
        """Called when this step becomes visible. Override to refresh UI."""
        pass

    def on_leave(self):
        """Called when leaving this step. Return False to block navigation."""
        return True

    def can_go_next(self):
        """Return True if the Next button should be enabled."""
        return True


class WizardApp:
    """Main wizard application with Back/Next/Cancel/Finish navigation."""

    def __init__(self, root, step_classes):
        self.root = root
        self.root.title("IRIS OPC UA Adapter Setup")
        self.root.geometry(f"{WINDOW_WIDTH}x{WINDOW_HEIGHT}")
        self.root.resizable(False, False)

        # Shared state dict passed between steps
        self.state = {
            "iris_instance": None,
            "iris_dir": None,
            "username": "SuperUser",
            "password": "",
            "iis_prefix": "",
            "namespace": "OPCUA",
            "create_demo_creds": True,
            "auto_start_production": False,
            "binaries_installed": False,
            "iris_configured": False,
            "preflight_results": {},
        }

        self._build_ui()
        self._create_steps(step_classes)
        self._show_step(0)

    def _build_ui(self):
        """Build the wizard frame layout."""
        # Header
        self.header_frame = ttk.Frame(self.root)
        self.header_frame.pack(fill=tk.X, padx=15, pady=(12, 0))

        self.title_label = ttk.Label(
            self.header_frame, text="", font=("Segoe UI", 14, "bold")
        )
        self.title_label.pack(side=tk.LEFT)

        self.step_label = ttk.Label(
            self.header_frame, text="", font=("Segoe UI", 10), foreground="gray"
        )
        self.step_label.pack(side=tk.RIGHT)

        ttk.Separator(self.root, orient=tk.HORIZONTAL).pack(
            fill=tk.X, padx=15, pady=(8, 0)
        )

        # Content area
        self.content_frame = ttk.Frame(self.root)
        self.content_frame.pack(fill=tk.BOTH, expand=True, padx=15, pady=10)

        # Bottom separator + buttons
        ttk.Separator(self.root, orient=tk.HORIZONTAL).pack(fill=tk.X, padx=15)

        self.button_frame = ttk.Frame(self.root)
        self.button_frame.pack(fill=tk.X, padx=15, pady=10)

        self.cancel_btn = ttk.Button(
            self.button_frame, text="Cancel", command=self._on_cancel
        )
        self.cancel_btn.pack(side=tk.LEFT)

        self.finish_btn = ttk.Button(
            self.button_frame, text="Finish", command=self._on_finish
        )
        self.finish_btn.pack(side=tk.RIGHT, padx=(5, 0))

        self.next_btn = ttk.Button(
            self.button_frame, text="Next >", command=self._on_next
        )
        self.next_btn.pack(side=tk.RIGHT, padx=(5, 0))

        self.back_btn = ttk.Button(
            self.button_frame, text="< Back", command=self._on_back
        )
        self.back_btn.pack(side=tk.RIGHT)

    def _create_steps(self, step_classes):
        """Instantiate all step frames."""
        self.steps = []
        for cls in step_classes:
            step = cls(self.content_frame, self.state)
            self.steps.append(step)
        self.current_step = 0

    def _show_step(self, index):
        """Display the step at the given index."""
        # Hide current step
        for step in self.steps:
            step.pack_forget()

        self.current_step = index
        step = self.steps[index]
        step.pack(fill=tk.BOTH, expand=True)

        # Update header
        self.title_label.config(text=step.title)
        self.step_label.config(text=f"Step {index + 1} of {TOTAL_STEPS}")

        # Update button states
        self.back_btn.config(state=tk.NORMAL if index > 0 else tk.DISABLED)

        is_last = index == len(self.steps) - 1
        self.next_btn.pack_forget()
        self.finish_btn.pack_forget()
        if is_last:
            self.finish_btn.pack(side=tk.RIGHT, padx=(5, 0))
        else:
            self.next_btn.pack(side=tk.RIGHT, padx=(5, 0))

        step.on_enter()

    def _on_next(self):
        step = self.steps[self.current_step]
        if not step.on_leave():
            return
        if self.current_step < len(self.steps) - 1:
            self._show_step(self.current_step + 1)

    def _on_back(self):
        if self.current_step > 0:
            self._show_step(self.current_step - 1)

    def _on_cancel(self):
        if messagebox.askyesno("Cancel", "Are you sure you want to cancel the setup?"):
            self.root.destroy()

    def _on_finish(self):
        self.root.destroy()
