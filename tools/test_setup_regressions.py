#!/usr/bin/env python3
"""Audit regression checks. All writes stay in a TemporaryDirectory.

Storage integration uses real rsync. Hardware identities and systemd calls
are fixtures/mocks; this suite makes no claim about the owner's desktop.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import _layout  # noqa: E402  (tools/_layout.py)

ENGINE = Path(__file__).resolve().parents[1] / str(_layout.ENGINE_PY)
spec = importlib.util.spec_from_file_location("hecate", ENGINE)
hecate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hecate)


def identity(disk, uuid=None, machine="fixture-machine", model="Fixture", serial=None):
    return {"machine": machine, "physical": [disk], "fsuuid": uuid or disk,
            "model": model, "serial": serial or disk, "dev": abs(hash(disk)) % 100000}


def participant(index, ident, transport="local"):
    return {"index": index, "identity": ident, "transport": transport}


class SetupRegressions(unittest.TestCase):
    def test_old_python_reports_requirement_before_annotations(self):
        script = "import sys, runpy; sys.version_info = (3, 9, 0); sys.version = '3.9.0 (simulated)'; runpy.run_path(sys.argv[1], run_name='__main__')"
        proc = subprocess.run(["python3", "-B", "-c", script, str(ENGINE)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("Python 3.10 or newer is required; found 3.9.0", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="hecate-regression-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {
            "XDG_STATE_HOME": str(self.base / "state"),
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_RUNTIME_DIR": str(self.base / "runtime"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_partitions_of_one_disk_refused_despite_different_uuids(self):
        a = identity("/dev/sda", "partition-A")
        b = identity("/dev/sda", "partition-B")
        a["serial"], b["serial"] = None, None
        result = hecate.independence_check([participant(1, a), participant(2, b)])
        self.assertEqual(result["verdict"], "refuse")

    def test_mapper_with_any_shared_member_refused(self):
        a, b = identity("/dev/sda"), identity("/dev/sdc")
        b["physical"].append("/dev/sda")
        self.assertTrue(hecate.same_filesystem(a, b)[0])

    def test_identical_device_paths_on_different_hosts_do_not_refuse(self):
        a, b = identity("/dev/sda", "A", "machine-A", serial="A"), identity("/dev/sda", "B", "machine-B", serial="B")
        a["host"], b["host"] = "alias-a", "alias-b"
        self.assertFalse(hecate.same_filesystem(a, b)[0])

    def test_ssh_aliases_of_one_machine_share_power_warning(self):
        a, b = identity("/dev/sda"), identity("/dev/sdb")
        a["host"], b["host"] = "alias-a", "alias-b"
        result = hecate.independence_check([participant(1, a, "ssh"), participant(2, b, "ssh")])
        self.assertEqual(result["verdict"], "warn")

    def test_different_models_shared_power_warn(self):
        a, b = identity("/dev/a", model="A"), identity("/dev/b", model="B")
        a["power"] = b["power"] = "one-strip"
        self.assertEqual(hecate.independence_check([participant(1, a), participant(2, b)])["verdict"], "warn")

    def test_same_model_different_power_still_warn(self):
        a, b = identity("/dev/a"), identity("/dev/b")
        a["power"], b["power"] = "strip-A", "strip-B"
        self.assertEqual(hecate.independence_check([participant(1, a), participant(2, b)])["verdict"], "warn")

    def test_same_model_missing_serials_still_warn(self):
        a, b = identity("/dev/a"), identity("/dev/b")
        a["serial"] = b["serial"] = None
        self.assertEqual(hecate.independence_check([participant(1, a), participant(2, b)])["verdict"], "warn")

    def test_usb_reenumeration_keeps_recorded_serial_identity(self):
        dest = self.base / "dest"
        dest.mkdir()
        expected = identity("/dev/sda", "same-uuid", serial="same-serial")
        actual = identity("/dev/sdb", "same-uuid", serial="same-serial")
        corner = {"destination": str(dest), "transport": "local", "identity": expected}
        with patch.object(hecate, "corner_identity", return_value=actual):
            self.assertIs(hecate.destination_observation(corner)["present"], True)
        actual["serial"] = "other-serial"
        with patch.object(hecate, "corner_identity", return_value=actual):
            self.assertIs(hecate.destination_observation(corner)["present"], False)
        actual["serial"] = None
        with patch.object(hecate, "corner_identity", return_value=actual):
            self.assertIsNone(hecate.destination_observation(corner)["present"])

    def test_all_cloud_set_refused(self):
        result = hecate.independence_check([participant(i, {"cloud": "fixture cloud"}, "rclone") for i in (1, 2, 3)])
        self.assertEqual(result["verdict"], "refuse")

    def test_unreadable_identity_has_reason_and_never_passes(self):
        result = hecate.independence_check([participant(1, {"unreadable": "fixture denied"})])
        self.assertEqual(result["verdict"], "unknown")
        self.assertIn("fixture denied", result["findings"][0]["reason"])

    def test_repeated_also_arguments_are_distinct(self):
        with patch.object(hecate, "corner_identity", side_effect=lambda c: {"path": c["destination"]}), patch.object(hecate, "cmd_check_destination", return_value=0) as check:
            rc = hecate._main(["check-destination", "/source", "/third", "--source-bytes", "100",
                               "--also-transport", "local", "--also", "/first",
                               "--also-transport", "ssh", "--also", "host:/second"])
        self.assertEqual(rc, 0)
        parts = check.call_args.args[4]
        self.assertEqual([p["identity"]["path"] for p in parts], ["/first", "host:/second"])
        self.assertEqual([p["transport"] for p in parts], ["local", "ssh"])

    def test_first_corner_ssh_transport_is_persisted(self):
        src = self.base / "source"
        src.mkdir()
        (src / "a").write_bytes(b"data")
        with patch.object(hecate, "_gate_corner", return_value=0), contextlib.redirect_stdout(io.StringIO()):
            rc = hecate.main(["add-job", "photos", str(src), "host:/backup", "--transport", "ssh"])
        self.assertEqual(rc, 0)
        corner = hecate.read_state()["jobs"][0]["corners"][0]
        self.assertEqual((corner["transport"], corner["destination"]), ("ssh", "host:/backup"))

    def test_capacity_cannot_fit_initial_copy_refused(self):
        result = hecate.corner_capacity_report({"bytes": 400}, {"availableBytes": 399})
        self.assertEqual(result["verdict"], "refuse")

    def test_existing_unmounted_directory_is_away(self):
        dest = self.base / "mountpoint"
        dest.mkdir()
        corner = {"transport": "local", "destination": str(dest), "identity": identity("/dev/external")}
        with patch.object(hecate, "corner_identity", return_value=identity("/dev/internal")):
            observation = hecate.destination_observation(corner)
        self.assertIs(observation["present"], False)
        self.assertTrue(observation["reason"])

    def test_changed_mount_is_not_written(self):
        dest = self.base / "mountpoint"
        dest.mkdir()
        corner = {"index": 1, "transport": "local", "destination": str(dest), "identity": identity("/dev/external")}
        job = {"name": "photos", "source": {"path": str(self.base)}}
        with patch.object(hecate, "corner_identity", return_value=identity("/dev/internal")), contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(hecate.run_corner(job, corner))
        self.assertFalse((dest / "hecate").exists())
        self.assertEqual(corner["override"]["status"], "unknown")

    def test_real_rsync_changed_files_and_manifest_inheritance(self):
        src, dest = self.base / "source", self.base / "destination"
        src.mkdir(); dest.mkdir()
        name = "photo | with  spaces .bin "
        (src / name).write_bytes(b"first")
        (src / "unchanged").write_bytes(b"stable")
        c = {"index": 1, "transport": "local", "destination": str(dest), "identity": identity("/dev/dest")}
        job = {"name": "photos", "source": {"path": str(src)}}
        with patch.object(hecate, "destination_observation", return_value={"present": True}), patch.object(hecate, "snapshot_name", side_effect=["20261001-010000", "20261001-020000", "20261001-030000"]), contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(hecate.run_corner(job, c))
            (src / name).write_bytes(b"second version")
            self.assertTrue(hecate.run_corner(job, c))
            self.assertEqual(c["verified"]["hashed"], 1)
            self.assertEqual(c["verified"]["inherited"], 1)
            self.assertTrue(hecate.run_corner(job, c))
        snap = Path(c["snapshot"])
        self.assertEqual((snap / name).read_bytes(), b"second version")
        self.assertTrue(hecate.scrub_check_manifest(snap)["ok"])
        self.assertEqual(hecate.resolve_latest(dest / "hecate/photos"), snap)
        self.assertNotIn("scrub", c)

    def test_rsync_exception_keeps_three_value_contract(self):
        with patch.object(hecate.subprocess, "run", side_effect=subprocess.TimeoutExpired("rsync", 1)):
            self.assertEqual(len(hecate.run_rsync(Path("/fixture"), "/fixture-dest", None)), 3)

    def test_failed_manifest_does_not_advance_latest(self):
        src, dest = self.base / "source", self.base / "destination"
        src.mkdir(); dest.mkdir(); (src / "a").write_bytes(b"x")
        c = {"index": 1, "transport": "local", "destination": str(dest), "identity": identity("/dev/dest")}
        job = {"name": "photos", "source": {"path": str(src)}}
        with patch.object(hecate, "destination_observation", return_value={"present": True}), patch.object(hecate, "_local_manifest_for_snapshot", side_effect=OSError("fixture read denied")):
            with self.assertRaises(OSError): hecate.run_corner(job, c)
        self.assertIsNone(hecate.resolve_latest(dest / "hecate/photos"))

    def test_state_writer_lock_refuses_other_mutation(self):
        fd, _ = hecate.acquire_run_lock("state", shared=True)
        self.addCleanup(os.close, fd)
        env = dict(os.environ)
        result = subprocess.run(["python3", "-B", str(ENGINE), "init-state"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 4)
        self.assertFalse(hecate.state_path().exists())

    def test_timer_announces_before_directory_or_unit_write(self):
        announced = []
        def announce(what, paths):
            self.assertFalse(hecate.systemd_user_dir().exists())
            announced.extend(paths)
            return {"status": "absent"}
        with patch.object(hecate, "aide_announce", side_effect=announce), patch.object(hecate, "_sc_verify", return_value=(True, "")):
            result = hecate.write_job_timer({"name": "photos", "schedule": {"calendar": hecate.DEFAULT_CALENDAR}}, "/usr/bin/python3")
        self.assertTrue(result["enabled"])
        for unit in result["units"]:
            self.assertIn(unit, announced)
            self.assertIn(unit + ".tmp", announced)
            self.assertTrue(Path(unit).is_file())

    def test_measure_read_errors_are_not_silently_counted(self):
        src = self.base / "source"
        src.mkdir(); (src / "a").write_bytes(b"x")
        with patch.object(hecate.os, "lstat", side_effect=PermissionError("fixture denied")):
            with self.assertRaises(PermissionError): hecate.measure(src)

    def test_remote_scrub_read_failure_sets_unknown(self):
        c = {"index": 1}
        with patch.object(hecate, "ssh_script", side_effect=subprocess.TimeoutExpired("ssh", 1)), contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(hecate.scrub_corner(c, "/snapshot", "host"))
        self.assertEqual(c["override"]["status"], "unknown")
        self.assertEqual(c["scrub"]["snapshot"], "/snapshot")

    def test_findmnt_null_uuid_preserves_backing_source(self):
        output = json.dumps({"filesystems": [{"uuid": None, "source": "/dev/mapper/root[/@home]", "fstype": "btrfs"}]})
        with patch.object(hecate.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output, "")):
            fs = hecate.findmnt_of(Path("/fixture"))
        self.assertEqual(fs["source"], "/dev/mapper/root[/@home]")
        self.assertIsNone(fs["uuid"])

    def test_reserved_manifest_is_not_overwritten_as_backup_chrome(self):
        src = self.base / "source"
        src.mkdir(); (src / hecate.MANIFEST_NAME).write_bytes(b"user data")
        with self.assertRaises(ValueError): hecate.measure(src)

    def test_remote_scrub_preserves_double_spaces_in_names(self):
        snap = self.base / "snapshot"
        snap.mkdir(); (snap / "photo  name").write_bytes(b"pixels")
        hecate.write_manifest(snap, hecate.hash_tree(snap, ["photo  name"]), [])
        result = subprocess.run(["bash", "-c", hecate.REMOTE_SCRUB, "fixture", str(snap)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("files=1 bad=0", result.stdout)

    def test_failed_corner_does_not_stop_others_or_lose_progress(self):
        src = self.base / "source"
        src.mkdir(); (src / "a").write_bytes(b"x")
        job = {"name": "photos", "source": {"path": str(src)},
               "corners": [{"index": i, "destination": f"/fixture/{i}", "transport": "local"} for i in (1, 2, 3)]}
        hecate.write_state({"jobs": [job]})
        def run(job, c):
            if c["index"] == 1: raise OSError("fixture hash failed")
            c["lastRun"] = hecate._now_iso()
            return True
        with patch.object(hecate, "job_participants", return_value=[]), patch.object(hecate, "run_corner", side_effect=run) as running, patch.object(hecate, "destination_capacity", return_value=None), contextlib.redirect_stdout(io.StringIO()):
            rc = hecate.main(["run", "photos"])
        self.assertEqual(rc, 1)
        self.assertEqual(running.call_count, 3)
        saved = hecate.read_state()["jobs"][0]["corners"]
        self.assertEqual(saved[0]["override"]["status"], "unknown")
        self.assertTrue(saved[1]["lastRun"] and saved[2]["lastRun"])

    def test_verify_read_failure_does_not_stop_later_corners(self):
        src = self.base / "source"
        src.mkdir(); (src / "a").write_bytes(b"x")
        corners = [{"index": i, "destination": str(self.base / str(i)), "transport": "local"} for i in (1, 2, 3)]
        hecate.write_state({"jobs": [{"name": "photos", "source": {"path": str(src)}, "corners": corners}]})
        def latest(job_dir):
            if "/1/" in str(job_dir):
                raise PermissionError("fixture snapshot unreadable")
            return self.base / "snapshot"
        with patch.object(hecate, "destination_observation", return_value={"present": True}), patch.object(hecate, "resolve_latest", side_effect=latest) as resolving, patch.object(hecate, "file_list", return_value=["a"]), patch.object(hecate, "scrub_corner", return_value=False) as scrubbing, contextlib.redirect_stdout(io.StringIO()):
            rc = hecate.main(["verify", "photos", "--scrub"])
        self.assertEqual(rc, 1)
        self.assertEqual(resolving.call_count, 3)
        self.assertEqual(scrubbing.call_count, 2)
        saved = hecate.read_state()["jobs"][0]["corners"]
        self.assertEqual(saved[0]["override"]["status"], "unknown")
        self.assertIn("fixture snapshot unreadable", saved[0]["override"]["reason"])
        self.assertTrue(saved[1]["sourceComparison"]["pathsAgree"])
        self.assertTrue(saved[2]["sourceComparison"]["pathsAgree"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
