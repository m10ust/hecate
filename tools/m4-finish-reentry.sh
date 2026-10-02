#!/bin/bash
# Hecate M4: verify the measured line rendered on screen, then complete re-entry
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
E=io.github.m10ust.hecate/engine/hecate.py

echo "== OCR the fresh measured shot (right-panel bbox from the diff lane) =="
python3 tools/m4-diff-shot.py receipts/m4-10-source-measured.png receipts/m4-8-identity-bee-ssh.png
python3 tools/zoom_ocr.py receipts/m4-10-source-measured.png 1795 5 1640 700 /tmp/ocr-m410.png 4
tesseract /tmp/ocr-m410.png /tmp/ocr-m410 --psm 6 2>/dev/null
grep -vE '^\s*$' /tmp/ocr-m410.txt | head -14

echo
echo "== re-entry: replace corner 1 (local->local, no warn expected) =="
python3 $E replace-corner wizard-demo 1 /dev/shm/hecate-m4/c1-elsewhere --transport local --accept-warning | tail -2
python3 $E state | python3 -c "import json,sys;s=json.load(sys.stdin);j=s['jobs'][0];[print('after:',c['index'],c['destination'],'lastRun=',c.get('lastRun'),'ack=',('independenceAck' in c)) for c in j['corners']]"
