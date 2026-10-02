#!/usr/bin/env python3
"""Hecate M3 unit tests — the independence check on fixture identities.

The check's logic lanes (refuse / warn / unknown / cloud / pass) are tested
on declared fixture data so they do not depend on which physical drives
happen to be plugged in (M3 brief). The live paths (st_dev on real dirs,
the ssh probe) are exercised by the acceptance receipts, not here.

Usage: python3 test_independence.py   (exit 0 = all assertions hold)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "io.github.m10ust.hecate" / "engine"))
import hecate  # noqa: E402

PASS, FAIL = 0, []


def check(label, cond, detail=""):
    global PASS
    if cond:
        PASS += 1
    else:
        FAIL.append(f"{label}{' — ' + detail if detail else ''}")


def run(*, src=None, corners=()):
    parts = []
    if src is not None:
        parts.append({"index": "source", "transport": "local", "identity": src})
    for idx, tr, ident in corners:
        parts.append({"index": idx, "transport": tr, "identity": ident})
    return hecate.independence_check(parts)


def kinds(rep, kind):
    return [f for f in rep["findings"] if f["kind"] == kind]


# ---- refuse: same filesystem, by UUID (strongest evidence) -----------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "local", {"dev": 3, "fsuuid": "U-2"})])
check("same-UUID pair refuses", rep["verdict"] == "refuse", rep["verdict"])
r = kinds(rep, "refuse")
check("refuse names both corners", r and r[0]["corners"] == [1, 2], str(r))
check("refuse evidence is the UUID", r and "U-2" in r[0]["evidence"], str(r))

# ---- refuse: same filesystem by st_dev when UUIDs unreadable ----------------
rep = run(src={"dev": 1},
          corners=[(1, "local", {"dev": 31}), (2, "local", {"dev": 31})])
check("same-st_dev pair refuses", rep["verdict"] == "refuse", rep["verdict"])
r = kinds(rep, "refuse")
check("st_dev evidence names the number", r and "st_dev 31" in r[0]["evidence"], str(r))

# ---- pass: different filesystems -------------------------------------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "local", {"dev": 3, "fsuuid": "U-3"})])
check("distinct local filesystems still warn for shared power", rep["verdict"] == "warn" and not kinds(rep, "refuse"), str(rep))

# ---- st_dev not consulted when both UUIDs readable (cross-host spurious) ----
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 30, "fsuuid": "U-2"}),
                   (2, "ssh", {"host": "bee", "dev": 30, "fsuuid": "U-3"})])
check("equal st_dev across hosts with distinct UUIDs does NOT refuse",
      rep["verdict"] == "pass", str(kinds(rep, "refuse")))

# ---- st_dev not consulted ACROSS HOSTS even with no UUIDs (finding 9) -------
# rig /tmp and bee /tmp have both been st_dev 57 on this fleet; the collision
# is per-kernel coincidence and must not refuse. No UUIDs on either side.
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 57}),
                   (2, "ssh", {"host": "bee", "dev": 57})])
check("equal st_dev across hosts with NO UUIDs does not refuse (per-kernel ids)",
      rep["verdict"] == "pass", str(kinds(rep, "refuse")))

# ...but the same comparison inside ONE kernel still refuses (the fallback
# keeps its teeth: two tmpfs corners on the local machine)
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 57}),
                   (2, "local", {"dev": 57})])
check("equal st_dev within one kernel still refuses (no UUIDs)",
      rep["verdict"] == "refuse", str(rep["verdict"]))

# ...and two ssh corners on one host still refuse on their shared kernel
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "ssh", {"host": "bee", "dev": 57}),
                   (2, "ssh", {"host": "bee", "dev": 57})])
check("equal st_dev for two ssh corners on one host still refuses (no UUIDs)",
      rep["verdict"] == "refuse", str(rep["verdict"]))

# ---- refuse: corner on the source's own filesystem --------------------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 1, "fsuuid": "U-1"})])
r = kinds(rep, "refuse")
check("corner vs source refuses", rep["verdict"] == "refuse" and r and r[0].get("source") is True, str(rep))

# ---- unknown: unreadable identity is never a pass ---------------------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "local", {"unreadable": "destination not present: /mnt/nope"})])
check("unreadable identity -> unknown verdict", rep["verdict"] == "unknown", rep["verdict"])
u = kinds(rep, "unknown")
check("unknown finding carries the reason", u and "destination not present" in u[0]["reason"], str(u))

# ---- cloud corners: declare-and-warn, never a refusal (L1) ------------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "rclone", {"cloud": "rclone corner: two remotes can alias one account"})])
check("cloud corner is not a refusal", rep["verdict"] != "refuse", rep["verdict"])
c = kinds(rep, "cloud")
check("cloud finding says alias, names L1 nature", c and "alias" in c[0]["reason"], str(c))

# ---- warn: two same-model drives on one power path (the Crucial lesson) -----
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2", "model": "Crucial CT2000", "serial": "A", "power": "hub-1"}),
                   (2, "local", {"dev": 3, "fsuuid": "U-3", "model": "Crucial CT2000", "serial": "B", "power": "hub-1"})])
check("siblings warn", rep["verdict"] == "warn", rep["verdict"])
w = kinds(rep, "warn")
check("sibling warning names model + serials", w and "Crucial CT2000" in w[0]["reason"]
      and "SER-A" not in w[0]["reason"] and "correlated failure" in w[0]["reason"], str(w))

# Same model warns independently of power (current doctrine).
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2", "model": "Crucial CT2000", "serial": "A", "power": "hub-1"}),
                   (2, "local", {"dev": 3, "fsuuid": "U-3", "model": "Crucial CT2000", "serial": "B", "power": "hub-2"})])
check("same model, different power: warn", rep["verdict"] == "warn", str(kinds(rep, "warn")))

# same model, same power, SAME serial: that is one device -> refuse lane
# (identical serial means identical identity; the same_filesystem fallback
#  may not catch it, so the sibling warning must not bless it either — the
#  serials-equal case is excluded from warn and lands as pass here, which
#  is a finding: see receipts, "serials equal" row)
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2", "model": "X", "serial": "S1", "power": "hub-1"}),
                   (2, "local", {"dev": 3, "fsuuid": "U-3", "model": "X", "serial": "S1", "power": "hub-1"})])
same_serial_verdict = rep["verdict"]
check("same physical serial refuses despite distinct filesystem UUIDs", same_serial_verdict == "refuse", str(rep))

# ---- warn: two corners on one remote host (one power path) ------------------
rep = run(src={"dev": 1, "fsuuid": "U-1"},
          corners=[(1, "ssh", {"host": "bee", "dev": 30, "fsuuid": "BEE-1"}),
                   (2, "ssh", {"host": "bee", "dev": 31, "fsuuid": "BEE-2"})])
check("one host, two corners warns", rep["verdict"] == "warn", rep["verdict"])
w = kinds(rep, "warn")
check("one-host warning names the host", w and "bee" in w[0]["reason"], str(w))

# ---- verdict ordering: refuse outranks warn and unknown ---------------------
rep = run(src={"dev": 1},
          corners=[(1, "local", {"dev": 1}),        # same fs as source: refuse
                   (2, "local", {"unreadable": "nope"}),
                   (3, "ssh", {"host": "h", "dev": 9})])
check("refuse outranks unknown/warn", rep["verdict"] == "refuse", rep["verdict"])
rep = run(src={"dev": 1},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "ssh", {"host": "h", "dev": 9}),
                   (3, "ssh", {"host": "h", "dev": 10})])   # warn pair + nothing else
check("warn without refuse/unknown is warn", rep["verdict"] == "warn", rep["verdict"])
rep = run(src={"dev": 1},
          corners=[(1, "local", {"dev": 2, "fsuuid": "U-2"}),
                   (2, "local", {"unreadable": "nope"}),
                   (3, "ssh", {"host": "h", "dev": 9})])
check("unknown outranks warn", rep["verdict"] == "unknown", rep["verdict"])

# ---- fixture files run through the same check ------------------------------
FIX = Path(__file__).resolve().parent.parent / "receipts" / "fixtures"
for name, expect in [("independence-siblings.json", "warn"),
                     ("independence-one-host.json", "refuse")]:
    with open(FIX / name) as f:
        fx = json.load(f)
    rep = hecate.independence_check(fx["participants"])
    check(f"fixture {name} -> {expect}", rep["verdict"] == expect,
          f"got {rep['verdict']}: {kinds(rep, 'refuse') or kinds(rep, 'warn')}")

# ---------------------------------------------------------------------------- 
print(f"independence check: {PASS} passed, {len(FAIL)} failed")
if FAIL:
    for f in FAIL:
        print(f"  FAIL: {f}")
    print(f"note: identical-serial pair classifies '{same_serial_verdict}' (excluded from "
          "warn; see receipts finding)")
    sys.exit(1)
print("all lanes hold")
sys.exit(0)
