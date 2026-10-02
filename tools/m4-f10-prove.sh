#!/bin/bash
# Hecate M4 finding-10 fix: prove --job and --also warn lanes live
set -u
cd ~/Work/hecate || exit 1
E=io.github.m10ust.hecate/engine/hecate.py

echo "== tests still green =="
python3 tools/test_independence.py | tail -1
python3 tools/test_identity.py | tail -1

echo
echo "== --job lane: candidate on bee vs job's bee corners (expect WARN) =="
python3 $E check-destination /home/m4/hecate-test/source-m4 beelink:/tmp/hecate-warn-c3 --transport ssh --job wizard-demo > /tmp/rep-job-warn.json; echo "rc=$? (0 = warn allowed)"
python3 -c "import json;r=json.load(open('/tmp/rep-job-warn.json'));print('verdict:',r['verdict']);print('warn:',[f['reason'][:80] for f in r['findings'] if f['kind']=='warn'])"

echo
echo "== --also lane: new-job corner 2 on bee, corner 3 candidate also bee (expect WARN) =="
python3 $E check-destination /home/m4/hecate-test/source-m4 beelink:/tmp/hecate-warn-c3 --transport ssh --also-transport ssh --also beelink:~/hecate-m4-c3 > /tmp/rep-also-warn.json; echo "rc=$?"
python3 -c "import json;r=json.load(open('/tmp/rep-also-warn.json'));print('verdict:',r['verdict']);print('warn:',[f['reason'][:80] for f in r['findings'] if f['kind']=='warn'])"

echo
echo "== pairwise still passes when nothing correlates =="
python3 $E check-destination /home/m4/hecate-test/source-m4 /dev/shm/hecate-m4/c2w --transport local > /tmp/rep-pass.json; echo "rc=$?"
python3 -c "import json;r=json.load(open('/tmp/rep-pass.json'));print('verdict:',r['verdict'])"
