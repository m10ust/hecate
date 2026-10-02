#!/bin/bash
# Hecate M4: re-shoot source-measured (verifiable) + reentry-replace receipts
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
E=io.github.m10ust.hecate/engine/hecate.py

echo "== 1. source-measured screen with a REAL measure report =="
python3 $E measure-source /home/m4/hecate-test/source-m4 > /tmp/rep-measure.json
cat /tmp/rep-measure.json
qs ipc call io.github.m10ust.hecate wizardscreen 0 "$(cat /tmp/rep-measure.json)" >/dev/null 2>&1
sleep 1.4
grim -t png receipts/m4-10-source-measured.png
ls -la receipts/m4-10-source-measured.png

echo
echo "== 2. re-entry replace receipt: corner through the wizard, engine writes =="
python3 $E state | python3 -c "import json,sys;s=json.load(sys.stdin);j=s['jobs'][0];print('before:',[ (c['index'],c['destination']) for c in j['corners']])"
mkdir -p /dev/shm/hecate-m4/c1-elsewhere
python3 $E replace-corner wizard-demo 1 /dev/shm/hecate-m4/c1-elsewhere --transport local | tail -2
python3 $E state | python3 -c "import json,sys;s=json.load(sys.stdin);j=s['jobs'][0];print('after:',[ (c['index'],c['destination'],c.get('lastRun')) for c in j['corners']])"
