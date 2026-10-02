#!/bin/bash
# Hecate M4: warn lane receipt — two ssh corners, one host, two filesystems
set -u
cd ~/Work/hecate || exit 1
E=io.github.m10ust.hecate/engine/hecate.py

echo "== fresh 2-corner setup: /tmp local + beelink btrfs =="
python3 $E rm-job wizard-demo >/dev/null 2>&1
python3 $E add-job wizard-demo /home/m4/hecate-test/source-m4 /tmp/hecate-m4/c1 --horizon 48 | tail -1
python3 $E add-corner wizard-demo beelink:~/hecate-m4-c3 --transport ssh --horizon 48 | tail -1

echo
echo "== 3rd corner on the SAME host, different fs (bee /tmp tmpfs) — expect WARN =="
ssh beelink 'mkdir -p /tmp/hecate-warn-c3'
python3 $E add-corner wizard-demo beelink:/tmp/hecate-warn-c3 --transport ssh --horizon 48 > /tmp/m4-warn3.out 2>&1
echo "rc=$? (expect 5 without ack)"
grep -A3 'WARN' /tmp/m4-warn3.out | head -8

echo
echo "== with --accept-warning — expect rc 0 + independenceAck in state =="
python3 $E add-corner wizard-demo beelink:/tmp/hecate-warn-c3 --transport ssh --horizon 48 --accept-warning > /tmp/m4-warn4.out 2>&1
echo "rc=$?"
tail -1 /tmp/m4-warn4.out
echo "-- cat state (the acceptance-4 receipt):"
python3 -c "import json;s=json.load(open('/home/m4/.local/state/hecate/state.json'));c=[x for x in s['jobs'][0]['corners'] if 'hecate-warn-c3' in x['destination']][0];print(json.dumps(c,indent=1))"
