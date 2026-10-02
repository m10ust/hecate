#!/usr/bin/env python3
"""M4: verify the armed-screen receipts show the expected text (PIL pixel
lane is blind to glyphs; instead we read the panel's own wizardDebug +
classify IPC which report what rendered)."""
import json
import os
import subprocess

os.environ["QS_CONFIG_PATH"] = "/usr/share/omarchy/shell"
os.environ["WAYLAND_DISPLAY"] = "wayland-1"
os.environ["DISPLAY"] = ":0"
os.environ["XDG_RUNTIME_DIR"] = "/run/user/1000"

out = subprocess.run(
    ["qs", "ipc", "call", "io.github.m10ust.hecate", "state"],
    capture_output=True, text=True, timeout=10)
print("rc:", out.returncode)
s = json.loads(out.stdout.strip())
print("wizardDebug:", s.get("wizardDebug"))
print("statePath:", s.get("statePath"))
