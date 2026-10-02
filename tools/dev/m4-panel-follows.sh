#!/bin/bash
# Hecate M4: panel-follows receipt (status page shows replaced corner)
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

# close wizard (openpanel alone re-opens with wizard armed; use summon/hide?
# simplest: the wizard closes on wizardDone; state page shows after. Try
# calling state to confirm jobs parsed, then shoot the panel as-is.
qs ipc call io.github.m10ust.hecate state >/dev/null 2>&1
qs ipc call io.github.m10ust.hecate classify
