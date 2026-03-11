"""IRIS OPC UA Adapter Setup Wizard — Entry point."""

import sys
import os
import tkinter as tk

# Ensure the setup-wizard directory is on the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from wizard import WizardApp
from steps import ALL_STEPS


def main():
    root = tk.Tk()
    app = WizardApp(root, ALL_STEPS)
    root.mainloop()


if __name__ == "__main__":
    main()
