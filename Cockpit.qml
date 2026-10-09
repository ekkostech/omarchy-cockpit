import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Cockpit: repos → worktrees → the agent terminals working in them.
// Data comes from bin/cockpit-scan (git + Hyprland) and, when installed,
// `ekkos-personal work status` for claims on every machine.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "ekkostech.cockpit"
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string home: Quickshell.env("HOME") || ""

  property bool opened: false
  property var state: ({ repos: [], terminals: [], unplaced: [], claims: [] })
  property bool loading: false
  property string scanText: ""
  property string claimsText: ""
  property string deviceId: ""
  property bool ekkos: false
  property string agentCommand: "claude"
  property int repoIndex: 0
  property int wtIndex: 0
  property string pane: "repos"
  property string filter: ""
  property string message: ""
  property var pendingRemove: null

  property string fontFamily: Style.font.menuFamily
  readonly property color surface: Color.menu.background
  readonly property color text: Color.menu.text
  readonly property color muted: Util.alpha(Color.menu.text, 0.6)
  readonly property color subtle: Util.alpha(Color.menu.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color good: "#46a758"
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.space(10)

  readonly property var repos: state.repos.filter(function (r) { return Model.matches(r, root.filter) })
  readonly property var repo: repoIndex >= 0 && repoIndex < repos.length ? repos[repoIndex] : null
  readonly property var worktree: repo && wtIndex >= 0 && wtIndex < repo.worktrees.length ? repo.worktrees[wtIndex] : null

  // ---- lifecycle --------------------------------------------------------
  function open(payloadJson) {
    root.opened = true
    root.message = ""
    root.pendingRemove = null
    root.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function dismiss() { root.close(); if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId) }
  function toggle() { if (root.opened) root.dismiss(); else root.open("{}") }

  function refresh() {
    if (root.loading) return
    root.loading = true
    scanProc.running = true
  }

  function onScan(text) {
    root.scanText = text
    if (root.ekkos) claimsProc.running = true
    else root.finish()
  }

  function finish() {
    root.state = Model.build(root.scanText, root.claimsText, root.deviceId)
    root.repoIndex = Math.max(0, Math.min(root.repoIndex, root.repos.length - 1))
    root.wtIndex = Math.max(0, Math.min(root.wtIndex, root.repo ? root.repo.worktrees.length - 1 : 0))
    root.loading = false
  }

  // ---- actions ----------------------------------------------------------
  function openTerminal(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + path])
    root.message = "Opened a terminal in " + Model.basename(path)
  }

  function launchAgent(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + path, "-e", root.agentCommand])
    root.message = "Started " + root.agentCommand + " in " + Model.basename(path)
  }

  function focusTerminal(term) {
    if (!term) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + term.address + '" })')
    root.dismiss()
  }

  // Removing a worktree asks once; a dirty one needs the capital letter.
  function removeWorktree(force) {
    var w = root.worktree, r = root.repo
    if (!w || !r || w.main) { root.message = "The main checkout can't be removed from here."; return }
    if (w.terminals.length > 0) { root.message = "A terminal is still working in it; close that first."; return }
    if (w.dirty > 0 && !force) { root.message = w.dirty + " uncommitted changes in it. Press X (capital) to remove anyway."; return }
    if (!root.pendingRemove || root.pendingRemove !== w.path) {
      root.pendingRemove = w.path
      root.message = "Remove worktree " + Model.basename(w.path) + (w.ahead > 0 ? " (" + w.ahead + " unpushed commits)" : "") + "? Press again to confirm."
      return
    }
    root.pendingRemove = null
    removeProc.command = ["git", "-C", r.path, "worktree", "remove"].concat(force ? ["--force"] : []).concat([w.path])
    removeProc.running = true
  }

  function prune() {
    if (!root.repo) return
    pruneProc.command = ["git", "-C", root.repo.path, "worktree", "prune", "-v"]
    pruneProc.running = true
  }

  // ---- processes --------------------------------------------------------
  Process {
    id: scanProc
    command: ["bash", root.pluginDir + "/bin/cockpit-scan"]
    stdout: StdioCollector { onStreamFinished: root.onScan(text) }
  }

  Process {
    id: claimsProc
    command: ["ekkos-personal", "work", "status"]
    stdout: StdioCollector { onStreamFinished: { root.claimsText = text; root.finish() } }
  }

  // Once per session: is ekkOS here, which device is this, which agent is default.
  Process {
    id: envProc
    running: true
    command: ["sh", "-c", 'command -v ekkos-personal >/dev/null 2>&1 && printf "ekkos\\n"; '
      + 'd=$(python3 -c "import json;print(json.load(open(\\"$HOME/.config/ekkos-personal/client.json\\")).get(\\"device_id\\",\\"\\"))" 2>/dev/null); printf "device %s\\n" "$d"; '
      + 'a=$(omarchy-default-agent 2>/dev/null | head -n1); printf "agent %s\\n" "${a:-claude}"']
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text).split("\n")
        root.ekkos = lines.indexOf("ekkos") >= 0
        lines.forEach(function (l) {
          if (l.indexOf("device ") === 0) root.deviceId = l.slice(7).trim()
          if (l.indexOf("agent ") === 0 && /^[a-z0-9_.-]+$/.test(l.slice(6).trim())) root.agentCommand = l.slice(6).trim()
        })
      }
    }
  }

  Process {
    id: removeProc
    stderr: StdioCollector { id: removeErr }
    onExited: function (code) {
      root.message = code === 0 ? "Worktree removed." : ("git: " + String(removeErr.text).trim().split("\n").pop())
      root.refresh()
    }
  }

  Process {
    id: pruneProc
    stdout: StdioCollector { id: pruneOut }
    onExited: { var n = String(pruneOut.text).trim(); root.message = n ? n.split("\n").length + " stale entries pruned." : "Nothing to prune."; root.refresh() }
  }

  Timer { interval: 5000; repeat: true; running: root.opened; onTriggered: root.refresh() }

  // ---- UI ---------------------------------------------------------------
  component Chip: Rectangle {
    property string label: ""
    property color tone: root.muted
    property bool solid: false
    width: chipText.implicitWidth + Style.space(10)
    height: chipText.implicitHeight + Style.space(4)
    radius: height / 2
    color: solid ? tone : "transparent"
    border.width: solid ? 0 : Math.max(1, Style.space(1))
    border.color: tone
    Text { id: chipText; anchors.centerIn: parent; text: parent.label; color: parent.solid ? "#ffffff" : parent.tone; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: parent.solid }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: {
      var mon = Hyprland.focusedMonitor
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (mon && screens[i].name === mon.name) return screens[i]
      return screens.length > 0 ? screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cockpit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1100), panel.width - Style.gapsOut * 4)
      height: Math.min(Style.space(640), panel.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.surface
      borderSpec: root.borderSpec
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: root.pad
        focus: true

        Keys.onPressed: function (event) {
          var k = event.key
          if (k === Qt.Key_Escape) { if (root.filter) root.filter = ""; else root.dismiss() }
          else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.pane = root.pane === "repos" ? "worktrees" : "repos"
          else if (k === Qt.Key_Down || (k === Qt.Key_J && !(event.modifiers & Qt.ControlModifier))) root.move(1)
          else if (k === Qt.Key_Up || k === Qt.Key_K) root.move(-1)
          else if (k === Qt.Key_Right || k === Qt.Key_L) root.pane = "worktrees"
          else if (k === Qt.Key_Left || k === Qt.Key_H) root.pane = "repos"
          else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_T) root.openTerminal(root.worktree ? root.worktree.path : (root.repo ? root.repo.path : ""))
          else if (k === Qt.Key_A) root.launchAgent(root.worktree ? root.worktree.path : (root.repo ? root.repo.path : ""))
          else if (k === Qt.Key_F) root.focusTerminal(root.worktree && root.worktree.terminals.length ? root.worktree.terminals[0] : null)
          else if (k === Qt.Key_X && (event.modifiers & Qt.ShiftModifier)) root.removeWorktree(true)
          else if (k === Qt.Key_X) root.removeWorktree(false)
          else if (k === Qt.Key_P) root.prune()
          else if (k === Qt.Key_R) root.refresh()
          else if (k === Qt.Key_Backspace) root.filter = root.filter.slice(0, -1)
          else if (k === Qt.Key_Slash) { root.filter = ""; root.message = "Type to filter; Esc clears." }
          else if (event.text && /^[a-z0-9._\-]$/i.test(event.text) && (root.filter.length > 0 || k === Qt.Key_Slash)) root.filter += event.text
          else return
          event.accepted = true
        }

        Column {
          anchors.fill: parent
          spacing: root.gap

          Item {
            width: parent.width
            height: titleText.implicitHeight
            Text { id: titleText; text: "Cockpit"; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)
              Text { visible: root.filter !== ""; text: "filter: " + root.filter; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
              Text { text: root.loading ? "scanning…" : (root.ekkos ? "git + ekkOS" : "git"); color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            }
          }

          Row {
            width: parent.width
            height: parent.height - titleText.implicitHeight - footer.implicitHeight - root.gap * 2
            spacing: root.gap

            // ---- repos ----
            Rectangle {
              width: Style.space(340)
              height: parent.height
              radius: Style.cornerRadius
              color: "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: root.pane === "repos" ? root.accent : root.subtle

              ListView {
                id: repoList
                anchors.fill: parent
                anchors.margins: Style.space(6)
                clip: true
                model: root.opened ? root.repos : []
                currentIndex: root.repoIndex
                spacing: Style.space(4)
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  width: ListView.view.width
                  height: repoCol.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: index === root.repoIndex ? Color.menu.selectedBackground : "transparent"
                  MouseArea { anchors.fill: parent; onClicked: { root.repoIndex = index; root.wtIndex = 0; root.pane = "repos" } }
                  Column {
                    id: repoCol
                    x: Style.space(8); y: Style.space(6)
                    width: parent.width - Style.space(16)
                    spacing: Style.space(4)
                    Row {
                      spacing: Style.space(8)
                      Rectangle { width: Style.space(8); height: width; radius: width / 2; anchors.verticalCenter: parent.verticalCenter
                        color: modelData.waiting ? root.urgent : modelData.working ? root.good : root.subtle }
                      Text { text: modelData.name; color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: index === root.repoIndex }
                    }
                    Row {
                      spacing: Style.space(6)
                      Chip { label: modelData.worktrees.length + (modelData.worktrees.length === 1 ? " worktree" : " worktrees") }
                      Chip { visible: modelData.terminals > 0; label: modelData.terminals + (modelData.terminals === 1 ? " terminal" : " terminals"); tone: root.accent }
                      Chip { visible: modelData.dirty > 0; label: modelData.dirty + " dirty"; tone: root.urgent }
                      Chip { visible: modelData.warnings.length > 0; label: modelData.warnings.length + " ⚠"; tone: root.urgent }
                    }
                  }
                }
              }
              Text { visible: root.repos.length === 0 && !root.loading; anchors.centerIn: parent; width: parent.width - Style.space(24); wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                text: root.filter ? "Nothing matches." : "No git repos found under ~/Projects, ~/code, ~/src, ~/dev or ~/Work, and no terminal is in one."; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            }

            // ---- worktrees of the selected repo ----
            Rectangle {
              width: parent.width - Style.space(340) - root.gap
              height: parent.height
              radius: Style.cornerRadius
              color: "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: root.pane === "worktrees" ? root.accent : root.subtle

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                Text { visible: root.repo !== null; text: root.repo ? root.repo.path : ""; color: root.muted; elide: Text.ElideMiddle; width: parent.width; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  visible: root.repo !== null && root.repo.warnings.length > 0
                  Repeater { model: root.repo ? root.repo.warnings : []; delegate: Chip { required property var modelData; label: "⚠ " + modelData; tone: root.urgent } }
                }

                ListView {
                  id: wtList
                  width: parent.width
                  height: parent.height - y
                  clip: true
                  spacing: Style.space(4)
                  model: root.opened && root.repo ? root.repo.worktrees : []
                  currentIndex: root.wtIndex
                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: wtCol.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius
                    color: index === root.wtIndex ? Color.menu.selectedBackground : "transparent"
                    MouseArea { anchors.fill: parent; onClicked: { root.wtIndex = index; root.pane = "worktrees" } }
                    Column {
                      id: wtCol
                      x: Style.space(8); y: Style.space(6)
                      width: parent.width - Style.space(16)
                      spacing: Style.space(4)
                      Row {
                        spacing: Style.space(8)
                        Text { text: modelData.branch || ("detached " + modelData.head); color: root.text; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                        Chip { visible: modelData.main; label: "main checkout"; tone: root.accent }
                        Text { text: modelData.head + " · " + modelData.age; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                      }
                      Text { width: parent.width; text: modelData.path; elide: Text.ElideMiddle; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                      Flow {
                        width: parent.width
                        spacing: Style.space(6)
                        Chip { visible: modelData.dirty > 0; label: modelData.dirty + " uncommitted"; tone: root.urgent }
                        Chip { visible: modelData.ahead > 0; label: "↑" + modelData.ahead + " unpushed"; tone: root.urgent }
                        Chip { visible: modelData.behind > 0; label: "↓" + modelData.behind + " behind"; tone: root.muted }
                        Chip { visible: modelData.upstream === "" && !modelData.main; label: "no upstream"; tone: root.muted }
                        Repeater {
                          model: modelData.terminals
                          delegate: Chip { required property var modelData; label: (modelData.agent === "working" ? "◐ " : modelData.agent === "idle" ? "✳ " : "▣ ") + String(modelData.title).replace(/^[◐◑◒◓✳]\s*/, "").slice(0, 36); tone: modelData.agent === "idle" ? root.urgent : modelData.agent === "working" ? root.good : root.accent; solid: true }
                        }
                        Chip { visible: modelData.claim !== null; label: modelData.claim ? ("claim: " + modelData.claim.agent + " · " + modelData.claim.state + (modelData.claim.stale ? " (stale)" : "") + " · " + Model.ago((root.state.now || Date.now() / 1000) - modelData.claim.updated)) : ""; tone: modelData.claim && modelData.claim.stale ? root.urgent : root.muted }
                      }
                      Text { visible: modelData.claim !== null && modelData.claim.task !== ""; width: parent.width; text: modelData.claim ? modelData.claim.task : ""; elide: Text.ElideRight; color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    }
                  }
                }
              }
            }
          }

          Text {
            id: footer
            width: parent.width
            elide: Text.ElideRight
            text: root.message || ("Enter/T terminal here · A start " + root.agentCommand + " · F focus its terminal · X remove worktree · P prune · R refresh · / filter · Tab panes · Esc"
              + (root.state.unplaced.length > 0 ? " · " + root.state.unplaced.length + " terminals outside any repo" : ""))
            color: root.message ? root.text : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  function move(delta) {
    if (root.pane === "repos") {
      var n = root.repos.length; if (n === 0) return
      root.repoIndex = (root.repoIndex + delta + n) % n; root.wtIndex = 0
    } else {
      var m = root.repo ? root.repo.worktrees.length : 0; if (m === 0) return
      root.wtIndex = (root.wtIndex + delta + m) % m
    }
  }
}
