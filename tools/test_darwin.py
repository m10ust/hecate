#!/usr/bin/env python3
"""Darwin SSH compatibility fixtures, not a real Mac integration receipt."""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import _layout  # noqa: E402  (tools/_layout.py)

ENGINE = Path(__file__).resolve().parents[1] / str(_layout.ENGINE_PY)
spec = importlib.util.spec_from_file_location("hecate", ENGINE)
hecate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hecate)

PROBE = "platform=Darwin\ndev=42\nmachine=fixture-mac\n"


def physical(device):
    return {"DeviceIdentifier": device, "WholeDisk": True,
            "VirtualOrPhysical": "Physical", "DiskUUID": "fixture-" + device,
            "MediaName": "fixture drive", "BusProtocol": "USB"}


class DarwinChecks(unittest.TestCase):
    def identity(self, volume, parts, tree=None):
        def info(host, device, is_path=False):
            if is_path: return volume
            return parts[device]
        proc = subprocess.CompletedProcess([], 0, plistlib.dumps(tree or {}).decode(), "")
        with patch.object(hecate, "darwin_disk_info", side_effect=info), patch.object(hecate, "ssh_script", return_value=proc):
            return hecate.read_darwin_identity("fixture-mac", "/Volumes/Test Drive/Backups", PROBE)

    def test_apfs_volumes_on_one_physical_drive_refused(self):
        parts = {"disk2s2": {"ParentWholeDisk": "disk2"}, "disk2": physical("disk2")}
        volume = {"DeviceIdentifier": "disk3s1", "FilesystemType": "apfs", "VolumeUUID": "volume-A",
                  "APFSPhysicalStores": [{"APFSPhysicalStore": "disk2s2"}]}
        a = self.identity(volume, parts)
        b = self.identity(dict(volume, VolumeUUID="volume-B", DeviceIdentifier="disk3s2"), parts)
        self.assertNotIn("unreadable", a)
        self.assertEqual(a["physical"], ["/dev/disk2"])
        self.assertTrue(hecate.same_filesystem(a, b)[0])

    def test_apfs_fusion_tracks_every_store(self):
        volume = {"DeviceIdentifier": "disk5s1", "FilesystemType": "apfs", "APFSContainerReference": "disk5"}
        tree = {"Containers": [{"ContainerReference": "disk5", "PhysicalStores": [
            {"DeviceIdentifier": "disk1s2"}, {"DeviceIdentifier": "disk2s2"}]}]}
        parts = {"disk1s2": {"ParentWholeDisk": "disk1"}, "disk2s2": {"ParentWholeDisk": "disk2"},
                 "disk1": physical("disk1"), "disk2": physical("disk2")}
        result = self.identity(volume, parts, tree)
        self.assertEqual(result["physical"], ["/dev/disk1", "/dev/disk2"])
        self.assertNotIn("unreadable", result)

    def test_hfs_partition_tracks_whole_disk(self):
        volume = {"DeviceIdentifier": "disk2s1", "ParentWholeDisk": "disk2", "FilesystemType": "hfs"}
        result = self.identity(volume, {"disk2": physical("disk2")})
        self.assertEqual(result["physical"], ["/dev/disk2"])
        self.assertEqual(result["transport"], "USB")

    def test_virtual_disk_is_unknown(self):
        volume = {"DeviceIdentifier": "disk2s1", "ParentWholeDisk": "disk2", "FilesystemType": "hfs"}
        result = self.identity(volume, {"disk2": dict(physical("disk2"), VirtualOrPhysical="Virtual")})
        self.assertIn("not proven physical", result["unreadable"])

    def test_apple_silicon_unknown_requires_physical_list_evidence(self):
        volume = {"DeviceIdentifier": "disk0s2", "ParentWholeDisk": "disk0", "FilesystemType": "hfs"}
        parts = {"disk0": dict(physical("disk0"), VirtualOrPhysical="Unknown")}
        result = self.identity(volume, parts, {"AllDisksAndPartitions": [{"DeviceIdentifier": "disk0"}]})
        self.assertNotIn("unreadable", result)
        self.assertEqual(result["physical"], ["/dev/disk0"])
        result = self.identity(volume, parts, {"AllDisksAndPartitions": []})
        self.assertIn("not proven physical", result["unreadable"])

    def test_missing_apfs_topology_is_unknown(self):
        result = self.identity({"DeviceIdentifier": "disk3s1", "FilesystemType": "apfs"}, {})
        self.assertIn("container reference unreadable", result["unreadable"])

    def test_ssh_probe_dispatches_to_darwin(self):
        proc = subprocess.CompletedProcess([], 0, PROBE, "")
        with patch.object(hecate, "ssh_script", return_value=proc), patch.object(hecate, "read_darwin_identity", return_value={"fixture": True}) as read:
            self.assertEqual(hecate.read_ssh_identity("mac:/Volumes/Test Drive"), {"fixture": True})
        read.assert_called_once_with("mac", "/Volumes/Test Drive", PROBE)

    def test_diskutil_xml_parsed_without_remote_python(self):
        proc = subprocess.CompletedProcess([], 0, plistlib.dumps(physical("disk2")).decode(), "")
        with patch.object(hecate, "ssh_script", return_value=proc) as ssh:
            self.assertEqual(hecate.darwin_disk_info("mac", "disk2"), physical("disk2"))
        self.assertEqual(ssh.call_args.args[1], 'diskutil info -plist "$1"')

    def test_failed_diskutil_preserves_reason(self):
        proc = subprocess.CompletedProcess([], 1, "", "fixture permission failure")
        with patch.object(hecate, "ssh_script", return_value=proc):
            with self.assertRaisesRegex(ValueError, "fixture permission failure"):
                hecate.darwin_disk_info("mac", "disk2")

    def test_remote_exfat_without_source_check_is_unknown(self):
        with patch.object(hecate, "corner_identity", return_value={"fstype": "ExFAT"}):
            result = hecate.destination_readiness({"transport": "ssh", "destination": "mac:/Volumes/Test"}, 10)
        self.assertEqual(result["verdict"], "unknown")

    def test_exfat_source_symlinks_and_specials_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "directory").mkdir()
            (root / "linked-directory").symlink_to(root / "directory", target_is_directory=True)
            self.assertEqual(hecate.portable_source_check(str(root))["verdict"], "refuse")
            (root / "linked-directory").unlink()
            (root / "file").write_bytes(b"fixture")
            (root / "linked-file").symlink_to(root / "file")
            self.assertEqual(hecate.portable_source_check(str(root))["verdict"], "refuse")
            (root / "linked-file").unlink()
            os.mkfifo(root / "fifo")
            self.assertEqual(hecate.portable_source_check(str(root))["verdict"], "refuse")

    def test_exfat_warning_requires_explicit_acknowledgement(self):
        with tempfile.TemporaryDirectory() as temporary:
            Path(temporary, "file").write_bytes(b"fixture")
            proc = subprocess.CompletedProcess([], 0, "", "")
            with patch.object(hecate, "corner_identity", return_value={"fstype": "exfat"}), patch.object(hecate, "ssh_script", return_value=proc), patch.object(hecate, "destination_capacity", return_value={"availableBytes": 1000, "totalBytes": 2000}):
                result = hecate.destination_readiness({"transport": "ssh", "destination": "mac:/Volumes/Test"}, 10, temporary)
            self.assertEqual(result["verdict"], "warn")
            self.assertEqual(result["snapshotMode"], "full-copy")
            ready = {"verdict": "warn", "reason": "fixture format warning"}
            job = {"name": "fixture", "source": {"bytes": 10, "path": temporary}, "corners": []}
            candidate = {"index": 1, "destination": "mac:/Volumes/Test", "transport": "ssh"}
            with patch.object(hecate, "job_participants", return_value=[]), patch.object(hecate, "destination_readiness", return_value=ready), patch.object(hecate, "corner_identity", return_value={"fstype": "exfat"}), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(hecate._gate_corner({}, job, candidate, False), 5)
                self.assertEqual(hecate._gate_corner({}, job, candidate, True), 0)
            self.assertIn("independenceAck", candidate)

    def test_full_snapshots_use_file_markers_and_no_hardlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, dest = root / "source", root / "dest"
            source.mkdir(); dest.mkdir()
            (source / "nested").mkdir()
            (source / "nested" / "file").write_bytes(b"fixture")
            corner = {"index": 1, "transport": "local", "destination": str(dest), "identity": {"fstype": "exfat"}}
            job = {"name": "fixture", "source": {"path": str(source)}}
            snapshots = []
            with patch.object(hecate, "destination_observation", return_value={"present": True, "identity": {"fstype": "exfat"}}), patch.object(hecate, "destination_capacity", return_value={"availableBytes": 10000, "totalBytes": 20000}), patch.object(hecate, "snapshot_name", side_effect=["20261002-000001", "20261002-000002"]), contextlib.redirect_stdout(io.StringIO()):
                for _ in range(2):
                    self.assertTrue(hecate.run_corner(job, corner))
                    snapshots.append(Path(corner["snapshot"]))
            job_dir = dest / "hecate" / "fixture"
            markers = sorted(job_dir.glob("*.latest"))
            self.assertEqual(len(markers), 2)
            marker = markers[-1]
            self.assertFalse(marker.is_symlink())
            self.assertEqual(hecate.resolve_latest(job_dir), snapshots[-1])
            self.assertNotEqual((snapshots[0] / "nested/file").stat().st_ino, (snapshots[1] / "nested/file").stat().st_ino)
            self.assertEqual(corner["snapshotMode"], "full-copy")
            self.assertFalse(corner["metadataPreserved"])

    def test_portable_rsync_omits_link_dest_and_archive_metadata(self):
        proc = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(hecate.subprocess, "run", return_value=proc) as running:
            hecate.run_rsync(Path("/fixture"), "/snapshot", "/previous", portable=True)
        command = running.call_args.args[0]
        self.assertIn("-rt", command)
        self.assertNotIn("-a", command)
        self.assertFalse(any(a.startswith("--link-dest") for a in command))

    def test_remote_readiness_allows_existing_shasum(self):
        proc = subprocess.CompletedProcess([], 0, "", "")
        with patch.object(hecate, "corner_identity", return_value={"fstype": "apfs"}), patch.object(hecate, "ssh_script", return_value=proc) as ssh, patch.object(hecate, "destination_capacity", return_value={"availableBytes": 1000, "totalBytes": 2000}):
            result = hecate.destination_readiness({"transport": "ssh", "destination": "mac:/Volumes/Test Drive"}, 10)
        self.assertEqual(result["verdict"], "pass")
        self.assertIn("command -v shasum", ssh.call_args.args[1])

    def test_scrub_shasum_fallback_and_space_names(self):
        real_hash = shutil.which("sha256sum")
        real_cut = shutil.which("cut")
        if not real_hash or not real_cut: self.skipTest("host tools unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bin_dir = root / "bin"; bin_dir.mkdir()
            shim = bin_dir / "shasum"
            shim.write_text('#!/bin/sh\n[ "$1" = -a ] && shift 2\nexec ' + hecate.posix_quote(real_hash) + '\n')
            shim.chmod(0o700)
            (bin_dir / "cut").symlink_to(real_cut)
            (root / "file  name ").write_bytes(b"fixture")
            digest = hashlib.sha256(b"fixture").hexdigest()
            (root / hecate.MANIFEST_NAME).write_text(digest + "  file  name \n")
            env = dict(os.environ, PATH=str(bin_dir))
            proc = subprocess.run(["/bin/sh", "-s", str(root)], input=hecate.REMOTE_SCRUB, capture_output=True, text=True, env=env)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("files=1 bad=0", proc.stdout)
            (root / "file  name ").write_bytes(b"corrupt")
            proc = subprocess.run(["/bin/sh", "-s", str(root)], input=hecate.REMOTE_SCRUB, capture_output=True, text=True, env=env)
            self.assertNotEqual(proc.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
