"""Wizard step modules."""

from steps.welcome import WelcomeStep
from steps.locate_iris import LocateIRISStep
from steps.credentials import CredentialsStep
from steps.preflight import PreflightStep
from steps.install_binaries import InstallBinariesStep
from steps.configure_iris import ConfigureIRISStep
from steps.test_connection import TestConnectionStep
from steps.summary import SummaryStep

ALL_STEPS = [
    WelcomeStep,
    LocateIRISStep,
    CredentialsStep,
    PreflightStep,
    InstallBinariesStep,
    ConfigureIRISStep,
    TestConnectionStep,
    SummaryStep,
]
