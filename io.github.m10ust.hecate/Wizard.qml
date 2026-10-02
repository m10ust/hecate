import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Strings.js" as Loc

// Hecate wizard. The six steps as real screens, re-enterable.
//
// LAWS THIS SCREEN OBEYS (M4 brief):
//   - The wizard writes NOTHING to state.json. It talks to the engine
//     (measure-source, check-destination, device-identity, add-job,
//     add-corner, replace-corner, set-horizon, run) and the engine stays
//     the only writer.
//   - Every user-facing string comes from Strings.js. Nothing is typed
//     inline.
//   - Refusal is a screen with the reason and the evidence, never a
//     broken button. The warning path has a deliberate continue that the
//     engine records as independenceAck.
//   - The first screen measures honestly with the engine's own
//     measure(); the working text says it can take a while.
//   - The first run tells the truth about time before it starts, can be
//     closed, and the panel shows the per-corner results when the
//     engine exits.
//
// Process plumbing: one Process per engine call, sequential, stdout
// parsed as JSON where the engine emits JSON. The wizard never touches
// the state file directly, not even to read it: the service's parsed
// jobs are the single read path.
Column {
  id: root

  property var hecate: null          // the service (parsed jobs, fmt helpers)
  property string mode: "idle"       // idle | new | reentry
  signal wizardDone()
  // M5.5a: the chooser is a normal toplevel that maps UNDER this panel's
  // full-screen overlay dismissal surface — every click meant for it
  // lands on the invisible overlay and closes the panel instead (Seb's
  // "first click unfocus the plugin which closes it"). While the chooser
  // runs the panel must be out of the way entirely. The wizard tree and
  // the picker process survive a hidden window: this Loader keys on
  // wizardActive, not visibility, and pickerDone reopens the panel on
  // every outcome (picked, nothing-picked, fault).
  signal pickerPanelWanted(bool open)

  readonly property bool active: mode !== "idle"
  Keys.onEscapePressed: function(event) { pickerPanelWanted(false); event.accepted = true }
  readonly property var jobs: hecate && hecate.jobs !== undefined ? hecate.jobs : []

  // ---- the collected job description (never written here) ----
  property string jobName: ""
  property string sourcePath: ""
  property var sourceMeasure: null   // {bytes, files} from the engine
  property var cornerPlan: [null, null, null]  // dest strings per index
  property var cornerTransports: ["local", "local", "local"]
  property var cornerIdents: [null, null, null]
  property var cornerAcks: [false, false, false]
  property int horizonHours: 48

  // step machine: 0 source, 1..3 corners, 4 schedule, 5 first run
  property int step: 0
  readonly property int totalSteps: 6

  // per-step working state
  property string measureOut: ""
  property bool measuring: false
  property string checkOut: ""
  property bool checking: false
  property var checkReport: null
  property string engineErr: ""
  property bool engineBusy: false
  property string engineLog: ""
  property var pendingSequence: []
  property int sequenceIndex: 0
  property var timerPreview: null
  property bool reentryAdding: false
  property string pickerKind: ""
  readonly property bool busy: engineBusy || pickerBusy

  // ---- fields ----
  property string srcField: ""
  property string nameField: ""
  property string destField: ""
  property int transportIdx: 0
  property bool warnAck: false
  property var reentryJob: null
  property int reentryCorner: 0

  function fmtBytes(b) { return hecate ? hecate.fmtBytes(b) : String(b) }
  function fmtCount(n) { return hecate ? hecate.fmtCount(n) : String(n) }

  function startNew() {
    mode = "new"
    step = 0
    jobName = ""; sourcePath = ""; sourceMeasure = null
    cornerPlan = [null, null, null]
    cornerTransports = ["local", "local", "local"]
    cornerIdents = [null, null, null]
    cornerAcks = [false, false, false]
    horizonHours = 48
    srcField = ""; nameField = ""; destField = ""; transportIdx = 0
    warnAck = false; checkReport = null; engineErr = ""; measureOut = ""
    reentryJob = null
    pendingSequence = []; sequenceIndex = 0; timerPreview = null
    replaceDone = false; pickerNote = ""
  }

  function startReentry(job) {
    mode = "reentry"
    reentryJob = job
    step = 10
  }

  // receipts lane: render a specific screen with a report already loaded.
  // checkReport comes from the ENGINE's JSON (the same object the Check
  // button produces); nothing here is fabricated UI state. For step 0 the
  // report is a measure-source result.
  function armScreen(s, reportJson) {
    mode = "new"
    step = s
    checkReport = null
    sourceMeasure = null
    measuring = false
    checking = false
    engineErr = ""
    if (!reportJson) return
    var r
    try { r = JSON.parse(reportJson) } catch (e) {
      return
    }
    _programmaticField = true
    if (s === 0) {
      sourceMeasure = r   // {path, bytes, files} from measure-source
      srcField = r.path !== undefined ? String(r.path) : ""
    } else {
      checkReport = r
    }
    Qt.callLater(function() { _programmaticField = false })
  }

  property bool _programmaticField: false

  function close() {
    if (busy) return
    mode = "idle"
    wizardDone()
  }

  function stepTitle() {
    if (step === 0) return Loc.S.sourceHeading
    if (step === 1) return Loc.S.cornerOneHeading
    if (step === 2) return Loc.S.cornerTwoHeading
    if (step === 3) return Loc.S.cornerDestLabel + " 3"
    if (step === 4) return Loc.S.scheduleHorizonLabel
    if (step === 5) return Loc.S.firstRunHeading
    if (step === 10) return Loc.S.reenterButton
    return ""
  }

  // ===================================================================
  // engine plumbing — sequential, one flight at a time
  // ===================================================================

  function engineCmd(args, jsonOut, onDone) {
    if (engineBusy) return false
    engineBusy = true
    engineErr = ""
    wizardProc.expectedJson = jsonOut
    wizardProc.onDone = onDone
    wizardProc.command = ["python3", hecate ? hecate.enginePath : "hecate.py"].concat(args)
    wizardProc.awaitingStart = true
    wizardProc.running = true
    processStartWatch.restart()
    return true
  }

  function startMeasure() {
    if (busy) return
    var requested = srcField
    measuring = true
    measureOut = ""
    engineCmd(["measure-source", requested], true, function(out, code) {
      measuring = false
      if (srcField !== requested) return
      var r = parseReport(out)
      if (code !== 0 || !r || r.error) { sourceMeasure = null; engineErr = r && r.error ? r.error : out; return }
      sourceMeasure = r
    })
  }

  function parseReport(out) {
    try { return JSON.parse(out) } catch (e) { engineErr = out || String(e); return null }
  }

  function reportDetails(report) {
    if (!report) return ""
    var lines = [], findings = report.findings || []
    for (var i = 0; i < findings.length; i++) {
      lines.push(String(findings[i].reason || ""))
      if (findings[i].evidence !== undefined)
        lines.push(typeof findings[i].evidence === "string" ? findings[i].evidence : JSON.stringify(findings[i].evidence))
    }
    return lines.join("\n")
  }

  function checkedAllowed() {
    if (busy || !checkReport) return false
    return checkReport.verdict === "pass" || (checkReport.verdict === "warn" && warnAck)
  }

  function continueWarning() {
    if (busy || !checkReport || checkReport.verdict !== "warn") return
    if (mode === "new" && step >= 1 && step <= 3) {
      warnAck = true
      acceptCheckedCorner()
    } else if (mode === "reentry-corner" && !replaceDone) {
      warnAck = true
      commitReplace(destField, transportIdx === 1 ? "ssh" : "local", true)
    }
  }

  function leaveSource() {
    if (busy || !sourceMeasure) return
    var requestedName = nameField
    engineCmd(["validate-name", requestedName], true, function(out, code) {
      var r = parseReport(out)
      if (code !== 0 || !r || r.error) { engineErr = r && r.error ? r.error : out; return }
      jobName = requestedName
      sourcePath = sourceMeasure.path
      step = 1
      loadCorner()
    })
  }

  function loadCorner() {
    checkReport = null; warnAck = false
    if (step >= 1 && step <= 3) {
      destField = cornerPlan[step - 1] || ""
      transportIdx = cornerTransports[step - 1] === "ssh" ? 1 : 0
    }
  }

  onTransportIdxChanged: { checkReport = null; warnAck = false; replaceDone = false }
  onStepChanged: {
    if (step === 4 && mode === "new" && !engineBusy) {
      engineCmd(["timer-paths", jobName], true, function(out, code) {
        var r = parseReport(out)
        timerPreview = code === 0 && r && r.paths ? r : null
      })
    }
  }

  function startCheckCorner() {
    if (busy) return
    var requestedDest = destField, requestedTransport = transportIdx, requestedStep = step
    checking = true
    checkReport = null
    var tr = transportIdx === 1 ? "ssh" : "local"
    // re-entry and later corners: check against every corner that will
    // exist (finding 10) — a corner-vs-corner warn must surface HERE, on
    // the warning screen with its deliberate continue, not as a raw engine
    // error at commit. Re-entry joins the declared job's corners (--job);
    // a new job's accepted-but-undeclared corners ride --also.
    var replacing = mode === "reentry-corner"
    var args = ["check-destination", replacing && reentryJob ? reentryJob.source.path : sourcePath, destField, "--transport", tr]
    // M5.5: the step-0 measure rides along so the engine pairs size
    // with free space without re-walking the source tree per corner
    if (root.sourceMeasure && root.sourceMeasure.bytes !== undefined) {
      args.push("--source-bytes", String(root.sourceMeasure.bytes))
    }
    if (replacing && reentryJob) {
      args.push("--job", reentryJob.name)
      if (!reentryAdding) args.push("--exclude-corner", String(reentryCorner))
    } else if (step > 1) {
      for (var ci = 0; ci < step - 1 && ci < cornerPlan.length; ci++) {
        if (cornerPlan[ci] === null) continue
        args.push("--also-transport", cornerTransports[ci], "--also", cornerPlan[ci])
      }
    }
    engineCmd(args, true,
      function(out, code) {
        checking = false
        if (destField !== requestedDest || transportIdx !== requestedTransport || step !== requestedStep) return
        var r = parseReport(out)
        if (!r || r.error) { checkReport = null; engineErr = r && r.error ? r.error : out; return }
        checkReport = r
      })
  }

  // after a PASS (or acknowledged WARN) at wizard steps 1..3, remember
  // the corner; the writes happen at step 4 -> review -> engine calls
  function acceptCheckedCorner() {
    var idx = step  // step 1 = corner 1
    var plan = cornerPlan.slice(), transports = cornerTransports.slice()
    var identities = cornerIdents.slice(), acks = cornerAcks.slice()
    plan[idx - 1] = destField
    transports[idx - 1] = transportIdx === 1 ? "ssh" : "local"
    identities[idx - 1] = checkReport && checkReport.candidate
      ? checkReport.candidate.identity : null
    acks[idx - 1] = warnAck
    cornerPlan = plan; cornerTransports = transports; cornerIdents = identities; cornerAcks = acks
    destField = ""
    transportIdx = 0
    warnAck = false
    checkReport = null
    step = Math.min(step + 1, 5)
    loadCorner()
  }

  // the writes: one add-job then add-corner per corner, sequential
  function commitJob() {
    if (busy || !timerPreview) return
    if (pendingSequence.length > 0) { runSeq(pendingSequence, sequenceIndex, jobName); return }
    var seq = []
    var name = jobName
    var src = sourcePath
    var first = ["add-job", name, src, cornerPlan[0], "--horizon", String(horizonHours), "--transport", cornerTransports[0]]
    if (cornerAcks[0]) first.push("--accept-warning")
    seq.push(first)
    for (var i = 1; i < 3; i++) {
      if (cornerPlan[i] === null) continue
      var a = ["add-corner", name, cornerPlan[i], "--transport", cornerTransports[i],
               "--horizon", String(horizonHours)]
      if (cornerAcks[i]) a.push("--accept-warning")
      seq.push(a)
    }
    seq.push(["schedule-set", name, "--on-off", "on"])
    pendingSequence = seq
    runSeq(seq, 0, name)
  }

  function runSeq(seq, i, name) {
    sequenceIndex = i
    if (i >= seq.length) {
      step = 5   // first-run screen
      engineBusy = false
      pendingSequence = []
      if (hecate) hecate.refreshState()
      return
    }
    engineBusy = true
    engineErr = ""
    wizardProc.expectedJson = false
    wizardProc.onDone = function(out, code) {
      engineLog = engineLog + "\n" + out
      if (code !== 0) { engineErr = out; engineBusy = false; return }
      Qt.callLater(function() { runSeq(seq, i + 1, name) })
    }
    wizardProc.command = ["python3", hecate ? hecate.enginePath : "hecate.py"].concat(seq[i])
    wizardProc.awaitingStart = true
    wizardProc.running = true
    processStartWatch.restart()
  }

  function startFirstRun() {
    if (!hecate || hecate.engineRunning || hecate.verifyRunning) return
    var result = hecate.ipcRun(jobName)
    if (!hecate.engineRunning) engineErr = result
    step = 5
  }

  // re-entry: point a corner elsewhere
  function commitReplace(dest, tr, ack) {
    if (!checkedAllowed()) return
    var j = reentryJob
    if (!j) return
    var args = reentryAdding ? ["add-corner", j.name, dest, "--transport", tr]
      : ["replace-corner", j.name, String(reentryCorner), dest, "--transport", tr]
    if (ack) args.push("--accept-warning")
    engineBusy = true
    engineErr = ""
    wizardProc.expectedJson = false
    wizardProc.onDone = function(out, code) {
      engineBusy = false
      engineLog = engineLog + "\n" + out
      replaceDone = code === 0
      if (code !== 0) engineErr = out
      if (hecate) hecate.refreshState()
    }
    wizardProc.command = ["python3", hecate ? hecate.enginePath : "hecate.py"].concat(args)
    wizardProc.awaitingStart = true
    wizardProc.running = true
    processStartWatch.restart()
  }

  property bool replaceDone: false

  // ---- M5.5: the desktop folder picker (addendum §1) ----
  property bool pickerBusy: false
  property string pickerNote: ""
  property bool pickerFault: false

  function openPicker(kind) {
    if (busy) return
    pickerKind = kind
    pickerBusy = true
    pickerNote = Loc.S.pickerOpening
    pickerFault = false
    pickerProc.command = ["python3", hecate ? hecate.enginePath : "hecate.py",
                          "pick-folder", kind]
    pickerProc.awaitingStart = true
    pickerProc.running = true
    processStartWatch.restart()
    // step out of the chooser's way (see the signal's comment above)
    pickerPanelWanted(false)
  }

  function pickerDone(out) {
    pickerBusy = false
    // every outcome reopens the panel — the answer (or its absence) must
    // land somewhere the user can see, never in a hidden window
    pickerPanelWanted(true)
    var r
    try { r = JSON.parse(out) } catch (e) {
      pickerNote = "picker output unreadable"
      pickerFault = true
      return
    }
    if (r.outcome === "picked") {
      pickerNote = ""
      pickerFault = false
      if (pickerKind === "source") {
        // a picked source is the user's answer to step 0: land it in
        // STATE and let the field's `text: root.srcField` binding carry
        // the box (armScreen's shape). v0.0.6 wrote srcInput.text
        // directly under the programmatic guard — the guard skipped
        // root.srcField, so measure ran on "" and Next never enabled
        // ("the change doesn't register"); the direct write also broke
        // the text binding on first use. The measure is invalidated
        // here and immediately re-derived by startMeasure.
        root.srcField = r.path
        root.sourceMeasure = null
        root.startMeasure()
      } else {
        root.destField = r.path
      }
    } else if (r.outcome === "nothing-picked") {
      // a decision, not an error: quiet, the screen stays as it was
      pickerNote = Loc.S.pickerNothingPicked
      pickerFault = false
    } else {
      pickerNote = Loc.S.pickerFault.replace("{error}", r.error !== undefined ? r.error : "unknown")
      pickerFault = true
    }
  }

  Process {
    id: pickerProc
    property bool awaitingStart: false
    onStarted: awaitingStart = false
    command: ["true"]
    running: false
    property string buf: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { pickerProc.buf += line + "\n" }
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { pickerProc.buf += line + "\n" }
    }
    onExited: function(code) {
      awaitingStart = false
      running = false
      var out = buf
      buf = ""
      pickerDone(out)
    }
  }

  function fmtRatio(x) {
    if (x === undefined || x === null) return "?"
    var v = Math.round(x * 10) / 10
    return v >= 100 ? String(Math.round(v)) : String(v)
  }

  Process {
    id: wizardProc
    property bool awaitingStart: false
    onStarted: awaitingStart = false
    command: ["true"]
    running: false
    property bool expectedJson: false
    property var onDone: null
    property string buf: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { wizardProc.buf += line + "\n" }
    }
    property string errors: ""
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { wizardProc.errors += line + "\n" }
    }
    onExited: function(code) {
      awaitingStart = false
      running = false
      var out = expectedJson ? buf : buf + errors
      if (code !== 0 && !out) out = errors || String(code)
      buf = ""
      errors = ""
      engineBusy = false
      if (onDone) { var cb = onDone; onDone = null; cb(out, code) }
    }
  }

  // This Quickshell Process exposes started/exited, but no error signal.
  Timer {
    id: processStartWatch
    interval: 2000
    onTriggered: {
      if (wizardProc.awaitingStart && !wizardProc.processId) {
        wizardProc.awaitingStart = false; wizardProc.onDone = null
        root.engineBusy = false; root.measuring = false; root.checking = false
        root.engineErr = JSON.stringify(wizardProc.command)
      }
      if (pickerProc.awaitingStart && !pickerProc.processId) {
        pickerProc.awaitingStart = false
        root.pickerDone(JSON.stringify({outcome: "fault", error: JSON.stringify(pickerProc.command)}))
      }
    }
  }

  // ===================================================================
  // rendering
  // ===================================================================

  spacing: Style.space(10)
  width: parent ? parent.width : 400

  // step header
  PanelSectionHeader {
    visible: root.active
    text: root.active ? (mode !== "new"
      ? Loc.S.reenterButton
      : Loc.S.step + " " + (step + 1) + " " + Loc.S.of + " " + totalSteps) : ""
  }

  Text {
    visible: root.active && mode === "new"
    width: parent.width
    wrapMode: Text.Wrap
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
    text: root.stepTitle()
  }

  // ---------------- step 0: source ----------------
  Column {
    visible: root.active && root.mode === "new" && root.step === 0
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.sourceOpening
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: Loc.S.sourcePathLabel
        color: Color.muted
        width: Style.space(80)
        anchors.verticalCenter: parent.verticalCenter
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: srcInput
        // the Browse button needs room INSIDE the row: label + spacing +
        // field + spacing + button must stay under parent.width, or the
        // button renders past the panel edge where nobody can click it
        // (the v0.0.6 defect: field filled the row, button clipped off)
        width: parent.width - Style.space(96) - browseBtn.implicitWidth
        enabled: !root.busy
        text: root.srcField
        // programmatic sets (armScreen prefilling the receipts lane) must
        // not wipe the measurement they carry; only USER edits invalidate it
        onTextChanged: {
          if (root._programmaticField) return
          root.srcField = text
          root.sourceMeasure = null
          root.cornerPlan = [null, null, null]
          root.cornerIdents = [null, null, null]
          root.cornerAcks = [false, false, false]
        }
        onAccepted: root.startMeasure()
      }
      Button {
        id: browseBtn
        focusable: true
        text: Loc.S.pickerBrowse
        onClicked: root.openPicker("source")
        enabled: !root.busy
      }
    }

    Button {
      focusable: true
      text: root.measuring ? Loc.S.working : Loc.S.sourceHeading
      onClicked: root.startMeasure()
      enabled: !root.busy && root.srcField.length > 0
    }

    Text {
      visible: root.measuring
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.measuring
    }

    Text {
      visible: !root.measuring && root.sourceMeasure !== null
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      textFormat: Text.PlainText
      text: root.sourceMeasure
        ? root.fmtCount(root.sourceMeasure.files) + " " + Loc.S.sourceMeasured
          + "  ·  " + root.fmtBytes(root.sourceMeasure.bytes) : ""
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: Loc.S.sourceJobLabel
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      TextField {
        id: nameInput
        width: parent.width
        enabled: !root.busy
        placeholderText: Loc.S.sourceJobPlaceholder
        text: root.nameField
        onTextChanged: root.nameField = text
      }
    }
  }

  // ---------------- steps 1..3: corners ----------------
  Column {
    visible: root.active && root.mode === "new" && root.step >= 1 && root.step <= 3
    width: parent.width
    spacing: Style.space(8)

    // corner one carries its body copy; two and three are their headings
    Text {
      visible: root.step === 1
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.cornerOneBody
    }

    Text {
      text: Loc.S.cornerDestLabel
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Dropdown {
      id: transportDrop
      width: parent.width
      value: root.transportIdx === 1 ? Loc.S.transportSsh : Loc.S.transportLocal
      options: [Loc.S.transportLocal, Loc.S.transportSsh]
      enabled: !root.busy
      onChanged: function(v) { root.transportIdx = v === Loc.S.transportSsh ? 1 : 0 }
    }

    TextField {
      id: destInput
      width: parent.width
      placeholderText: root.transportIdx === 1 ? Loc.S.cornerSshHint : Loc.S.cornerLocalHint
      text: root.destField
      enabled: !root.busy
      onTextChanged: { root.destField = text; root.checkReport = null; root.warnAck = false }
      onAccepted: root.startCheckCorner()
    }

    // M5.5: the chooser for a local corner; ssh says why it cannot
    Row {
      width: parent.width
      spacing: Style.space(8)
      Button {
        focusable: true
        text: Loc.S.pickerBrowse
        visible: root.transportIdx === 0
        onClicked: root.openPicker("dest")
        enabled: !root.busy
      }
      Text {
        visible: root.transportIdx === 1
        width: parent.width - Style.space(90)
        wrapMode: Text.Wrap
        color: Color.muted
        anchors.verticalCenter: parent.verticalCenter
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        text: Loc.S.pickerSshNoChooser
      }
    }

    Button {
      focusable: true
      text: Loc.S.cornerCheckButton
      onClicked: root.startCheckCorner()
      enabled: !root.busy && root.destField.length > 0
    }

    Text {
      visible: root.checking
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.cornerChecking
    }

    // device identity, shown live once the check has read it
    Column {
      visible: root.checkReport !== null && root.checkReport.candidate !== undefined
      width: parent.width
      spacing: 2
      Text {
        text: Loc.S.cornerDeviceLabel
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        text: {
          if (!root.checkReport || !root.checkReport.candidate) return ""
          var id = root.checkReport.candidate.identity
          if (!id) return ""
          if (id.unreadable !== undefined) {
            return Loc.S.cornerIdentityModel + " " + Loc.S.cornerIdentityUnknown
              + "  ·  " + Loc.S.cornerReasonUnknown + ": " + id.unreadable
          }
          var parts = []
          if (id.model !== undefined) parts.push(Loc.S.cornerIdentityModel + " " + id.model)
          else if (id.fstype !== undefined) parts.push(Loc.S.cornerIdentityModel + " " + Loc.S.cornerIdentityUnknown + " · " + (id.identityNote !== undefined ? id.identityNote : Loc.S.cornerReasonUnknown))
          if (id.serial !== undefined) parts.push(Loc.S.cornerIdentitySerial + " " + id.serial)
          if (id.transport !== undefined) parts.push(Loc.S.cornerIdentityTransport + " " + id.transport)
          if (id.fstype !== undefined) parts.push(id.fstype)
          return parts.join("  ·  ")
        }
      }
    }

    // M5.5: pair the information with the choice (addendum §1) — the
    // measured size against this destination's measured free space
    Column {
      visible: root.checkReport !== null && root.checkReport.capacity !== undefined
      width: parent.width
      spacing: 2
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: {
          if (!root.checkReport || !root.checkReport.capacity) return Color.muted
          var v = root.checkReport.capacity.verdict
          return v === "refuse" ? "#f85149" : v === "warn" ? "#d29922" : Color.muted
        }
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        text: {
          if (!root.checkReport || !root.checkReport.capacity) return ""
          var c = root.checkReport.capacity
          if (c.verdict === "pass")
            return Loc.S.capacityRatioPass.replace("{ratio}", root.fmtRatio(c.ratio))
          if (c.verdict === "warn")
            return Loc.S.capacityRatioWarn.replace("{ratio}", root.fmtRatio(c.ratio))
          if (c.verdict === "refuse") return String(c.reason || "")
          return Loc.S.capacityUnknown + (c.reason ? "\n" + c.reason : "")
        }
      }
    }

    // the refusal screen: reason + evidence, in place, not a dead button
    Column {
      visible: root.checkReport !== null && root.checkReport.verdict === "refuse"
      width: parent.width
      spacing: Style.space(6)
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: "#f85149"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        text: Loc.S.cornerRefuseHeading
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        text: root.reportDetails(root.checkReport)
      }
    }

    // the warning screen: deliberate continue or choose another
    Column {
      visible: root.checkReport !== null && root.checkReport.verdict === "warn"
      width: parent.width
      spacing: Style.space(6)
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: "#d29922"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        text: Loc.S.cornerWarnHeading
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        text: root.reportDetails(root.checkReport)
      }
      Column {
        width: parent.width
        spacing: Style.space(8)
        Button {
      focusable: true
          text: Loc.S.cornerWarnAck
          selected: root.warnAck
          enabled: !root.busy
          onClicked: root.continueWarning()
        }
      }
    }

    Text {
      visible: root.checkReport !== null && root.checkReport.verdict === "unknown"
      width: parent.width
      wrapMode: Text.Wrap
      color: "#d29922"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.cornerUnknownHeading + "\n" + root.reportDetails(root.checkReport)
    }
  }

  // ---------------- step 4: schedule ----------------
  Column {
    visible: root.active && root.mode === "new" && root.step === 4
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: root.timerPreview ? root.timerPreview.calendar + "\n" + root.timerPreview.paths.join("\n") : Loc.S.working
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      Text {
        text: Loc.S.scheduleHorizonLabel
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      NumberField {
        id: horizonField
        width: Style.space(100)
        fieldWidth: width
        from: 1
        to: 8760
        value: root.horizonHours
        enabled: !root.busy && root.pendingSequence.length === 0
        onModified: function(value) { root.horizonHours = value }
      }
      Text {
        text: Loc.S.scheduleHorizonHours
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // ---------------- step 5: first run ----------------
  Column {
    visible: root.active && root.mode === "new" && root.step === 5
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      // Only measured facts are rendered while the owner supplies first-run copy.
      text: root.cornerPlan.filter(function(p) { return p !== null }).join("\n")
    }

    Text {
      visible: root.sourceMeasure !== null
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: root.sourceMeasure
        ? root.fmtBytes(root.sourceMeasure.bytes) + " · " + root.fmtCount(root.sourceMeasure.files) + " " + Loc.S.sourceMeasured : ""
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)
      Button {
      focusable: true
        text: Loc.S.firstRunStart
        enabled: root.hecate && !root.hecate.engineRunning && !root.hecate.verifyRunning
        onClicked: root.startFirstRun()
      }
      Button {
        focusable: true
        text: Loc.S.firstRunLater
        onClicked: root.close()
      }
    }

    Text {
      visible: root.hecate && root.hecate.engineRunning
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: root.hecate && root.hecate.enginePhase === "copy" ? Loc.S.firstRunRunning : Loc.S.working
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: root.hecate ? root.hecate.engineLog : ""
    }
  }

  // ---------------- reentry ----------------
  Column {
    visible: root.active && root.mode === "reentry"
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.reenterButton
    }

    Repeater {
      model: root.jobs
      delegate: Column {
        id: rjob
        required property var modelData
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: rjob.modelData && rjob.modelData.name !== undefined ? String(rjob.modelData.name) : ""
          color: Color.foreground
          font.bold: true
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: 3
          delegate: Column {
            id: rcorn
            required property int index
            readonly property var corner: root.hecate ? root.hecate.cornerAt(rjob.modelData.corners || [], index + 1) : null
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: rcorn.corner ? String(rcorn.corner.destination) : ""
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
              width: parent.width
            }

            Button {
      focusable: true
              enabled: rcorn.corner !== null || rcorn.index === (rjob.modelData.corners || []).length
              text: Loc.S.reenterEditCorner + " " + (rcorn.index + 1) + " " + Loc.S.reenterElsewhere
              onClicked: {
                root.reentryJob = rjob.modelData
                root.reentryCorner = rcorn.index + 1
                root.reentryAdding = !rcorn.corner
                root.checkReport = null; root.warnAck = false; root.replaceDone = false; root.engineErr = ""
                root.destField = rcorn.corner ? rcorn.corner.destination : ""
                root.transportIdx = rcorn.corner && rcorn.corner.transport === "ssh" ? 1 : 0
                root.mode = "reentry-corner"
              }
            }
          }
        }
      }
    }

    Button {
      focusable: true
      text: Loc.S.reenterNewJob
      onClicked: root.startNew()
    }
  }

  // reentry corner replacement screen
  Column {
    visible: root.active && root.mode === "reentry-corner"
    width: parent.width
    spacing: Style.space(8)

    Text {
      text: root.reentryJob && root.reentryCorner > 0
        ? Loc.S.reenterEditCorner + " " + root.reentryCorner + " " + Loc.S.reenterElsewhere : ""
      color: Color.foreground
      font.bold: true
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Dropdown {
      id: rcTransport
      width: parent.width
      value: root.transportIdx === 1 ? Loc.S.transportSsh : Loc.S.transportLocal
      options: [Loc.S.transportLocal, Loc.S.transportSsh]
      onChanged: function(v) { root.transportIdx = v === Loc.S.transportSsh ? 1 : 0 }
      enabled: !root.busy
    }

    TextField {
      id: rcDest
      width: parent.width
      placeholderText: root.transportIdx === 1 ? Loc.S.cornerSshHint : Loc.S.cornerLocalHint
      text: root.destField
      enabled: !root.busy
      onTextChanged: { root.destField = text; root.checkReport = null; root.warnAck = false; root.replaceDone = false }
    }

    Row {
      spacing: Style.space(8)
      Button {
        focusable: true
        text: Loc.S.pickerBrowse
        visible: root.transportIdx === 0
        onClicked: root.openPicker("dest")
        enabled: !root.busy
      }
    }

    Button {
      focusable: true
      text: Loc.S.cornerCheckButton
      onClicked: root.startCheckCorner()
      enabled: !root.busy && root.destField.length > 0
    }

    Text {
      visible: root.checkReport !== null
      width: parent.width
      wrapMode: Text.Wrap
      color: root.checkReport && root.checkReport.verdict === "pass" ? "#56d060" : "#d29922"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: root.checkReport ? root.checkReport.verdict + "\n" + root.reportDetails(root.checkReport) : ""
    }

    Button {
      focusable: true
      visible: root.checkedAllowed() && !root.replaceDone
      text: Loc.S.next
      onClicked: root.commitReplace(root.destField, root.transportIdx === 1 ? "ssh" : "local", root.warnAck)
      enabled: !root.busy
    }

    Button {
      focusable: true
      visible: root.checkReport !== null && root.checkReport.verdict === "warn"
      text: Loc.S.cornerWarnAck
      selected: root.warnAck
      enabled: !root.busy && !root.replaceDone
      onClicked: root.continueWarning()
    }

    Text {
      visible: root.replaceDone
      width: parent.width
      wrapMode: Text.Wrap
      color: "#56d060"
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      text: Loc.S.reenterChanged
    }
  }

  // ---------------- nav row ----------------
  Flow {
    width: parent.width
    visible: root.active
    spacing: Style.space(8)

    Button {
      focusable: true
      visible: root.mode === "reentry-corner" || (root.mode === "new" && root.step > 0 && root.step < 5)
      text: Loc.S.back
      enabled: !root.busy && root.pendingSequence.length === 0
      onClicked: {
        if (root.mode === "reentry-corner") { root.mode = "reentry"; root.checkReport = null; return }
        root.step--; root.loadCorner()
      }
    }

    Button {
      focusable: true
      visible: root.mode === "new" && root.step < 5
      // step 0 needs measure + name; corner steps need a checked pass
      // (or ack'd warn); schedule needs its pre-write path preview.
      enabled: {
        if (root.busy) return false
        if (root.step === 0) return root.sourceMeasure !== null && root.nameField.length > 0
        if (root.step >= 1 && root.step <= 3)
          return root.checkedAllowed()
        if (root.step === 4) return root.timerPreview !== null
        return false
      }
      text: root.step === 4 ? Loc.S.finish : Loc.S.next
      onClicked: {
        if (root.step === 4) { root.commitJob(); return }
        if (root.step >= 1 && root.step <= 3) { root.acceptCheckedCorner(); return }
        root.leaveSource()
      }
    }

    Button {
      focusable: true
      text: Loc.S.cancel
      enabled: !root.busy
      onClicked: root.close()
    }
  }

  Text {
    visible: root.engineErr !== "" && root.active
    width: parent.width
    wrapMode: Text.Wrap
    color: "#f85149"
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
    text: Loc.S.engineError + "\n" + root.engineErr
  }

  // picker outcome note — SHARED, after the nav row like engineErr, so
  // every step that offers a Browse button shows picker feedback. The
  // v0.0.6 defect: this rendered only inside the corner column AND was
  // suppressed while busy, so the source step showed nothing at all and
  // a working picker and a dead one looked identical.
  Text {
    visible: root.active && root.pickerNote !== ""
    width: parent.width
    wrapMode: Text.Wrap
    color: root.pickerFault ? "#f85149" : Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
    text: root.pickerNote
  }
}
