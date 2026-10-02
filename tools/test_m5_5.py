#!/usr/bin/env python3
"""M5.5 regression battery: the folder picker contract (exit taxonomy,
stdout shape), the AIDE announce degradation ladder (including the
unprivileged aide-note that LIES with rc=0), the backed-disk key for
the bee's btrfs case (different st_dev, one disk, one UUID — refused by
UUID today, refused by key when UUIDs are absent), timer announce path
coverage, and the destination-capacity pairing math. All in-process;
live receipts live in receipts/m5-5-receipts.md."""
import json
import os
import stat
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


print("== picker: exit taxonomy (real binary, fault path live) ==")
OMARCHY_FS = "/usr/share/omarchy/bin/omarchy-file-select"
present = Path(OMARCHY_FS).exists()
check("omarchy-file-select present on this box", present, OMARCHY_FS)
if present:
    # LIVE FACT (receipted tonight): Gio discovers the session bus via
    # $XDG_RUNTIME_DIR/bus even without DBUS_SESSION_BUS_ADDRESS, so on a
    # desktop session the picker OPENS THE REAL CHOOSER — never fire it
    # blind from a test. The fault lane needs BOTH vars gone (true
    # headless/ssh seats): then bus_get_sync fails -> exit 2.
    env = {k: v for k, v in os.environ.items()
           if k not in ("DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR")}
    p = subprocess.run([OMARCHY_FS, "--directory"], capture_output=True,
                       text=True, env=env, timeout=30)
    check("no session bus reachable -> exit 2 (fault), not 1",
          p.returncode == 2, f"rc={p.returncode} err={p.stderr.strip()[:80]}")
# with a session bus this same call opens the desktop chooser; the
# dialog receipts (exit 0 with a path, exit 1 on cancel) are Seb's
# click, not a unit test — receipts/m5-5-receipts.md.

print("== picker: the wrapper's JSON contract ==")
r = hecate.picker_result(0, "/home/m4/pictures\n", "")
check("picked -> picked=true with the path",
      r == {"outcome": "picked", "path": "/home/m4/pictures"}, str(r))
r = hecate.picker_result(1, "", "")
check("exit 1 -> nothing-picked (a decision, quiet)",
      r == {"outcome": "nothing-picked"}, str(r))
r = hecate.picker_result(2, "", "omarchy-file-select: ...")
check("exit 2 -> fault with stderr carried",
      r == {"outcome": "fault", "error": "omarchy-file-select: ..."}, str(r))
r = hecate.picker_result(0, "\n", "")
check("exit 0 with no path -> fault (never a silent empty pick)",
      r["outcome"] == "fault", str(r))
r = hecate.picker_result(0, "  /data/one \n/data/two \n", "")
check("multiple lines -> fault (single folder is the contract)",
      r["outcome"] == "fault", str(r))
r = hecate.picker_result(0, "not-absolute\n", "")
check("relative path -> fault (destinations are absolute)",
      r["outcome"] == "fault", str(r))

print("== picker: source discovery ==")
check("absolute path preferred",
      hecate.picker_command()[0] == OMARCHY_FS)
with tempfile.TemporaryDirectory() as td:
    fake = Path(td) / "bin" / "omarchy-file-select"
    fake.parent.mkdir()
    fake.write_text("#!/bin/sh\nexit 0\n")
    fake.chmod(0o755)
    # simulate the absolute path being absent: point the module at the
    # sandbox copy and confirm PATH discovery finds the fake
    saved_path = hecate.OMARCHY_FILE_SELECT
    try:
        hecate.OMARCHY_FILE_SELECT = str(Path(td) / "nowhere" / "omarchy-file-select")
        import os as _os
        _os.environ["PATH"] = f"{fake.parent}:{_os.environ.get('PATH', '')}"
        check("PATH fallback found when absolute absent",
              hecate.picker_command()[0] == str(fake),
              str(hecate.picker_command()))
    finally:
        hecate.OMARCHY_FILE_SELECT = saved_path
        _os.environ["PATH"] = ":".join(
            p for p in _os.environ["PATH"].split(":") if p != str(fake.parent))

