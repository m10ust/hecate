#!/usr/bin/env python3
"""Hecate M4 unit tests — device identity (the udev lanes).

udev_ident()/block_node_of() are tested against the LIVE block topology of
whatever machine runs them: both fleet boxes are LUKS-on-NVMe with btrfs
subvolumes, which is exactly the hard case (crypt node -> dm slave ->
partition -> disk). Plus parser edge cases that need no hardware.

Usage: python3 test_identity.py   (exit 0 = all assertions hold)
"""
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


# ---- _clean_id_value ----
check("clean: passthrough", hecate._clean_id_value("WD Blue SN570") == "WD Blue SN570")
check("clean: strips control chars", hecate._clean_id_value("abc\x00def\x1f") == "abcdef")
check("clean: first line only", hecate._clean_id_value("line1\nline2") == "line1")
check("clean: empty -> None", hecate._clean_id_value("") is None)
check("clean: None -> None", hecate._clean_id_value(None) is None)
check("clean: whitespace-only -> None", hecate._clean_id_value("   ") is None)
check("clean: int value accepted", hecate._clean_id_value(7) == "7")

# ---- block_node_of ----
check("node: tmpfs -> None", hecate.block_node_of("tmpfs") is None)
check("node: none -> None", hecate.block_node_of("none") is None)
check("node: empty -> None", hecate.block_node_of("") is None)
check("node: subvol stripped",
      hecate.block_node_of("/dev/mapper/root[/@home]") in ("/dev/mapper/root", "/dev/dm-0"))
check("node: plain partition", hecate.block_node_of("/dev/nvme0n1p2") == "/dev/nvme0n1p2")

# ---- findmnt tmpfs shape ----
from pathlib import Path as P  # noqa: E402
shm = P("/dev/shm")
if shm.is_dir():
    fs = hecate.findmnt_of(shm)
    check("findmnt: tmpfs fstype", fs is not None and fs.get("fstype") == "tmpfs",
          str(fs))
    check("findmnt: tmpfs has no uuid", fs is not None and not fs.get("uuid"), str(fs))

# ---- live udev walk (the fleet case: LUKS crypt -> dm slave -> disk) ----
root_fs = hecate.findmnt_of(P("/"))
if root_fs and root_fs.get("source", "").startswith("/dev/"):
    ident = hecate.udev_ident(root_fs["source"])
    check("udev: model found through dm ancestry", bool(ident.get("model")), str(ident))
    check("udev: model is not the transport lane",
          ident.get("model") not in ("nvme", "sata", "usb", "ata"), str(ident))
    if ident.get("model"):
        print(f"  live identity: model={ident['model']!r} serial={ident.get('serial')!r} "
              f"transport={ident.get('transport')!r}")
    # serial matches sysfs directly when present
    if ident.get("serial"):
        import subprocess
        r = subprocess.run(["cat", "/sys/class/block/nvme0n1/device/serial"],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            check("udev: serial equals sysfs", ident["serial"] == r.stdout.strip(),
                  f"{ident['serial']} vs {r.stdout.strip()}")

# ---- read_local_identity carries the identity or says why not ----
home = hecate.read_local_identity(str(P("/home")))
check("identity: home readable", "unreadable" not in home, str(home)[:120])
if home.get("fstype") == "tmpfs":
    check("identity: tmpfs gets the note",
          "identityNote" in home or "no physical device" in home.get("identityNote", ""),
          str(home)[:160])
else:
    # btrfs/ext4 on this fleet: model+serial expected, with a note if absent
    has_or_notes = ("model" in home) or ("identityNote" in home)
    check("identity: model or honest note", has_or_notes, str(home)[:160])
    if "model" in home:
        check("identity: model is not transport",
              home["model"] not in ("nvme", "sata", "usb", "ata"), str(home["model"]))

# ---- ssh identity parse (probe string sanity, no live ssh needed) ----
probe = hecate.SSH_IDENTITY_PROBE
check("probe: parses model=", "model=" in probe)
check("probe: dm slave walk present", "/sys/class/block" in probe and "slaves" in probe)
check("probe: subvol strip present", "${src%%[*}" in probe)
check("probe: no sed-unterminated risk", "s/\"$//" not in probe)

# independence_check still refuses on st_dev alone (M3 law)
rep = hecate.independence_check([
    {"index": "source", "transport": "local", "identity": {"dev": 31}},
    {"index": 1, "transport": "local", "identity": {"dev": 31}}])
check("law1: st_dev refusal intact", rep["verdict"] == "refuse", rep["verdict"])

# verdict vocabulary unchanged
rep2 = hecate.independence_check([
    {"index": "source", "transport": "local", "identity": {"dev": 1, "fsuuid": "a"}},
    {"index": 1, "transport": "local", "identity": {"dev": 2, "fsuuid": "b"}}])
check("law1: distinct uuids pass", rep2["verdict"] == "pass", rep2["verdict"])

print(f"\nidentity tests: {PASS} passed, {len(FAIL)} failed")
for f in FAIL:
    print(f"  FAIL: {f}")
sys.exit(1 if FAIL else 0)
