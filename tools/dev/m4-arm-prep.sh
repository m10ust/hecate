#!/bin/bash
# Hecate M4: on-screen receipts via the qs ipc receipts lane
# armWizardScreen renders a wizard step with a REAL engine report, then grim.
set -u
cd ~/Work/hecate || exit 1
R=receipts
E=io.github.m10ust.hecate/engine/hecate.py
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

echo "== engine reports for arming =="
python3 $E check-destination /home/m4/hecate-test/source-m4 /dev/shm/hecate-m4/c2w --transport local > /tmp/rep-ident-rig.json 2>&1; echo "local report rc=$?"
python3 $E check-destination /home/m4/hecate-test/source-m4 beelink:~/hecate-m4-c3 --transport ssh > /tmp/rep-ident-bee.json 2>&1; echo "ssh report rc=$?"
head -c 300 /tmp/rep-ident-rig.json; echo; echo ---; head -c 300 /tmp/rep-ident-bee.json; echo
