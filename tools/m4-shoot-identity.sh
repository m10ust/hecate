#!/bin/bash
# Hecate M4: shoot on-screen identity receipts via the qs ipc receipts lane
set -u
cd ~/Work/hecate || exit 1
R=receipts
export QS_CONFIG_PATH=/usr/share/omarchy/shell
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/1000

# step 1 = corner screen; report = real engine JSON
shoot() {
  local json="$1" out="$2"
  qs ipc call io.github.m10ust.hecate wizardscreen 1 "$(cat $json)" 2>&1 | head -2
  sleep 1.4   # open + arm + render
  grim -t png "$R/$out" 2>&1
  ls -la "$R/$out"
}

echo "== rig NVMe identity on screen =="
python3 io.github.m10ust.hecate/engine/hecate.py check-destination \
  /home/m4/hecate-test/source-m4 /home/m4/hecate-test/dest-nvme --transport local > /tmp/rep-rig.json 2>&1 || true
mkdir -p /home/m4/hecate-test/dest-nvme
python3 io.github.m10ust.hecate/engine/hecate.py check-destination \
  /home/m4/hecate-test/source-m4 /home/m4/hecate-test/dest-nvme --transport local > /tmp/rep-rig.json 2>&1
head -c 260 /tmp/rep-rig.json; echo
shoot /tmp/rep-rig.json m4-7-identity-rig-nvme.png

echo
echo "== beelink ssh identity on screen =="
shoot /tmp/rep-ident-bee.json m4-8-identity-bee-ssh.png

echo
echo "== tmpfs unknown-with-reason on screen =="
shoot /tmp/rep-ident-rig.json m4-9-identity-tmpfs-unknown.png
