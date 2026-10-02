import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Hecate service.
//
// ONE LAW: nothing is rendered that was not measured. Every value the bar
// glyph and the panel display comes from parsing
// ~/.local/state/hecate/state.json. No demo switch, no literal state, no
// placeholder pretending to be data. Where nothing is known, the UI says
// "not configured" / "never" / "unknown" — true statements about real state.
//
// THE CONTRACT (PLAN.md "Data contract, corrected 2026-09-30"): the state
// file stores FACTS (lastRun, horizonHours, verified, snapshot, override);
// this service CLASSIFIES at display time into the five words
// current | away | stale | failed | unknown. A stored status/ageDays is a
// verdict the file cannot re-derive — the clock decides here, every render.
//
// What this service does:
// 1. creates the state dir; seeds the canonical empty v2 state if absent
// 2. watches the state file and re-parses it on every change
// 3. classifies each corner from lastRun + horizonHours + override
// 4. answers `qs ipc call io.github.m10ust.hecate state|classify|run|openpanel`
// — `run <job>` spawns the engine (tools/hecate.py); the engine owns
// the state file, this service only reads it
//
// M3: corners two and three are first-class (local + ssh transports,
// per-corner results and horizons). Wizard, timers: M4+.
Item {
 id: root

 property var shell: null
 property var manifest: null

 readonly property string version: "0.0.6"

 signal panelRequested()
 signal wizardRequested(string mode) // "new" | "reentry": open panel with the wizard armed (M4)
 signal wizardScreenRequested(int step, string report) // receipts: render one screen with an engine report

 // The engine ships inside the plugin dir (install lane is copy-then-diff;
 // nothing outside the plugin tree survives it). HECATE_ENGINE overrides
 // for repo-side testing.
 readonly property string enginePath: {
 var env = Quickshell.env("HECATE_ENGINE")
 if (env && env !== "") return env
 // resolvedUrl percent-encodes; decode before handing to a process
 return decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
 + "/engine/hecate.py"
 }

 readonly property string stateDir:
 (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hecate"
 readonly property string statePath: stateDir + "/state.json"

 // ---- the model. Everything below is either parsed from the file or
 // says why it isn't.
 property var jobs: [] // parsed verbatim from state.json
 property string fileBasis: "state not read yet"
 property bool parseFailed: false
 property string parseError: ""
 property string writtenBy: "" // the file's own claim about itself
 property int stateVersion: 0 // the file's contract version (1)

 // ---- status vocabulary: current | away | stale | unknown | failed
 // (five words, PLAN "Findings accepted" M1). THE CONTRACT: these words are
 // CLASSIFIED HERE at display time from lastRun + horizonHours + override;
 // they are never read out of the file. A v1 file's stored status/ageDays
 // is a verdict the file cannot re-derive (P1) — on version < 2 every
 // corner classifies unknown until the engine migrates the file.
 // `missing` is synthesized for a corner absent from the file.
 // Rank: higher = worse. An UNRECOGNIZED status word ranks with "unknown"
 // — never silently green.

 readonly property real defaultHorizonHours: 48

 // The clock is part of the dependency graph: classification depends on
 // Date.now(), which QML bindings do NOT track. Every tick re-runs the
 // classify bindings, so a corner goes stale on screen the same minute it
 // goes stale in fact — the P1 law, applied to the renderer's own cache.
 property real nowMs: Date.now()
 Timer {
 interval: 30000
 running: true
 repeat: true
 triggeredOnStart: true
 onTriggered: {
 root.nowMs = Date.now()
 root.startProbes()
 root.refreshTimers()
 }
 }

 function parseLastRun(c) {
 // -> ms since epoch, or null when absent/unparseable/no timezone
 if (c === null || c === undefined) return null
 var lr = c.lastRun
 if (lr === null || lr === undefined || lr === "") return null
 var s = String(lr)
 // timezone is mandatory: a naive local timestamp would shift with the
 // machine's zone and lie about age
 if (!/(Z|[+-]\d\d:?\d\d)$/.test(s)) return null
 var t = Date.parse(s)
 return isFinite(t) ? t : null
 }

 function classifyCorner(c) {
 // -> one of the five words (or "missing" for a null corner)
 if (c === null || c === undefined) return "missing"
 if (stateVersion < 2) return "unknown"
 var probe = cornerProbe(c)
 if (probe !== null) return probe
 var ov = c.override
 if (ov !== null && ov !== undefined) {
 var w = String(ov.status || "")
 if (w === "failed" || w === "unknown") return w
 }
 // local destination absent from the filesystem = away (measured, not
 // stored: the probe below re-checks and corrects within seconds).
 // away needs a KNOWN lastRun (PLAN: "expected absence with a known
 // last run"); never-run + absent destination is unknown, not away.
 var t = parseLastRun(c)
 if (t === null) return "unknown"
 var horizon = Number(c.horizonHours)
 if (!isFinite(horizon) || horizon <= 0) horizon = defaultHorizonHours
 var ageH = (nowMs - t) / 3600000
 return ageH <= horizon ? "current" : "stale"
 }

 // Read-only engine probes return presence/identity facts. The renderer
 // classifies them; an unmeasured, expired, or failed read is unknown.
 property var probeResults: ({}) // destination -> live observation facts
 property bool probesInFlight: false
 property real probeAtMs: 0
 property string probeError: ""

 function cornerProbe(c) {
 var d = c.destination
 if (d === undefined || d === null || String(d) === "") return "unknown"
 var key = String(d)
 if (Object.prototype.hasOwnProperty.call(probeResults, key)) {
 var observation = probeResults[key]
 if (nowMs - observation.atMs > 60000) return "unknown"
 if (observation.present === true) return null
 return observation.present === false ? "away" : "unknown"
 }
 return "unknown"
 }

 function startProbes() {
 if (probesInFlight) return
 if (parseFailed || jobs.length === 0 || stateVersion < 2) return
 // probeResults is LAST MEASURED, refreshed every tick — presence can
 // change while the file does not, so it is never a permanent cache.
 probesInFlight = true
 destProbe.command = ["python3", enginePath, "probe-destinations"]
 destProbe.running = true
 }

 Process {
 id: destProbe
 command: ["true"]
 running: false
 property string buf: ""
 property string errors: ""
 stdout: SplitParser { onRead: function(line) { destProbe.buf += line + "\n" } }
 stderr: SplitParser { onRead: function(line) { destProbe.errors += line + "\n" } }
 onExited: function(code) {
 var next = ({})
 root.probeError = ""
 try {
 var report = JSON.parse(buf)
 if (code !== 0 || report.error) throw new Error(report.error || errors || String(code))
 for (var i = 0; i < report.observations.length; i++) {
 var r = report.observations[i], old = next[r.destination]
 r.observed.atMs = Date.parse(r.at)
 if (!old || old.present === true) next[r.destination] = r.observed
 }
 root.probeAtMs = Date.now()
 } catch (e) {
 root.probeError = String(e.message || e)
 }
 root.probeResults = next
 root.probesInFlight = false
 buf = ""; errors = ""
 }
 }


 function rankOf(word) {
 if (word === "failed" || word === "missing") return 3
 if (word === "current") return 1
 if (word === "none") return 0 // not configured: not participating, not bad
 return 2 // stale, away, unknown, ""
 }
 // 0 = grey (nothing declared), 1 = green, 2 = amber, 3 = red
 function colorWordForRank(r) { return r >= 3 ? "red" : r === 2 ? "amber" : r === 1 ? "green" : "grey" }

 // Worst status for corner index idx (1..3) across all parsed jobs.
 // "none" — no jobs parsed, OR no job declares this corner: grey.
 // A corner the job never declared is not "missing" (that
 // was the M1 skeleton's word, from fixtures that always
 // had three corners); it is not configured. Red is for a
 // DECLARED corner that failed — an undeclared index is
 // not a break in what exists. (M2 law kept for M3: jobs with
 // otherwise render permanent red until M3 — the
 // amber-permanence disease, H2, wearing red.)
 // otherwise — the worst status among the jobs that declare it
 function hasList(v) {
 // QVariantList (an array that crossed the QML boundary) fails
 // Array.isArray — accept any array-like with a length.
 return v !== null && v !== undefined && typeof v.length === "number" && v.length >= 0
 }

 function worstAt(idx) {
 if (parseFailed) return "unknown"
 if (jobs.length === 0) return "none"
 var worst = "" // "" = no job declares this corner
 for (var j = 0; j < jobs.length; j++) {
 var cs = jobs[j] && hasList(jobs[j].corners) ? jobs[j].corners : []
 var c = cornerAt(cs, idx)
 if (!c) continue
 var s = classifyCorner(c) // display-time, never a stored word
 if (worst === "" || rankOf(s) > rankOf(worst)) worst = s
 }
 return worst === "" ? "none" : worst
 }

 // Worst status per corner index 1..3 across all jobs. Drives the three
 // dots. "none" = no jobs parsed → grey (not configured).
 readonly property var cornerWorst: [worstAt(1), worstAt(2), worstAt(3)]

 // Whole-glyph verdict: green | amber | red | grey.
 // grey — no jobs (or no file): not configured
 // amber — any corner stale or unknown; also an unparseable state file,
 // which means every corner's status is unknown (with the reason
 // shown in the panel — the plan's law 4)
 // red — any corner failed or missing entirely
 // green — every corner current
 readonly property string verdict: {
 if (parseFailed) return "amber"
 if (jobs.length === 0) return "grey"
 var worstRank = Math.max(rankOf(cornerWorst[0]), rankOf(cornerWorst[1]), rankOf(cornerWorst[2]))
 for (var j = 0; j < jobs.length; j++)
 for (var i = 1; i <= 3; i++)
 if (!cornerAt(jobs[j].corners || [], i)) worstRank = Math.max(2, worstRank)
 return colorWordForRank(worstRank)
 }

 function cornerAt(corners, idx) {
 for (var k = 0; k < corners.length; k++)
 if (corners[k] && Number(corners[k].index) === idx) return corners[k]
 return null
 }

 // ---- formatting helpers (single source for tooltip and panel)
 function fmtBytes(b) {
 if (typeof b !== "number" || !isFinite(b) || b < 0) return "unknown"
 var units = ["B", "KB", "MB", "GB", "TB", "PB"]
 var v = b, u = 0
 while (v >= 1000 && u < units.length - 1) { v /= 1000; u++ }
 var s = v >= 100 ? Math.round(v).toString() : v >= 10 ? v.toFixed(1) : v.toFixed(2)
 return s + " " + units[u]
 }
 function fmtCount(n) {
 if (typeof n !== "number" || !isFinite(n) || n < 0) return "unknown"
 return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
 }
 function cornerLine(c) {
 if (!c) return "missing from state file"
 var t = c.transport !== undefined && c.transport !== null ? String(c.transport) : "unknown"
 var d = c.destination !== undefined && c.destination !== null ? String(c.destination) : "unknown"
 // the word is CLASSIFIED here, never read from the file
 var st = classifyCorner(c)
 var line = t + " · " + d + " · " + st
 if (c.lastRun === null || c.lastRun === undefined) line += " · never run"
 else line += " · last run " + String(c.lastRun)
 if (typeof c.horizonHours === "number" && isFinite(c.horizonHours) && c.horizonHours > 0)
 line += " · horizon " + c.horizonHours + "h"
 if (c.verified === true) line += " · list-verified"
 if (c.verified === false) line += " · list diff FAILED"
 if (c.snapshot !== undefined && c.snapshot !== null) line += " · " + String(c.snapshot)
 var ov = c.override
 if (ov !== null && ov !== undefined && ov.status !== undefined && ov.status !== null) {
 line += " · override " + String(ov.status)
 if (ov.reason !== undefined && ov.reason !== null && String(ov.reason) !== "")
 line += ": " + String(ov.reason)
 }
 return line
 }

 // ---- state bootstrap: mkdir, then attach the watcher (omablackbox law:
 // the path is only set once the directory exists)
 Process {
 id: mkdirState
 command: ["python3", root.enginePath, "init-state"]
 running: true
 property string errors: ""
 stdout: SplitParser { onRead: function(line) { mkdirState.errors += line + "\n" } }
 stderr: SplitParser { onRead: function(line) { mkdirState.errors += line + "\n" } }
 onExited: function(exitCode) {
 if (exitCode === 0) {
 stateFile.path = root.statePath
 } else {
 root.applyMissing(errors || String(exitCode))
 }
 }
 }

 FileView {
 id: stateFile
 atomicWrites: true
 printErrors: false
 watchChanges: true
 onLoaded: root.applyState(String(text()))
 onFileChanged: reload()
 onLoadFailed: function(error) {
 root.applyMissing(FileViewError.toString(error))
 }
 }

 function refreshState() { stateFile.reload() }
 property string timerLog: ""
 function refreshTimers() {
 if (parseFailed || jobs.length === 0 || timerCensus.running) return
 timerCensus.command = ["python3", enginePath, "timers"]
 timerCensus.running = true
 }
 Process {
 id: timerCensus
 running: false
 property string buf: ""
 stdout: SplitParser { onRead: function(line) { timerCensus.buf += line + "\n" } }
 stderr: SplitParser { onRead: function(line) { timerCensus.buf += line + "\n" } }
 onExited: function(code) {
 root.timerLog = new Date().toISOString() + "\n" + buf + (code !== 0 ? "\nexit " + code : "")
 buf = ""
 }
 }

 function applyState(text) {
 var s = null
 try { s = JSON.parse(text) } catch (e) {
 parseFailed = true
 parseError = String(e.message || e)
 jobs = []
 fileBasis = "parse failed: " + statePath
 return
 }
 if (s === null || typeof s !== "object" || Array.isArray(s)) {
 parseFailed = true
 parseError = "top-level value is not an object"
 jobs = []
 fileBasis = "parse failed: " + statePath
 return
 }
 if (s.jobs !== undefined && !Array.isArray(s.jobs)) {
 parseFailed = true
 parseError = "\"jobs\" is not an array"
 jobs = []
 fileBasis = "parse failed: " + statePath
 return
 }
 parseFailed = false
 parseError = ""
 writtenBy = s.writtenBy !== undefined && s.writtenBy !== null ? String(s.writtenBy) : ""
 stateVersion = typeof s.version === "number" && isFinite(s.version) ? s.version : 0
 jobs = Array.isArray(s.jobs) ? s.jobs : []
 fileBasis = "parsed " + statePath + (stateVersion > 0 && stateVersion < 2
 ? " (v1 shape: stored verdicts ignored until the engine migrates)" : "")
 probeResults = ({}) // destinations may have changed: re-measure
 startProbes()
 refreshTimers()
 }

 function applyMissing(error) {
 parseFailed = true
 parseError = error
 jobs = []
 writtenBy = ""
 stateVersion = 0
 fileBasis = String(error)
 }

 IpcHandler {
 target: "io.github.m10ust.hecate"

 function state(): string {
 return JSON.stringify({
 version: root.version,
 statePath: root.statePath,
 fileBasis: root.fileBasis,
 parseFailed: root.parseFailed,
 parseError: root.parseError,
 stateVersion: root.stateVersion,
 writtenBy: root.writtenBy,
 verdict: root.verdict,
 cornerWorst: root.cornerWorst,
 jobs: root.jobs,
 wizardDebug: root.wizardDebug
 })
 }

 function openpanel(): void { root.panelRequested() }

 // M4: receipts lane — open the panel with the wizard armed in a mode.
 // Same surface a click reaches; the mode is the wizard's own front door.
 function wizard(mode: string): void { root.wizardRequested(mode) }

 // M4: receipts lane — render a specific wizard screen with an ENGINE
 // report (checkReport) preloaded, e.g. the refusal screen. The report
 // is the engine's own JSON for a real candidate destination.
 function wizardscreen(step: int, report: string): void {
 root.wizardScreenRequested(step, report)
 }

 // classified view for scripts and receipts: the five words as the
 // renderer computes them right now, per corner, with reasons
 function classify(): string {
 var out = []
 out.push("classified at " + new Date(root.nowMs).toISOString())
 for (var j = 0; j < root.jobs.length; j++) {
 var job = root.jobs[j]
 var cs = job && root.hasList(job.corners) ? job.corners : []
 for (var i = 1; i <= 3; i++) {
 var c = root.cornerAt(cs, i)
 if (!c) continue
 out.push(" " + job.name + " corner " + i + " [" + (c.transport || "local") + "] -> "
 + root.classifyCorner(c) + " (" + root.cornerReason(c) + ")")
 }
 }
 return out.join("\n")
 }

 function run(job: string): string {
 return root.ipcRun(job)
 }

 // M5: the "Check the copies" button — list diff + manifest scrub.
 // Same one-code-path rule as run(): the panel button and IPC agree.
 function verify(job: string): string {
 return root.ipcVerify(job)
 }
 }

 property bool engineRunning: false
 property string enginePhase: ""
 property string engineLog: ""
 property bool verifyRunning: false // M5: the scrub pass, separate
 property string verifyLog: "" // from the copy engine so a long
 property string lastVerify: "" // scrub never blocks a run

 // M4 diagnostic: the panel reports the wizard's live mode/step so the
 // receipts lane can see what actually rendered (read-only).
 property string wizardDebug: ""

 // shared entry: the panel's button and the IPC `run` both come through
 // here, so there is exactly one code path that starts the engine.
 function ipcVerify(name) {
 if (verifyRunning || engineRunning) return "verify already running"
 if (name === undefined || name === null || String(name).length === 0)
 return "verify: job name required"
 var n = String(name)
 var known = false
 for (var j = 0; j < jobs.length; j++)
 if (jobs[j] && String(jobs[j].name) === n) { known = true; break }
 if (!known) return "verify: no such job '" + n + "'"
 verifyRunning = true
 verifyLog = "verify started " + new Date().toISOString() + " job=" + n
 verifyProc.command = ["python3", enginePath, "verify", n, "--scrub"]
 verifyProc.running = true
 return "verify started: " + n
 }

 function ipcRun(name) {
 if (engineRunning || verifyRunning) return "engine already running"
 if (name === undefined || name === null || String(name).length === 0)
 return "run: job name required"
 var n = String(name)
 var known = false
 for (var j = 0; j < jobs.length; j++)
 if (jobs[j] && String(jobs[j].name) === n) { known = true; break }
 if (!known) return "run: no such job '" + n + "'"
 engineRunning = true
 enginePhase = ""
 engineLog = "engine started " + new Date().toISOString() + " job=" + n
 engineProc.command = ["python3", enginePath, "run", n]
 engineProc.running = true
 return "engine started: " + n
 }

 Process {
 id: engineProc
 command: ["true"]
 running: false
 stdout: SplitParser {
 splitMarker: "\n"
 onRead: function(line) {
 if (line.length) root.engineLog += "\n" + line
 try {
 var event = JSON.parse(line)
 if (event.phase) root.enginePhase = event.phase
 } catch (e) {}
 }
 }
 stderr: SplitParser {
 splitMarker: "\n"
 onRead: function(line) {
 if (line.length) root.engineLog += "\n[stderr] " + line
 }
 }
 onExited: function(code) {
 root.engineRunning = false
 root.engineLog += "\nengine exit " + code
 // the engine wrote the state file; the FileView watcher fires
 // applyState on its own. Re-probe destinations in case a run created
 // a destination dir for the first time.
 root.startProbes()
 }
 }

 // the M5 verify process: same shape as the copy engine, separate
 // process object so engineRunning never lies about which lane is busy
 Process {
 id: verifyProc
 command: ["true"]
 running: false
 stdout: SplitParser {
 splitMarker: "\n"
 onRead: function(line) {
 if (line.length) root.verifyLog += "\n" + line
 }
 }
 stderr: SplitParser {
 splitMarker: "\n"
 onRead: function(line) {
 if (line.length) root.verifyLog += "\n[stderr] " + line
 }
 }
 onExited: function(code) {
 root.verifyRunning = false
 root.lastVerify = "exit " + code + " at " + new Date().toISOString()
 root.verifyLog += "\nverify exit " + code
 }
 }

 // human-readable reason for a corner's current word (panel second line)
 function cornerReason(c) {
 if (c === null || c === undefined) return "not present in the state file"
 var word = classifyCorner(c)
 if (word === "unknown" || word === "away") {
 var observation = probeResults[String(c.destination)]
 var age = parseLastRun(c)
 var suffix = age !== null ? " · age " + ((nowMs - age) / 3600000).toFixed(1) + "h" : " · never run"
 if (observation && nowMs - observation.atMs > 60000) return "probe age " + ((nowMs - observation.atMs) / 1000).toFixed(0) + "s" + suffix
 if (observation && observation.present !== true) return observation.reason + suffix
 if (!observation) return (probeError || "destination not read yet") + suffix
 }
 if (word === "failed" || word === "unknown") {
 var ov = c.override
 if (ov && ov.reason !== undefined && ov.reason !== null && String(ov.reason) !== "")
 return String(ov.reason)
 if (word === "unknown") {
 if (root.stateVersion > 0 && root.stateVersion < 2) return "v1 state shape — stored verdicts are not knowledge"
 var lr = c.lastRun
 if (lr === null || lr === undefined || String(lr) === "") return "never run"
 return "lastRun unparseable or missing timezone: " + String(lr)
 }
 return "engine override"
 }
 if (word === "away") return "destination not present: " + String(c.destination)
 if (word === "stale") {
 var t = parseLastRun(c)
 var horizon = Number(c.horizonHours)
 if (!isFinite(horizon) || horizon <= 0) horizon = defaultHorizonHours
 return "age " + ((nowMs - t) / 3600000).toFixed(1) + "h past " + horizon + "h horizon"
 }
 if (word === "current") {
 var t2 = parseLastRun(c)
 var h2 = Number(c.horizonHours)
 if (!isFinite(h2) || h2 <= 0) h2 = defaultHorizonHours
 return "age " + ((nowMs - t2) / 3600000).toFixed(1) + "h within " + h2 + "h horizon"
 }
 return ""
 }

 Component.onCompleted: console.warn("hecate: service loaded (v" + version + " M4 — engine " + enginePath + ")")
}
