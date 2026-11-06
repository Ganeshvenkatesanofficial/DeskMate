"""Test isolation: point HOME (and so the DeskMate data dir) at a temp folder before any engine import."""

import os
import sys
import tempfile
from pathlib import Path

_TMP_HOME = Path(tempfile.mkdtemp(prefix="deskmate-test-home-"))
os.environ["HOME"] = str(_TMP_HOME)
os.environ["USERPROFILE"] = str(_TMP_HOME)
os.environ["APPDATA"] = str(_TMP_HOME / "AppData")

ENGINE = Path(__file__).resolve().parents[1]
if str(ENGINE) not in sys.path:
    sys.path.insert(0, str(ENGINE))
