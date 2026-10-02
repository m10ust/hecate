#!/bin/bash
# Hecate M4: warning screen receipt with a real --also warn report
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

qs ipc call io.github.m10ust.hecate wizardscreen 3 "$(cat /tmp/rep-also-warn.json)" >/dev/null 2>&1
sleep 1.4
grim -t png receipts/m4-13-warn-live.png
python3 tools/zoom_ocr.py receipts/m4-13-warn-live.png 1795 5 1640 760 /tmp/ocr-warnlive.png 4
tesseract /tmp/ocr-warnlive.png /tmp/ocr-warnlive --psm 6 2>/dev/null
grep -vE '^\s*$' /tmp/ocr-warnlive.txt | head -18
