#!/usr/bin/env python3
"""M5 regression battery: manifest + basis + scrub + timer grammar +
unit-name gate + capacity math, all in-process (no rsync, no ssh, no
systemd). The live-fire receipts live in receipts/m5-receipts.md."""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "io.github.m10ust.hecate" / "engine"))
import hecate

FAIL = 0
def check(name, cond, detail=""):
    global FAIL
    tag = "PASS" if cond else "FAIL"
    if not cond:
        FAIL += 1
    print(f"  [{tag}] {name}" + (f"  ({detail})" if detail and not cond else ""))

print("== manifest round-trip ==")
with tempfile.TemporaryDirectory() as td:
    t = Path(td)
    (t / "a.bin").write_bytes(b"alpha" * 100)
    (t / "sub").mkdir()
    (t / "sub" / "b.bin").write_bytes(b"beta" * 100)
    (t / "link").symlink_to("a.bin")
    hashed = hecate.hash_tree(t, ["a.bin", "sub/b.bin"])
    man = hecate.write_manifest(t, hashed, ["link"])
    # manifest exists inside the snapshot
    check("manifest inside snapshot", (t / "MANIFEST.sha256").is_file())
    # sha256sum -c compatible: run the real tool
    rc = subprocess.run(["sha256sum", "-c", "MANIFEST.sha256"], cwd=t,
                        capture_output=True).returncode
    check("sha256sum -c passes on the real tool", rc == 0)
    # scrub: healthy
    res = hecate.scrub_check_manifest(t)
    check("scrub healthy ok", res["ok"], str(res))
    check("scrub counts 2 files", res.get("files") == 2, str(res))
    # the length-preserving flip: byte 3 of a.bin
    data = bytearray((t / "a.bin").read_bytes())
    data[3] ^= 0xFF
    (t / "a.bin").write_bytes(bytes(data))
    check("size preserved by the flip", (t / "a.bin").stat().st_size == 500)
    res = hecate.scrub_check_manifest(t)
    check("scrub catches length-preserving flip", not res["ok"], str(res))
    check("scrub names the bad file", res.get("bad") and res["bad"][0][0] == "a.bin", str(res))
    # extra file (undeclared content)
    (t / "a.bin").write_bytes(b"alpha" * 100)
    (t / "sneaky").write_bytes(b"x")
    res = hecate.scrub_check_manifest(t)
    check("scrub flags undeclared extra", not res["ok"] and res.get("extra") == ["sneaky"], str(res))
    (t / "sneaky").unlink()
    # missing file
    (t / "sub" / "b.bin").unlink()
    res = hecate.scrub_check_manifest(t)
    check("scrub flags missing file", not res["ok"] and "sub/b.bin" in res.get("missing", []), str(res))
    # absent manifest
    (t / "MANIFEST.sha256").unlink()
    res = hecate.scrub_check_manifest(t)
    check("absent manifest is not ok, with reason", not res["ok"] and "no MANIFEST" in res.get("reason", ""), str(res))
    # symlink swap: link retargeted, content identical
    (t / "sub" / "b.bin").write_bytes(b"beta" * 100)
    (t / "a.bin").write_bytes(b"alpha" * 100)   # restore from the extra-file test
    hashed = hecate.hash_tree(t, ["a.bin", "sub/b.bin"])
    hecate.write_manifest(t, hashed, ["link"])
    (t / "link").unlink()
    (t / "link").symlink_to("sub/b.bin")
    res = hecate.scrub_check_manifest(t)
    check("retargeted symlink still scrubs ok (links ride, never hashed)", res["ok"], str(res))

print("== basis vocabulary ==")
check("three bases defined", {hecate.BASIS_BYTES, hecate.BASIS_PROVIDER, hecate.BASIS_SIZE_MTIME}
      == {"bytes", "provider-checksum", "size+mtime"})

print("== job name gate ==")
check("plain name ok", hecate.job_name_ok("music"))
check("dotted ok", hecate.job_name_ok("my.music-2"))
check("space refused", not hecate.job_name_ok("my job"))
check("semicolon refused", not hecate.job_name_ok("job;rm"))
check("path refused", not hecate.job_name_ok("../escape"))
check("empty refused", not hecate.job_name_ok(""))
check("65 chars refused", not hecate.job_name_ok("a" * 65))
check("64 chars ok", hecate.job_name_ok("a" * 64))

print("== calendar validation ==")
ok, norm = hecate.validate_calendar("*-*-* 02:00:00")
check("default calendar valid", ok, norm)
check("normalized form used", norm == "*-*-* 02:00:00", norm)
ok, msg = hecate.validate_calendar("garbage value here")
check("garbage refused", not ok, msg)

print("== unit templates ==")
svc = hecate.SERVICE_UNIT.format(version="0.0.5", name="demo", python="/usr/bin/python3",
                                 engine="/x/hecate.py", job="demo")
check("service: oneshot", "Type=oneshot" in svc)
check("service: --by-timer present", "--by-timer" in svc)
check("service: no sudo anywhere", "sudo" not in svc)
tmr = hecate.TIMER_UNIT.format(version="0.0.5", name="demo",
                               calendar="*-*-* 02:00:00", service="hecate-demo.service")
check("timer: Persistent=true", "Persistent=true" in tmr)
check("timer: OnCalendar present", "OnCalendar=*-*-* 02:00:00" in tmr)
check("timer: user scope only", "WantedBy=timers.target" in tmr)

print("== capacity facts shape ==")
with tempfile.TemporaryDirectory() as td:
    # the job dir does not exist before the first run; capacity probes the
    # nearest existing ancestor (the destination root), which is the honest
    # available number for "can this corner hold 3x the source"
    cap = hecate.destination_capacity({"transport": "local", "destination": td}, "job")
    check("local capacity measured via ancestor", cap is not None and cap["totalBytes"] > 0, str(cap))
    if cap:
        check("available <= total", cap["availableBytes"] <= cap["totalBytes"])
    # and with the job dir actually present (post-run shape)
    (Path(td) / "hecate" / "job").mkdir(parents=True)
    cap2 = hecate.destination_capacity({"transport": "local", "destination": td}, "job")
    check("local capacity measured at job dir", cap2 is not None and cap2["totalBytes"] > 0, str(cap2))

print(f"\nm5 tests: {'ALL PASS' if FAIL == 0 else str(FAIL) + ' FAILED'}")
sys.exit(1 if FAIL else 0)
