import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Strings.js" as Loc

// Hecate panel — v0.0.1 WALKING SKELETON (M1, redo brief).
// Renders ONLY what the service parsed from ~/.local/state/hecate/state.json.
// No literal state, no demo switch, nothing invented. The source is its own
// row and is not a corner; the three corners are rows with transport,
// destination, status, and the file's own words for what it knows.
Panel {
  id: root

  moduleName: "io.github.m10ust.hecate"
  ipcTarget: "io.github.m10ust.hecate"
  manageIpc: false   // the service owns the io.github.m10ust.hecate IPC target

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  readonly property var hecate: hostWidget && hostWidget.hecate !== undefined
    ? hostWidget.hecate
    : null

  // ---- the wizard (M4): a mode of this panel, not a second surface
  property bool wizardActive: false
  function startWizard() { armWizard("new") }
  function startReentry() { armWizard("reentry") }

  // receipts lane + bar routing: arm the wizard in a mode, then open
  function armWizard(mode) {
    wizardActive = true
    wizardMode = (mode === "reentry") ? "reentry" : "new"
    armWizardItem()
  }
  property string wizardMode: "new"

  // receipts lane: render one wizard screen with a real engine report
  function armWizardScreen(step, report) {
    wizardActive = true
    wizardMode = "new"
    var it = wizardLoader.item
    if (it && typeof it.armScreen === "function") {
      if (it.hecate === undefined || it.hecate !== root.hecate) it.hecate = root.hecate
      it.armScreen(step, report)
    } else {
      pendingScreen = [step, report]
    }
  }
  property var pendingScreen: null

  // idempotent: hand the loaded wizard its mode once the service has jobs
  function armWizardItem() {
    var it = wizardLoader.item
    if (!it) return
    if (root.hecate) root.hecate.wizardDebug = "mode=" + it.mode + " step=" + it.step
      + " measure=" + (it.sourceMeasure !== null ? "set" : "null")
      + " report=" + (it.checkReport !== null ? String(it.checkReport.verdict) : "none")
    if (it.hecate === undefined || it.hecate !== root.hecate) it.hecate = root.hecate
    if (pendingScreen !== null) {
      it.armScreen(pendingScreen[0], pendingScreen[1])
      pendingScreen = null
      return
    }
    if (root.wizardMode === "reentry" && root.hecate && root.hecate.jobs.length > 0) {
      if (it.mode !== "reentry") it.startReentry(root.hecate.jobs[0])
    } else if (it.mode === "idle") {
      it.startNew()
    }
  }
  // re-arm when jobs arrive late (fresh-shell async parse). startNew() WIPES
  // an armed screen (it resets the wizard), so late arrivals only adopt an
  // idle wizard, never one already showing a screen.
  onHecateChanged: Qt.callLater(function() {
    if (wizardLoader.item && wizardLoader.item.mode === "idle") armWizardItem()
  })
  Connections {
    target: root.hecate
    ignoreUnknownSignals: true
    function onJobsChanged() {
      if (root.wizardActive && wizardLoader.item && wizardLoader.item.mode === "idle")
        Qt.callLater(root.armWizardItem)
    }
  }

  readonly property color ink: bar ? bar.barForeground : Color.foreground
  readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, 0.78)
  readonly property color goodC: "#56d060"
  readonly property color amberC: "#d29922"
  readonly property color badC: "#f85149"
  readonly property string mono: bar ? bar.fontFamily : Style.font.family

  // status → colour. `unknown` and `away` lean amber by the plan's law 4
  // (four words after the accepted M1 finding) — absence is never green.
  function statusColor(status) {
    if (status === "current") return goodC
    if (status === "failed" || status === "missing") return badC
    if (status === "stale" || status === "unknown" || status === "away") return amberC
    return secondary
  }

  function cornerAt(corners, idx) {
    if (!root.hecate) return null
    return root.hecate.cornerAt(corners, idx)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.wizardActive
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            iconComponent: Component {
              Text {
                text: "⬢"
                color: Color.accent
                font.family: root.mono
                font.pixelSize: Style.font.display
              }
            }
            title: "HECATE"
            detail: "three-corner backups"
            meta: root.hecate ? root.hecate.version : ""
          }

          PanelSeparator {}

          // ---- the wizard (M4): six steps, re-enterable, strings from
          // Strings.js, engine the only writer
          Loader {
            id: wizardLoader
            active: root.wizardActive
            width: parent.width
            source: Qt.resolvedUrl("Wizard.qml")
            // arm on load AND re-arm when the service's jobs arrive (a
            // fresh shell parses the state file asynchronously; jobs can
            // land after onLoaded)
            onLoaded: root.armWizardItem()
            Connections {
              target: wizardLoader.item
              ignoreUnknownSignals: true
              function onWizardDone() { root.wizardActive = false }
              // M5.5a: the chooser maps under the panel's full-screen
              // overlay dismissal surface; while it runs the panel must
              // be hidden, and every picker outcome reopens it. The
              // wizard tree (and the picker process) survive a hidden
              // window — this Loader keys on wizardActive, not
              // visibility, and the close was the dismissal surface's,
              // not the wizard's own.
              function onPickerPanelWanted(open) {
                if (open) root.open()
                else root.close()
              }
            }
          }

          // the wizard replaces the status pages while it is open
          Loader {
            active: !root.wizardActive
            width: parent.width
            sourceComponent: statusPages
          }

          Component {
            id: statusPages
            Column {
              width: parent.width
              spacing: Style.space(10)
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: Color.muted
            font.family: root.mono
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            text: "state   " + (root.hecate ? root.hecate.fileBasis : "service not loaded")
              + (root.hecate && root.hecate.parseFailed ? "\n        " + root.hecate.parseError : "")
          }

          // ---- parse failure: the honest page
          Loader {
            active: root.hecate && root.hecate.parseFailed
            width: parent.width
            sourceComponent: Component {
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: root.badC
                font.family: root.mono
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
                text: root.hecate ? root.hecate.parseError : ""
              }
            }
          }

          // ---- not configured: the honest page, with the door to the wizard
          Loader {
            active: root.hecate && !root.hecate.parseFailed && root.hecate.jobs.length === 0
            width: parent.width
            sourceComponent: Component {
              Column {
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader { text: "NOTHING CONFIGURED" }

                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  color: root.secondary
                  font.family: root.mono
                  font.pixelSize: Style.font.bodySmall
                  textFormat: Text.PlainText
                  text: "No jobs are configured, so there is nothing to report.\nThe grey glyphs are the true state: nothing is protected.\nSet up a source and three corners with the wizard."
                }

                Button {
                  text: "SET UP BACKUPS"
                  onClicked: root.startWizard()
                }
              }
            }
          }

          // ---- configured: the wizard remains a first-class door (re-entry)
          Loader {
            active: root.hecate && !root.hecate.parseFailed && root.hecate.jobs.length > 0 && !root.wizardActive
            width: parent.width
            sourceComponent: Component {
              Item {
                width: parent.width
                height: reenterBtn.height
                Button {
                  id: reenterBtn
                  anchors.right: parent.right
                  text: Loc.S.reenterButton
                  onClicked: root.startReentry()
                }
              }
            }
          }

          // ---- jobs: the source row (not a corner) + corners 1–3
          Repeater {
            model: root.hecate ? root.hecate.jobs : []
            delegate: Column {
              id: jobCol
              required property var modelData
              width: contentColumn.width
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "SOURCE — " + (jobCol.modelData && jobCol.modelData.name !== undefined && jobCol.modelData.name !== null
                  ? String(jobCol.modelData.name) : "unnamed job")
              }

              Row {
                width: parent.width
                leftPadding: Style.space(4)
                spacing: Style.space(10)

                Text {
                  text: "SRC"
                  color: root.secondary
                  font.family: root.mono
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  spacing: 0
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(10) - srcSizeCol.width - Style.space(40)

                  Text {
                    text: jobCol.modelData && jobCol.modelData.source && jobCol.modelData.source.path !== undefined
                      ? String(jobCol.modelData.source.path) : "unknown"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideMiddle
                    width: parent.width
                  }
                  Text {
                    text: jobCol.modelData && jobCol.modelData.source
                      ? (jobCol.modelData.source.readError || (root.hecate.fmtCount(jobCol.modelData.source.files) + " files · "
                        + root.hecate.fmtBytes(jobCol.modelData.source.bytes) + " · as written by "
                        + (root.hecate.writtenBy || "unknown writer")))
                      : "source unknown"
                    color: root.secondary
                    font.family: root.mono
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                Column {
                  id: srcSizeCol
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    anchors.right: parent.right
                    text: jobCol.modelData && jobCol.modelData.source
                      ? root.hecate.fmtBytes(jobCol.modelData.source.bytes) : ""
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }

              PanelSeparator {}

              PanelSectionHeader { text: "CORNERS" }

              // Nothing runs from the bar without a click (plan law). This
              // is the click: the human triggers, the engine copies, the
              // watcher re-reads the state the engine wrote.
              Row {
                width: parent.width
                spacing: Style.space(8)

                PanelActionButton {
                  iconText: root.hecate && root.hecate.engineRunning ? "…" : "▶"
                  tooltipText: root.hecate && root.hecate.engineRunning
                    ? Loc.S.firstRunRunning : Loc.S.firstRunStart
                  foreground: Color.foreground
                  enabled: root.hecate && !root.hecate.engineRunning && !root.hecate.verifyRunning
                  onClicked: {
                    if (root.hecate) root.hecate.ipcRun(jobCol.modelData.name)
                  }
                }

                PanelActionButton {
                  iconText: root.hecate && root.hecate.verifyRunning ? "…" : "✓"
                  tooltipText: root.hecate && root.hecate.verifyRunning
                    ? Loc.S.verifyRunning : Loc.S.verifyButton
                  foreground: Color.foreground
                  enabled: root.hecate && !root.hecate.verifyRunning && !root.hecate.engineRunning
                  onClicked: {
                    if (root.hecate) root.hecate.ipcVerify(jobCol.modelData.name)
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.hecate && root.hecate.engineRunning
                  text: Loc.S.firstRunRunning
                  color: Color.muted
                  font.family: root.mono
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Repeater {
                model: 3
                delegate: Row {
                  id: cornerRow
                  required property int index
                  readonly property var job: jobCol.modelData
                  // NOTE: no Array.isArray gate — arrays that crossed the
                  // model boundary arrive as QVariantList, which
                  // Array.isArray rejects. Length-check instead.
                  readonly property var corners:
                    job && job.corners !== undefined && job.corners !== null && job.corners.length > 0
                      ? job.corners : []
                  readonly property var c: root.hecate ? root.hecate.cornerAt(corners, index + 1) : null
                  width: contentColumn.width
                  leftPadding: Style.space(4)
                  rightPadding: Style.space(4)
                  spacing: Style.space(10)

                  Text {
                    text: cornerRow.index + 1
                    color: root.secondary
                    font.family: root.mono
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    spacing: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(10) - stateCol.width - Style.space(20)

                    Text {
                      text: cornerRow.c
                        ? (String(cornerRow.c.transport !== undefined && cornerRow.c.transport !== null ? cornerRow.c.transport : "unknown")
                          + " · "
                          + String(cornerRow.c.destination !== undefined && cornerRow.c.destination !== null ? cornerRow.c.destination : "unknown"))
                        : Loc.S.cornerIdentityUnknown
                      color: root.ink
                      font.family: root.mono
                      font.pixelSize: Style.font.body
                      elide: Text.ElideMiddle
                      width: parent.width
                    }
                    Text {
                      text: cornerRow.c
                        ? root.hecate.cornerReason(cornerRow.c)
                        : Loc.S.reenterButton
                      color: root.secondary
                      font.family: root.mono
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.Wrap
                      width: parent.width
                    }
                    Text {
                      visible: cornerRow.c !== null
                      // M5: `verified` is an OBJECT — a basis, not a verdict
                      text: cornerRow.c ? (cornerRow.c.verified
                        && typeof cornerRow.c.verified === "object"
                        ? ("basis " + String(cornerRow.c.verified.basis)
                           + " · " + (cornerRow.c.verified.hashed || 0) + " hashed / "
                           + (cornerRow.c.verified.inherited || 0) + " inherited"
                           + " · " + String(cornerRow.c.verified.at || Loc.S.cornerIdentityUnknown)
                           + (cornerRow.c.snapshot ? " · " + String(cornerRow.c.snapshot).split("/").slice(-2).join("/") : ""))
                        : cornerRow.c.verified === true ? "list-verified (pre-M5 shape)"
                        : cornerRow.c.verified === false ? String((cornerRow.c.override || {}).reason || Loc.S.cornerIdentityUnknown) : "never verified")
                        : ""
                      color: cornerRow.c && cornerRow.c.verified === false ? root.badC : Color.muted
                      font.family: root.mono
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideMiddle
                      width: parent.width
                    }
                    Text {
                      // M5: the last scrub's measured fact (re-read + rehash)
                      visible: cornerRow.c !== null && cornerRow.c.scrub !== undefined
                      text: cornerRow.c && cornerRow.c.scrub
                        ? (cornerRow.c.scrub.ok === true
                           ? "scrub OK · " + (cornerRow.c.scrub.files !== undefined ? cornerRow.c.scrub.files + " files rehashed" : "all files rehashed")
                           : "scrub FAILED · " + String(cornerRow.c.scrub.reason || "see override"))
                           + " · " + String(cornerRow.c.scrub.at || Loc.S.cornerIdentityUnknown)
                           + " · " + String(cornerRow.c.scrub.snapshot || Loc.S.cornerIdentityUnknown)
                        : ""
                      color: cornerRow.c && cornerRow.c.scrub && cornerRow.c.scrub.ok === false ? root.badC : Color.muted
                      font.family: root.mono
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideMiddle
                      width: parent.width
                    }
                  }

                  Column {
                    id: stateCol
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      anchors.right: parent.right
                      // the word is classified at display time from
                      // lastRun + horizon + override — never stored.
                      // An undeclared corner is not "missing" (red) —
                      // nothing declared it; grey "none" is the truth.
                      text: cornerRow.c ? root.hecate.classifyCorner(cornerRow.c) : "none"
                      color: cornerRow.c ? root.statusColor(root.hecate.classifyCorner(cornerRow.c)) : Color.muted
                      font.family: root.mono
                      font.pixelSize: Style.font.body
                      font.bold: cornerRow.c !== null
                    }
                    Text {
                      anchors.right: parent.right
                      visible: cornerRow.c !== null
                      text: cornerRow.c && cornerRow.c.lastRun !== undefined && cornerRow.c.lastRun !== null
                        ? "run " + String(cornerRow.c.lastRun).slice(5, 16).replace("T", " ") : "never run"
                      color: Color.muted
                      font.family: root.mono
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
            }
          }

          PanelSeparator {}

          PanelSectionHeader { text: "STATE" }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: Color.muted
            font.family: root.mono
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
            text: root.hecate ? root.hecate.timerLog + "\n" + root.hecate.engineLog + "\n" + root.hecate.verifyLog : ""
          }
            }
          }
        }
      }
    }
  }
}
