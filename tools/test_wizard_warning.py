#!/usr/bin/env python3
"""Run the actual wizard functions under QtTest with an offscreen surface.

This checks transitions and acknowledgement, not glass layout or clicks.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "io.github.m10ust.hecate/Wizard.qml").read_text()


def function(name):
    start = source.index("  function " + name + "(")
    end = source.index("\n  }", start) + len("\n  }")
    return source[start:end]


qml = '''import QtQuick
import QtTest
TestCase {
  id: root
  name: "WarningAction"
  property bool busy: false
  property var checkReport: null
  property string mode: "new"
  property int step: 1
  property bool warnAck: false
  property bool replaceDone: false
  property string destField: "mac:/Volumes/Drive"
  property int transportIdx: 1
  property var cornerPlan: [null, null, null]
  property var cornerTransports: ["local", "local", "local"]
  property var cornerIdents: [null, null, null]
  property var cornerAcks: [false, false, false]
  property var replacement: null
  QtObject { id: dropdown; property string value: root.transportIdx === 1 ? "ssh" : "local" }
  function commitReplace(dest, transport, ack) { replacement = [dest, transport, ack] }
  function init() {
    busy = false; mode = "new"; step = 1; warnAck = false; replaceDone = false
    destField = "mac:/Volumes/Drive"; transportIdx = 1
    cornerPlan = [null, null, null]; cornerTransports = ["local", "local", "local"]
    cornerIdents = [null, null, null]; cornerAcks = [false, false, false]
    replacement = null
    checkReport = {verdict: "warn", candidate: {identity: {fixture: true}}}
  }
  function test_newCorner_data() { return [{tag:"one", index:1}, {tag:"two", index:2}, {tag:"three", index:3}] }
  function test_newCorner(data) {
    step = data.index
    continueWarning()
    compare(step, data.index + 1)
    compare(cornerPlan[data.index - 1], "mac:/Volumes/Drive")
    compare(cornerTransports[data.index - 1], "ssh")
    compare(cornerAcks[data.index - 1], true)
    compare(cornerIdents[data.index - 1].fixture, true)
    compare(checkReport, null)
  }
  function test_reentry() {
    mode = "reentry-corner"
    continueWarning()
    compare(replacement[0], "mac:/Volumes/Drive")
    compare(replacement[1], "ssh")
    compare(replacement[2], true)
  }
  function test_blocksBusy() { busy = true; continueWarning(); compare(step, 1); compare(warnAck, false) }
  function test_blocksRefusal() { checkReport = {verdict:"refuse"}; continueWarning(); compare(step, 1); compare(warnAck, false) }
  function test_blocksUnknown() { checkReport = {verdict:"unknown"}; continueWarning(); compare(step, 1); compare(warnAck, false) }
  function test_blocksMissingReport() { checkReport = null; continueWarning(); compare(step, 1); compare(warnAck, false) }
  function test_blocksCompletedReplacement() {
    mode = "reentry-corner"; replaceDone = true; continueWarning(); compare(replacement, null)
  }
  function test_transportBindingSurvivesSelectionAndNextCorner() {
    transportIdx = 0
    dropdown.value = "ssh" // real Dropdown does this before its changed signal
    chooseTransport(dropdown, "ssh")
    compare(transportIdx, 1)
    compare(dropdown.value, "ssh")
    continueWarning()
    compare(cornerTransports[0], "ssh")
    compare(transportIdx, 0)
    compare(dropdown.value, "local")
    dropdown.value = "ssh"
    chooseTransport(dropdown, "ssh")
    compare(transportIdx, 1)
    transportIdx = 0
    compare(dropdown.value, "local")
  }
  function test_transportBindingRestoresSavedSshCorner() {
    dropdown.value = "local"
    chooseTransport(dropdown, "local")
    cornerTransports = ["ssh", "local", "local"]
    loadCorner()
    compare(transportIdx, 1)
    compare(dropdown.value, "ssh")
  }
'''
qml += "\n".join(function(name) for name in ("continueWarning", "acceptCheckedCorner", "loadCorner", "chooseTransport"))
qml += "\n}\n"

with tempfile.TemporaryDirectory(prefix="hecate-warning-qt-") as temporary:
    path = Path(temporary) / "tst_warning.qml"
    path.write_text(qml)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               QT_STYLE_OVERRIDE="Fusion", QT_QUICK_CONTROLS_STYLE="Basic")
    result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-input", temporary], env=env)
    raise SystemExit(result.returncode)