print("== AIDE announce: the lying lane ==")
with tempfile.TemporaryDirectory() as td:
    notes = Path(td) / "notes"
    notes.mkdir()
    # the trap, reproduced in a sandbox: rc=0 'noted' while nothing landed.
    # real repro on this box: /var/lib/aide/notes is root-700 and this
    # seat has no sudo -> aide-note prints 'noted @ ...' (rc=0) AND
    # 'Permission denied' on stderr. rc alone cannot be trusted.
    r = hecate.aide_announce("bridge job", ["/home/m4/.config/systemd/user/hecate-bridge.service"],
                             notes_dir=notes)
    check("unwritable notes dir -> degraded, not lied",
          r["status"] == "degraded", str(r))
    check("degraded names every path verbatim",
          "/home/m4/.config/systemd/user/hecate-bridge.service" in r.get("message", ""), str(r))
    check("degraded records the cause", r.get("cause", "") != "", str(r))
    # writability alone is not the verdict — read-back is. A runner that
    # genuinely files into OUR sandbox notes dir: (the real aide-note
    # always writes /var/lib/aide/notes, so the sandboxed case needs its
    # own runner — the logic under test is probe->run->read-back)
    os.chmod(notes, 0o755)
    honest = notes.parent / "aide-note-real"
    honest.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> '" + str(notes / "probe.note") + "'\nexit 0\n")
    honest.chmod(0o755)
    r2 = hecate.aide_announce("bridge job", ["/home/m4/.config/systemd/user/hecate-bridge.service"],
                              runner=str(honest), notes_dir=notes)
    check("writable lane + honest runner -> the note landed (read-back)",
          r2["status"] == "noted", str(r2))

print("== AIDE announce: runner isolation ==")
with tempfile.TemporaryDirectory() as td:
    notes = Path(td) / "notes"
    notes.mkdir()
    # a runner whose aide-note claims success but writes nothing:
    # read-back must catch it (this is the unprivileged lane in miniature)
    liar = Path(td) / "aide-note"
    liar.write_text("#!/bin/sh\necho 'noted @ fake' >&2\necho 'noted @ fake'\nexit 0\n")
    liar.chmod(0o755)
    r = hecate.aide_announce("j", ["/x/y.service"], runner=liar, notes_dir=notes)
    check("lying runner caught by read-back", r["status"] == "degraded", str(r))
    # a runner that genuinely files:
    honest = Path(td) / "aide-note-honest"
    honest.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> " + repr(str(notes / "probe.note")) + "\nexit 0\n")
    honest.chmod(0o755)
    r = hecate.aide_announce("j", ["/x/y.service"], runner=honest, notes_dir=notes)
    check("honest runner -> noted", r["status"] == "noted", str(r))

print("== backed-disk key: the bee's case ==")
# live facts from the bee (receipts): / = /dev/mapper/root[/@] dev 32,
# /home = /dev/mapper/root[/@home] dev 30, ONE uuid REPLACED-IDENTITY...,
# REPLACED-MODEL. Different st_dev, one physical disk: st_dev alone
# would PASS both as corners. The key must collapse them.
k_root = hecate.backed_disk_key({"dev": 32, "fsuuid": "REPLACED-FSUUID",
                                 "fssource": "/dev/mapper/root[/@]", "fstype": "btrfs"})
k_home = hecate.backed_disk_key({"dev": 30, "fsuuid": "REPLACED-FSUUID",
                                 "fssource": "/dev/mapper/root[/@home]", "fstype": "btrfs"})
check("bee: / and /home collapse to one backing disk", k_root == k_home and k_root,
      f"{k_root} vs {k_home}")
# two distinct disks (different UUIDs, no subvol suffix)
k_a = hecate.backed_disk_key({"dev": 100, "fsuuid": "uuid-a", "fssource": "/dev/sda1", "fstype": "ext4"})
k_b = hecate.backed_disk_key({"dev": 101, "fsuuid": "uuid-b", "fssource": "/dev/sdb1", "fstype": "ext4"})
check("two real disks stay distinct", k_a != k_b)
# no UUID anywhere (e.g. tmpfs-like reads): falls to cleaned fssource
k_t1 = hecate.backed_disk_key({"dev": 7, "fssource": "/dev/sdz9", "fstype": "ext4"})
k_t2 = hecate.backed_disk_key({"dev": 9, "fssource": "/dev/sdz9", "fstype": "ext4"})
check("no uuid: same source node collapses (same disk, devs differ)",
      k_t1 == k_t2 and k_t1, f"{k_t1} vs {k_t2}")
