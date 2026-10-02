import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Hecate bar widget — v0.0.5 M5.
// Render-only: every value comes from the service's PARSED state and its
// display-time classification. There is no demo switch and no literal
// state in this file.
//
// Glyph law: THREE dots, one per corner — Hecate Triformis. Each dot's
// colour is that corner's worst status ACROSS ALL JOBS, parsed from the
// state file. The word next to the dots is the whole-glyph verdict.
BarWidget {
  id: root

  moduleName: "io.github.m10ust.hecate"

  readonly property var hecate: bar && bar.shell ? bar.shell.serviceFor("io.github.m10ust.hecate") : null

  readonly property color ink: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Color.muted

  // Colours exist as palette constants for the pixel receipts; which one a
  // dot uses is decided only by the parsed state.
  readonly property color goodC: "#56d364"
  readonly property color amberC: "#d29922"
  readonly property color badC: "#f85149"
  readonly property color greyC: "#6e7681"

  readonly property var cornerWorst: hecate && hecate.cornerWorst ? hecate.cornerWorst : ["none", "none", "none"]
  readonly property string verdict: hecate && hecate.verdict ? hecate.verdict : "grey"

  function colorForStatus(status) {
    if (status === "current") return goodC
    if (status === "failed" || status === "missing") return badC
    if (status === "stale" || status === "unknown" || status === "away") return amberC
    return greyC // "none" — not configured / no such corner yet
  }

  readonly property string tooltip: {
    if (!hecate) return "Hecate: service not loaded"
    var lines = []
    lines.push("HECATE — three-corner backups · v0.0.5 M5")
    lines.push("state   " + hecate.fileBasis)
    if (hecate.parseFailed) lines.push("        " + hecate.parseError)
    if (hecate.jobs.length === 0 && !hecate.parseFailed) {
      lines.push("jobs    none configured — nothing to show but the truth")
    }
    for (var j = 0; j < hecate.jobs.length; j++) {
      var job = hecate.jobs[j]
      lines.push("JOB " + (job && job.name !== undefined && job.name !== null ? String(job.name) : "unnamed"))
      var src = job && job.source ? job.source : null
      if (src) {
        lines.push("  source  " + (src.path !== undefined && src.path !== null ? String(src.path) : "unknown"))
      }
      // QVariantList check (crossed the boundary): length, not Array.isArray
      var cs = job && job.corners !== undefined && job.corners !== null && job.corners.length > 0
        ? job.corners : []
      for (var i = 1; i <= 3; i++) {
        var c = hecate.cornerAt(cs, i)
        // classified at display time; cornerLine carries the facts
        lines.push("  corner " + i + "  " + (c ? hecate.cornerLine(c) : "none declared"))
      }
    }
    lines.push("")
    lines.push("verdict " + verdict + " (derived from the parsed state file)")
    return lines.join("\n")
  }

  // ------------------------------------------------------------- panel
  property var panelRef: null
  readonly property bool panelOpened: panelRef && panelRef.opened === true

  function openPanel() {
    if (panelRef && typeof panelRef.open === "function") panelRef.open()
  }
  function closePanel() {
    if (panelRef && typeof panelRef.close === "function") panelRef.close()
  }
  // Shape contract for shell.summon/hide/toggle routing (matches Janus).
  readonly property bool opened: panelOpened
  function open() { openPanel() }
  function close() { closePanel() }
  function togglePanel() {
    if (panelRef && typeof panelRef.toggle === "function") panelRef.toggle()
  }

  // ------------------------------------------------------------- layout
  implicitWidth: row.implicitWidth
  implicitHeight: barSize

  MouseArea {
    id: click
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: root.togglePanel()
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)

    Repeater {
      model: 3
      Text {
        required property int index
        text: "●"
        color: root.colorForStatus(root.cornerWorst[index] || "none")
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Item { width: Style.space(3); height: 1 }

    Text {
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      color: root.verdict === "grey" ? root.dim : root.ink
      text: "HECATE"
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Two-step injection (Janus law): bar is null at shell startup when the
  // Loader first fires; re-arm once and again on bar change, or the panel
  // renders without theme/api context.
  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = root
    if ("hostWidget" in t) t.hostWidget = root
    root.panelRef = t
  }

  Connections {
    target: root.hecate
    ignoreUnknownSignals: true
    function onPanelRequested() { root.openPanel() }
    function onWizardRequested(mode) {
      if (panelRef && typeof panelRef.armWizard === "function") panelRef.armWizard(mode)
      root.openPanel()
    }
    function onWizardScreenRequested(step, report) {
      if (panelRef && typeof panelRef.armWizardScreen === "function")
        panelRef.armWizardScreen(step, report)
      root.openPanel()
    }
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
}
