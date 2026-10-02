#!/bin/bash
# Hecate M4 final: sync, reload-verify, full test ladder, validator both copies
set -u
cd ~/Work/hecate || exit 1
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

echo "== sync tree -> installed =="
rsync -a --delete --exclude '__pycache__' io.github.m10ust.hecate/ ~/.config/omarchy/plugins/io.github.m10ust.hecate/
diff -r --exclude '__pycache__' io.github.m10ust.hecate ~/.config/omarchy/plugins/io.github.m10ust.hecate && echo "TREE == INSTALLED"

echo
echo "== wait for plugin reload, then service alive + no QML errors =="
sleep 4
qs ipc call io.github.m10ust.hecate state >/dev/null 2>&1 && echo "ipc state: OK"
journalctl --user --since "-2 min" --no-pager 2>/dev/null | grep -iE 'qml.*(error|Error)' | grep -i hecate | head -5
echo "(no output above = no QML errors)"

echo
echo "== test ladder =="
python3 tools/test_independence.py | tail -1; echo "indep rc=$?"
python3 tools/test_identity.py | tail -1; echo "ident rc=$?"

echo
echo "== validator both copies =="
omarchy-plugin-validate io.github.m10ust.hecate && echo "tree OK"
omarchy-plugin-validate ~/.config/omarchy/plugins/io.github.m10ust.hecate && echo "installed OK"