k_t3 = hecate.backed_disk_key({"dev": 9, "fssource": "/dev/sdy1", "fstype": "ext4"})
check("no uuid: different source nodes distinct", k_t2 != k_t3)
check("nothing readable -> no key (never a false collapse)",
      hecate.backed_disk_key({"dev": 9}) is None)

print("== same_filesystem uses the key ==")
a = {"dev": 32, "fsuuid": "REPLACED-IDENTITY", "fssource": "/dev/mapper/root[/@]", "fstype": "btrfs"}
b = {"dev": 30, "fsuuid": "REPLACED-IDENTITY", "fssource": "/dev/mapper/root[/@home]", "fstype": "btrfs"}
same, ev = hecate.same_filesystem(a, b)
check("uuid lane unchanged: same uuid -> same", same and "UUID" in ev, ev)
# the case UUID cannot see: strip uuids, keep the one-disk geometry
a2 = {k: v for k, v in a.items() if k != "fsuuid"}
b2 = {k: v for k, v in b.items() if k != "fsuuid"}
same2, ev2 = hecate.same_filesystem(a2, b2)
check("no uuid + subvol suffixes stripped -> refused by backing-disk key",
      same2 and "backing disk" in ev2, ev2)
# and st_dev-lane preserved: same host, same dev, no uuids, plain partitions
same3, ev3 = hecate.same_filesystem({"host": "bee", "dev": 57},
                                    {"host": "bee", "dev": 57})
check("st_dev lane intact (same host, same dev)", same3, ev3)

print("== timer announce path coverage ==")
paths = hecate.timer_install_paths("bridge")
want = {"/home/m4/.config/systemd/user/hecate-bridge.service",
        "/home/m4/.config/systemd/user/hecate-bridge.timer",
        # the enable touches the wants dir AND its symlink — the exact
        # rows tonight's live AIDE alert carried (2026-10-01 00:15)
        "/home/m4/.config/systemd/user/timers.target.wants",
        "/home/m4/.config/systemd/user/timers.target.wants/hecate-bridge.timer"}
check("every flagged path named (units + wants dir + symlink)",
      set(paths) >= want and all(str(hecate.systemd_user_dir() / ("hecate-bridge" + suffix + ".tmp")) in paths
                                 for suffix in (".service", ".timer")), str(paths))
if Path("/home/m4").exists():
    check("absolute-home form used (aidenote literal matching)",
          all(p.startswith("/home/m4/") for p in hecate.timer_install_paths("bridge")))

print("== capacity pairing ==")
src = {"bytes": 1_000_000_000, "files": 500}
c = hecate.corner_capacity_report(src, {"availableBytes": 10_000_000_000,
                                        "totalBytes": 20_000_000_000})
check("10x available passes", c["verdict"] == "pass" and c["ratio"] == 10.0, str(c))
c = hecate.corner_capacity_report(src, {"availableBytes": 2_000_000_000,
                                        "totalBytes": 20_000_000_000})
check("2x available -> warn", c["verdict"] == "warn" and c["ratio"] == 2.0, str(c))
c = hecate.corner_capacity_report(src, None)
check("unreadable capacity -> unknown, never a silent number",
      c["verdict"] == "unknown", str(c))
c = hecate.corner_capacity_report(None, {"availableBytes": 5, "totalBytes": 9})
check("unmeasured source -> unknown", c["verdict"] == "unknown", str(c))
c = hecate.corner_capacity_report({"bytes": 100, "files": 1},
                                  {"availableBytes": 0, "totalBytes": 0})
check("zero free -> refuse", c["verdict"] == "refuse", str(c))

print(f"\nm5.5 tests: {'ALL PASS' if FAIL == 0 else str(FAIL) + ' FAILED'}")
sys.exit(1 if FAIL else 0)
