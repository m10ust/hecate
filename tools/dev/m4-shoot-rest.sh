#!/bin/bash
# Hecate M4: schedule + first-run screens, wizard's warning screen, panel-follows
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000
E=io.github.m10ust.hecate/engine/hecate.py

echo "== 1. schedule screen (step 4) =="
qs ipc call io.github.m10ust.hecate wizardscreen 4 '{}' >/dev/null 2>&1
sleep 1.4
grim -t png receipts/m4-11-schedule.png && ls -la receipts/m4-11-schedule.png

echo "== 2. first-run truth screen (step 5) =="
qs ipc call io.github.m10ust.hecate wizardscreen 5 '{}' >/dev/null 2>&1
sleep 1.4
grim -t png receipts/m4-12-firstrun.png && ls -la receipts/m4-12-firstrun.png

echo "== 3. warning screen with a REAL warn report (the wizard's own copy) =="
# source + corner on same machine different fs? warn needs same-power pair:
# simplest real report: two ssh corners one host. Use check-destination? that
# checks source-vs-candidate only. Arm the screen with the report from an
# add-corner WARN attempt: capture via check-destination against a job.
python3 $E check-destination /home/m4/hecate-test/source-m4 beelink:/tmp/hecate-warn-c3 --transport ssh > /tmp/rep-warn.json 2>&1 || true
cat /tmp/rep-warn.json | head -c 200; echo
qs ipc call io.github.m10ust.hecate wizardscreen 3 "$(cat /tmp/rep-warn.json)" >/dev/null 2>&1
sleep 1.4
grim -t png receipts/m4-13-warn-live.png && ls -la receipts/m4-13-warn-live.png

echo "== 4. panel follows the replaced corner (status page after re-entry) =="
qs ipc call io.github.m10ust.hecate openpanel >/dev/null 2>&1
sleep 1.6
grim -t png receipts/m4-14-panel-follows.png && ls -la receipts/m4-14-panel-follows.png
