import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "ekkostech.cockpit"
  readonly property string version: (manifest && manifest.version) || "0.2.0"
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  property bool opened: false
  property var state: ({
      repos: [],
      terminals: [],
      unplaced: [],
      claims: []
    })
  property var inventory: ({
      status: "not checked",
      terminalStatus: "not checked",
      capabilities: {},
      roots: []
    })
  property var settings: ({
      pins: [],
      roots: []
    })
  property var details: ({
      path: "",
      files: [],
      commits: [],
      handoff: null
    })
  property string selectedRepoPath: ""
  property string selectedWorktreePath: ""
  property string pane: "repos"
  property string filter: ""
  property string mode: "all"
  property string sortMode: "attention"
  property string detailTab: "overview"
  property string message: ""
  property string scanError: ""
  property string detailError: ""
  property bool showSettings: false
  property bool showLoose: false
  property string pendingRemove: ""
  property var detailRequest: ({})
  property var actionRequest: ({})
  property string agentCommand: ""
  property bool detailAgain: false
  property double refreshedAt: 0
  readonly property bool loading: scanProc.running
  readonly property var repos: Model.visible(state.repos, filter, mode, settings.pins || [], sortMode)
  readonly property int repoIndex: Model.selectedIndex(repos, selectedRepoPath)
  readonly property var repo: repoIndex >= 0 ? repos[repoIndex] : null
  readonly property int wtIndex: Model.selectedIndex(repo ? repo.worktrees : [], selectedWorktreePath)
  readonly property var worktree: repo && wtIndex >= 0 ? repo.worktrees[wtIndex] : null
  readonly property var stats: Model.summary(state.repos)
  readonly property string cleanupReason: Model.cleanupReason(worktree)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property color surface: Color.menu.background
  readonly property color text: Color.menu.text
  readonly property color muted: Util.alpha(Color.menu.text, 0.6)
  readonly property color subtle: Util.alpha(Color.menu.text, 0.14)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color good: "#46a758"
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int gap: Style.space(10)
  onMessageChanged: messageLater.restart()
  onWorktreeChanged: {
    root.pendingRemove = "";
    detailLater.restart();
  }
  onFilterChanged: root.pendingRemove = ""
  onModeChanged: root.pendingRemove = ""
  function open(payload) {
    root.opened = true;
    root.refresh();
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus();
    });
  }
  function close() {
    root.opened = false;
  }
  function dismiss() {
    root.close();
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId);
  }
  function toggle() {
    if (opened)
      dismiss();
    else
      open("{}");
  }
  function status(arg) {
    return JSON.stringify({
      version: version,
      opened: opened,
      loading: loading,
      repos: stats.repos,
      worktrees: stats.worktrees,
      terminals: stats.terminals,
      selectedRepo: repo ? repo.path : "",
      selectedWorktree: worktree ? worktree.path : "",
      error: scanError
    });
  }
  function refresh() {
    if (!scanProc.running)
      scanProc.running = true;
  }
  function consumeScan(value) {
    if (!value || !Array.isArray(value.repos))
      throw new Error("Invalid inventory");
    var rp = root.repo ? root.repo.path : root.selectedRepoPath, wp = root.worktree ? root.worktree.path : root.selectedWorktreePath;
    root.inventory = value;
    root.settings = value.settings || {
      pins: [],
      roots: []
    };
    root.agentCommand = value.agentCommand || "";
    root.state = Model.build(JSON.stringify(value), JSON.stringify({
      claims: value.claims || []
    }), value.device || "");
    root.selectedRepoPath = rp;
    root.selectedWorktreePath = wp;
    if (root.repo)
      root.selectedRepoPath = root.repo.path;
    if (root.worktree)
      root.selectedWorktreePath = root.worktree.path;
    root.scanError = "";
    root.refreshedAt = Date.now();
    root.loadDetail();
  }
  function chooseRepo(index) {
    if (!repos[index])
      return;
    selectedRepoPath = repos[index].path;
    selectedWorktreePath = "";
    pane = "repos";
    keyCatcher.forceActiveFocus();
  }
  function chooseWorktree(index) {
    if (!repo || !repo.worktrees[index])
      return;
    selectedWorktreePath = repo.worktrees[index].path;
    pane = "worktrees";
    keyCatcher.forceActiveFocus();
  }
  function move(delta) {
    var list = pane === "repos" ? repos : (repo ? repo.worktrees : []);
    if (!list.length)
      return;
    var index = pane === "repos" ? repoIndex : wtIndex;
    index = (index + delta + list.length) % list.length;
    if (pane === "repos")
      chooseRepo(index);
    else
      chooseWorktree(index);
  }
  function loadDetail() {
    if (!root.opened || !root.worktree)
      return;
    if (detailProc.running) {
      root.detailAgain = true;
      return;
    }
    root.detailAgain = false;
    root.detailError = "";
    root.detailRequest = {
      path: root.worktree.path,
      project: root.repo.name
    };
    detailProc.running = true;
  }
  function runAction(request) {
    if (actionProc.running)
      return;
    root.actionRequest = request;
    actionProc.running = true;
  }
  function removeWorktree() {
    if (root.cleanupReason) {
      root.message = root.cleanupReason;
      return;
    }
    if (root.pendingRemove !== root.worktree.path) {
      root.pendingRemove = root.worktree.path;
      root.message = "Remove this clean, published worktree? Click Confirm remove to continue.";
      return;
    }
    root.pendingRemove = "";
    root.runAction({
      action: "remove",
      repo: root.repo.path,
      path: root.worktree.path
    });
  }
  function openTerminal() {
    if (worktree)
      Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + worktree.path]);
  }
  function launchAgent() {
    if (!worktree || !agentCommand)
      return;
    if (worktree.claim && worktree.claim.state === "active") {
      root.message = "This worktree already has an agent claim. Focus its terminal or coordinate the claim first.";
      return;
    }
    Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + worktree.path, "-e", agentCommand]);
    root.message = "Started " + agentCommand;
  }
  function focusTerminal(term) {
    if (!term || !/^0x[0-9a-f]+$/i.test(term.address))
      return;
    Hyprland.dispatch('hl.dsp.focus({window="address:' + term.address + '"})');
    root.dismiss();
  }
  function ombreTerminal(term) {
    root.focusTerminal(term);
    ombreLater.restart();
  }
  function editor() {
    if (worktree && root.inventory.capabilities["omarchy-launch-editor"])
      Quickshell.execDetached(["omarchy-launch-editor", worktree.path]);
  }
  function gitView() {
    if (worktree && root.inventory.capabilities.lazygit)
      Quickshell.execDetached(["xdg-terminal-exec", "--dir=" + worktree.path, "-e", "lazygit"]);
  }
  function folder() {
    if (worktree)
      Quickshell.execDetached(["xdg-open", "file://" + encodeURI(worktree.path).replace(/#/g, "%23").replace(/\?/g, "%3F")]);
  }
  function copyPath() {
    if (worktree && !copyProc.running) {
      copyProc.pathText = worktree.path;
      copyProc.running = true;
    }
  }
  Timer {
    id: messageLater
    interval: 7000
    onTriggered: if (!root.pendingRemove)
      root.message = ""
  }
  Timer {
    id: ombreLater
    interval: 120
    onTriggered: Quickshell.execDetached(["omarchy-shell", "shell", "summon", "ekkostech.ombre", "{}"])
  }
  Timer {
    id: detailLater
    interval: 160
    onTriggered: root.loadDetail()
  }
  Timer {
    interval: 10000
    repeat: true
    running: root.opened
    onTriggered: root.refresh()
  }
  Process {
    id: scanProc
    command: ["python3", "-I", root.pluginDir + "/bin/cockpit-scan"]
    stdout: StdioCollector {
      id: scanOut
    }
    stderr: StdioCollector {
      id: scanErr
    }
    onExited: function (code) {
      try {
        if (code !== 0)
          throw new Error(String(scanErr.text).trim() || "Inventory failed");
        root.consumeScan(JSON.parse(scanOut.text));
      } catch (e) {
        root.scanError = String(e);
      }
    }
  }
  Process {
    id: detailProc
    command: ["python3", "-I", root.pluginDir + "/bin/cockpit-scan", "--detail"]
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(root.detailRequest));
      stdinEnabled = false;
    }
    stdout: StdioCollector {
      id: detailOut
    }
    onExited: function (code) {
      try {
        var d = JSON.parse(detailOut.text);
        if (code !== 0)
          throw new Error(d.error);
        if (root.worktree && d.path === root.worktree.path)
          root.details = d;
      } catch (e) {
        root.detailError = String(e);
      }
      stdinEnabled = true;
      if (root.detailAgain)
        detailLater.restart();
    }
  }
  Process {
    id: actionProc
    command: ["python3", "-I", root.pluginDir + "/bin/cockpit-scan", "--action"]
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(root.actionRequest));
      stdinEnabled = false;
    }
    stdout: StdioCollector {
      id: actionOut
    }
    onExited: function (code) {
      try {
        var r = JSON.parse(actionOut.text);
        root.message = r.error || r.message || "Done";
        if (r.settings)
          root.settings = r.settings;
      } catch (e) {
        root.message = "Action failed. Refresh and try again.";
      }
      stdinEnabled = true;
      root.refresh();
    }
  }
  Process {
    id: copyProc
    property string pathText: ""
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      write(pathText);
      stdinEnabled = false;
    }
    onExited: function (code) {
      root.message = code === 0 ? "Worktree path copied." : "Could not access clipboard.";
      stdinEnabled = true;
    }
  }
  component Label: Text {
    color: root.text
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
    textFormat: Text.PlainText
  }
  component Button: Rectangle {
    id: button
    property string label: ""
    property bool chosen: false
    property bool danger: false
    signal clicked
    implicitWidth: caption.implicitWidth + Style.space(18)
    implicitHeight: Style.space(30)
    color: chosen ? Color.menu.selectedBackground : mouse.containsMouse ? Util.alpha(root.accent, 0.12) : "transparent"
    border.width: 1
    border.color: chosen ? root.accent : root.subtle
    radius: Style.space(3)
    opacity: enabled ? 1 : 0.4
    Label {
      id: caption
      anchors.centerIn: parent
      text: button.label
      color: button.danger ? root.urgent : root.text
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: if (enabled)
      clicked()
  }
  component Heading: Label {
    font.bold: true
    font.pixelSize: Style.font.body
    width: parent.width
  }
  component Paragraph: Label {
    width: parent.width
    wrapMode: Text.Wrap
    elide: Text.ElideNone
  }
  PanelWindow {
    id: panel
    visible: !!(root.opened)
    screen: {
      var mon = Hyprland.focusedMonitor;
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (mon && Quickshell.screens[i].name === mon.name)
          return Quickshell.screens[i];
      return Quickshell.screens[0] || null;
    }
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cockpit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }
    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1440), panel.width - Style.gapsOut * 4)
      height: Math.min(Style.space(880), panel.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.surface
      borderSpec: root.borderSpec
      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }
      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        focus: true
        Keys.onPressed: function (event) {
          var k = event.key;
          if (k === Qt.Key_Escape) {
            if (root.showSettings)
              root.showSettings = false;
            else if (root.filter)
              root.filter = "";
            else
              root.dismiss();
          } else if (k === Qt.Key_Slash || (k === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
            search.forceActiveFocus();
            search.selectAll();
          } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab)
            root.pane = root.pane === "repos" ? "worktrees" : "repos";
          else if (k === Qt.Key_Down || k === Qt.Key_J)
            root.move(1);
          else if (k === Qt.Key_Up || k === Qt.Key_K)
            root.move(-1);
          else if (k === Qt.Key_Left || k === Qt.Key_H)
            root.pane = "repos";
          else if (k === Qt.Key_Right || k === Qt.Key_L)
            root.pane = "worktrees";
          else if (k === Qt.Key_Return || k === Qt.Key_T)
            root.openTerminal();
          else if (k === Qt.Key_A)
            root.launchAgent();
          else if (k === Qt.Key_E)
            root.editor();
          else if (k === Qt.Key_G)
            root.gitView();
          else if (k === Qt.Key_F)
            root.focusTerminal(root.worktree && root.worktree.terminals[0]);
          else if (k === Qt.Key_R)
            root.refresh();
          else
            return;
          event.accepted = true;
        }
        Column {
          id: layout
          anchors.fill: parent
          spacing: root.gap
          Item {
            width: parent.width
            height: Style.space(50)
            Row {
              spacing: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              Rectangle {
                width: Style.space(40)
                height: width
                color: "transparent"
                border.width: 2
                border.color: root.accent
                radius: Style.space(8)
                Label {
                  anchors.centerIn: parent
                  text: "⌘"
                  font.pixelSize: Style.font.heading
                  color: root.accent
                }
              }
              Column {
                Heading {
                  text: "COCKPIT"
                  width: implicitWidth
                }
                Label {
                  text: "v" + root.version + "  ·  Your work, in view"
                  color: root.muted
                }
              }
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Button {
                label: root.loading ? "Refreshing…" : "Refresh"
                enabled: !!(!root.loading)
                onClicked: root.refresh()
              }
              Button {
                label: "Settings"
                chosen: root.showSettings
                onClicked: root.showSettings = !root.showSettings
              }
              Button {
                label: "Close"
                onClicked: root.dismiss()
              }
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(8)
            Label {
              text: root.stats.repos + " projects  ·  " + root.stats.worktrees + " worktrees  ·  " + root.stats.terminals + " terminals"
              height: Style.space(30)
              verticalAlignment: Text.AlignVCenter
            }
            Button {
              label: root.stats.working + " working"
              onClicked: root.mode = "active"
            }
            Button {
              label: root.stats.waiting + " waiting"
              danger: root.stats.waiting > 0
              onClicked: root.mode = "attention"
            }
            Button {
              label: root.stats.attention + " need attention"
              chosen: root.mode === "attention"
              onClicked: root.mode = root.mode === "attention" ? "all" : "attention"
            }
            Button {
              label: root.state.unplaced.length + " outside repos"
              chosen: root.showLoose
              onClicked: root.showLoose = !root.showLoose
            }
          }
          Row {
            width: parent.width
            spacing: Style.space(8)
            TextField {
              id: search
              width: Math.max(Style.space(160), parent.width - filterButtons.width - Style.space(8))
              placeholderText: "Search projects, branches, tasks or terminals…"
              text: root.filter
              onTextChanged: root.filter = text
              Keys.onEscapePressed: {
                root.filter = "";
                keyCatcher.forceActiveFocus();
              }
              Keys.onReturnPressed: keyCatcher.forceActiveFocus()
            }
            Row {
              id: filterButtons
              spacing: Style.space(6)
              Repeater {
                model: [
                  {
                    id: "all",
                    label: "All"
                  },
                  {
                    id: "attention",
                    label: "Attention"
                  },
                  {
                    id: "active",
                    label: "Active"
                  },
                  {
                    id: "pinned",
                    label: "Pinned"
                  }
                ]
                delegate: Button {
                  required property var modelData
                  label: modelData.label
                  chosen: root.mode === modelData.id
                  onClicked: root.mode = modelData.id
                }
              }
              Button {
                label: root.sortMode === "name" ? "A–Z" : "Priority"
                onClicked: root.sortMode = root.sortMode === "name" ? "attention" : "name"
              }
            }
          }
          Column {
            visible: !!(root.showSettings)
            width: parent.width
            spacing: Style.space(6)
            Paragraph {
              text: "Scan folders · defaults: ~/Projects, ~/code, ~/src, ~/dev, ~/Work. Adding a folder replaces the defaults; remove all custom folders to restore them."
              color: root.muted
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              TextField {
                id: rootInput
                width: parent.width - addRoot.width - Style.space(8)
                placeholderText: "/path/to/projects"
                Keys.onReturnPressed: root.runAction({
                  action: "root-add",
                  path: text
                })
              }
              Button {
                id: addRoot
                label: "Add folder"
                enabled: !!(rootInput.text.trim().length > 0 && !actionProc.running)
                onClicked: root.runAction({
                  action: "root-add",
                  path: rootInput.text
                })
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.settings.roots || []
                delegate: Button {
                  required property var modelData
                  label: modelData + " ×"
                  onClicked: root.runAction({
                    action: "root-remove",
                    path: modelData
                  })
                }
              }
            }
          }
          Paragraph {
            visible: !!(root.scanError !== "")
            text: "Refresh failed. Showing the last inventory. " + root.scanError
            color: root.urgent
          }
          Row {
            id: panes
            width: parent.width
            height: Math.max(Style.space(160), layout.height - y - statusLine.height - root.gap)
            spacing: root.gap
            Rectangle {
              width: parent.width * 0.23
              height: parent.height
              color: "transparent"
              border.width: 1
              border.color: root.pane === "repos" ? root.accent : root.subtle
              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)
                Heading {
                  text: "PROJECTS  " + root.repos.length
                }
                ListView {
                  id: repoList
                  width: parent.width
                  height: parent.height - y
                  clip: true
                  spacing: Style.space(4)
                  model: root.repos
                  currentIndex: root.repoIndex
                  onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: repoCol.implicitHeight + Style.space(18)
                    color: index === root.repoIndex ? Color.menu.selectedBackground : "transparent"
                    radius: Style.space(4)
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.chooseRepo(index)
                    }
                    Column {
                      id: repoCol
                      x: Style.space(8)
                      y: Style.space(8)
                      width: parent.width - Style.space(16)
                      spacing: Style.space(5)
                      Heading {
                        text: ((root.settings.pins || []).indexOf(modelData.path) >= 0 ? "★ " : "") + modelData.name
                      }
                      Label {
                        width: parent.width
                        text: modelData.worktrees.length + " worktrees · " + modelData.terminals + " terminals"
                        color: root.muted
                      }
                      Label {
                        width: parent.width
                        text: modelData.error ? "Inventory unavailable" : modelData.waiting ? "Waiting for you" : modelData.working ? "Agent working" : modelData.dirty ? modelData.dirty + " uncommitted changes" : Model.attention(modelData) ? "Needs attention" : "Up to date"
                        color: Model.attention(modelData) ? root.urgent : modelData.working ? root.good : root.muted
                      }
                    }
                  }
                  Label {
                    anchors.centerIn: parent
                    visible: !!(repoList.count === 0)
                    text: root.loading ? "Scanning…" : "No matching projects"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }
            Rectangle {
              width: parent.width * 0.31
              height: parent.height
              color: "transparent"
              border.width: 1
              border.color: root.pane === "worktrees" ? root.accent : root.subtle
              Column {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)
                Row {
                  width: parent.width
                  Heading {
                    width: parent.width - pinButton.width - Style.space(8)
                    text: root.repo ? root.repo.name : "WORKTREES"
                  }
                  Button {
                    id: pinButton
                    label: root.repo && (root.settings.pins || []).indexOf(root.repo.path) >= 0 ? "★" : "☆"
                    enabled: !!(root.repo !== null && !actionProc.running)
                    onClicked: root.runAction({
                      action: "pin",
                      path: root.repo.path
                    })
                  }
                }
                Label {
                  width: parent.width
                  text: root.repo ? root.repo.path : ""
                  elide: Text.ElideMiddle
                  color: root.muted
                }
                ListView {
                  id: wtList
                  width: parent.width
                  height: parent.height - y
                  clip: true
                  spacing: Style.space(4)
                  model: root.repo ? root.repo.worktrees : []
                  currentIndex: root.wtIndex
                  onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: wtCol.implicitHeight + Style.space(18)
                    color: index === root.wtIndex ? Color.menu.selectedBackground : "transparent"
                    radius: Style.space(4)
                    MouseArea {
                      anchors.fill: parent
                      onClicked: root.chooseWorktree(index)
                    }
                    Column {
                      id: wtCol
                      x: Style.space(8)
                      y: Style.space(8)
                      width: parent.width - Style.space(16)
                      spacing: Style.space(5)
                      Heading {
                        text: modelData.branch || "Detached " + modelData.head.slice(0, 7)
                      }
                      Label {
                        width: parent.width
                        text: (modelData.main ? "Main checkout · " : "") + modelData.head.slice(0, 7) + " · " + modelData.age
                        color: root.muted
                      }
                      Label {
                        width: parent.width
                        text: !modelData.statusKnown ? "Git status unavailable" : modelData.dirty ? modelData.dirty + " changed files" : modelData.ahead > 0 ? "↑ " + modelData.ahead + " unpushed" : modelData.behind > 0 ? "↓ " + modelData.behind + " behind" : modelData.published ? "Published · clean" : "No known remote copy"
                        color: modelData.warnings.length ? root.urgent : root.muted
                      }
                      Label {
                        visible: !!(modelData.terminals.length > 0)
                        width: parent.width
                        text: modelData.terminals.length + " terminals" + (modelData.working ? " · working" : "") + (modelData.waiting ? " · waiting" : "")
                        color: modelData.waiting ? root.urgent : root.accent
                      }
                      Label {
                        visible: !!(modelData.claim !== null)
                        width: parent.width
                        text: modelData.claim ? modelData.claim.agent + " · " + modelData.claim.state + (modelData.claim.stale ? " · stale" : "") : ""
                        color: root.muted
                      }
                    }
                  }
                }
              }
            }
            Rectangle {
              width: parent.width * 0.46 - root.gap * 2
              height: parent.height
              color: "transparent"
              border.width: 1
              border.color: root.subtle
              Flickable {
                anchors.fill: parent
                anchors.margins: Style.space(12)
                clip: true
                contentWidth: width
                contentHeight: detailCol.implicitHeight
                Column {
                  id: detailCol
                  width: parent.width
                  spacing: Style.space(10)
                  Heading {
                    text: root.showLoose ? "TERMINALS OUTSIDE REPOS" : root.worktree ? (root.worktree.branch || "Detached worktree") : "WORKTREE DETAILS"
                  }
                  Paragraph {
                    visible: !!(!root.showLoose)
                    text: root.worktree ? root.worktree.path : "Choose a project to begin."
                    color: root.muted
                  }
                  Flow {
                    visible: !!(!root.showLoose && root.worktree !== null)
                    width: parent.width
                    spacing: Style.space(6)
                    Button {
                      label: "Terminal"
                      onClicked: root.openTerminal()
                    }
                    Button {
                      label: "Start " + (root.agentCommand || "agent")
                      enabled: !!(!!root.agentCommand)
                      onClicked: root.launchAgent()
                    }
                    Button {
                      label: "Editor"
                      enabled: !!(root.inventory.capabilities && root.inventory.capabilities["omarchy-launch-editor"] === true)
                      onClicked: root.editor()
                    }
                    Button {
                      label: "Git"
                      enabled: !!(root.inventory.capabilities && root.inventory.capabilities.lazygit === true)
                      onClicked: root.gitView()
                    }
                    Button {
                      label: "Folder"
                      onClicked: root.folder()
                    }
                    Button {
                      label: "Copy path"
                      enabled: !!(root.inventory.capabilities && root.inventory.capabilities["wl-copy"] === true)
                      onClicked: root.copyPath()
                    }
                  }
                  Flow {
                    visible: !!(!root.showLoose)
                    width: parent.width
                    spacing: Style.space(6)
                    Repeater {
                      model: ["overview", "changes", "history"]
                      delegate: Button {
                        required property var modelData
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        chosen: root.detailTab === modelData
                        onClicked: root.detailTab = modelData
                      }
                    }
                  }
                  Paragraph {
                    visible: !!(detailProc.running && !root.showLoose)
                    text: "Loading details…"
                    color: root.muted
                  }
                  Paragraph {
                    visible: !!(root.detailError !== "" && !root.showLoose)
                    text: root.detailError
                    color: root.urgent
                  }
                  Column {
                    visible: !!(root.showLoose || root.detailTab === "overview")
                    width: parent.width
                    spacing: Style.space(10)
                    Paragraph {
                      visible: !!(!root.showLoose && root.repo && root.repo.warnings.length > 0)
                      text: root.repo ? root.repo.warnings.join("\n") : ""
                      color: root.urgent
                    }
                    Paragraph {
                      visible: !!(!root.showLoose && root.worktree && root.worktree.warnings.length > 0)
                      text: root.worktree ? root.worktree.warnings.join(" · ") : ""
                      color: root.urgent
                    }
                    Heading {
                      text: "Terminals"
                    }
                    Repeater {
                      model: root.showLoose ? root.state.unplaced : (root.worktree ? root.worktree.terminals : [])
                      delegate: Column {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(4)
                        Paragraph {
                          text: (modelData.agent === "working" ? "◐ " : modelData.agent === "idle" ? "✳ " : "▣ ") + String(modelData.title).replace(/^[◐◑◒◓✳⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]\s*/, "")
                          color: modelData.agent === "idle" ? root.urgent : root.text
                        }
                        Label {
                          width: parent.width
                          text: "Workspace " + modelData.workspace + " · " + modelData.pty
                          color: root.muted
                        }
                        Row {
                          spacing: Style.space(6)
                          Button {
                            label: "Focus"
                            onClicked: root.focusTerminal(modelData)
                          }
                          Button {
                            label: "Style in Ombre"
                            enabled: !!(root.inventory.capabilities && root.inventory.capabilities.ombre)
                            onClicked: root.ombreTerminal(modelData)
                          }
                        }
                      }
                    }
                    Paragraph {
                      visible: !!(!root.showLoose && root.worktree && root.worktree.terminals.length === 0)
                      text: "No terminal is currently in this worktree."
                      color: root.muted
                    }
                    Column {
                      visible: !!(!root.showLoose)
                      width: parent.width
                      spacing: Style.space(8)
                      Heading {
                        visible: !!(root.worktree && root.worktree.claim !== null)
                        text: "Work claim"
                      }
                      Paragraph {
                        text: root.worktree && root.worktree.claim ? root.worktree.claim.agent + " · " + root.worktree.claim.state + "\n" + root.worktree.claim.task : ""
                      }
                      Heading {
                        visible: !!(root.repo && root.repo.remoteClaims.length > 0)
                        text: "On other machines"
                      }
                      Repeater {
                        model: root.repo ? root.repo.remoteClaims : []
                        delegate: Paragraph {
                          required property var modelData
                          text: modelData.device + " · " + modelData.agent + "\n" + modelData.task
                          color: root.muted
                        }
                      }
                      Heading {
                        visible: !!(root.details.path === (root.worktree ? root.worktree.path : "") && root.details.handoff !== null)
                        text: "Last handoff"
                      }
                      Paragraph {
                        visible: !!(root.details.path === (root.worktree ? root.worktree.path : ""))
                        text: root.details.handoff ? String(root.details.handoff.summary || "").slice(0, 1800) : ""
                      }
                      Paragraph {
                        visible: !!(root.details.path === (root.worktree ? root.worktree.path : ""))
                        text: root.details.handoff && root.details.handoff.next_steps ? "Next: " + String(root.details.handoff.next_steps).slice(0, 1400) : ""
                        color: root.muted
                      }
                      Button {
                        visible: !!(root.worktree && !root.worktree.main)
                        label: root.pendingRemove === (root.worktree ? root.worktree.path : "") ? "Confirm remove" : "Remove clean worktree"
                        danger: true
                        enabled: !!(root.cleanupReason === "" && !actionProc.running)
                        onClicked: root.removeWorktree()
                      }
                      Paragraph {
                        visible: !!(root.worktree && !root.worktree.main && root.cleanupReason !== "")
                        text: "Cleanup unavailable: " + root.cleanupReason
                        color: root.muted
                      }
                    }
                  }
                  Column {
                    visible: !!(!root.showLoose && root.detailTab === "changes" && root.details.path === (root.worktree ? root.worktree.path : ""))
                    width: parent.width
                    spacing: Style.space(7)
                    Paragraph {
                      text: root.details.statusKnown === false ? "Git status unavailable" : root.details.fileCount ? root.details.fileCount + " changed files · open Git to review diffs" : "Working tree is clean."
                      color: root.muted
                    }
                    Repeater {
                      model: root.details.files
                      delegate: Paragraph {
                        required property var modelData
                        text: modelData.status + "  " + (modelData.from ? modelData.from + " → " : "") + modelData.path
                      }
                    }
                    Paragraph {
                      visible: !!(root.details.fileCount > 100)
                      text: "Showing the first 100 files. Open Git for the full list."
                      color: root.muted
                    }
                  }
                  Column {
                    visible: !!(!root.showLoose && root.detailTab === "history" && root.details.path === (root.worktree ? root.worktree.path : ""))
                    width: parent.width
                    spacing: Style.space(10)
                    Paragraph {
                      text: root.worktree && root.worktree.upstream ? "Tracking " + root.worktree.upstream + " · counts reflect your last fetch" : "No tracking branch configured"
                      color: root.muted
                    }
                    Repeater {
                      model: root.details.commits
                      delegate: Paragraph {
                        required property var modelData
                        text: modelData.head + "  " + modelData.subject
                      }
                    }
                  }
                }
              }
            }
          }
          Label {
            id: statusLine
            width: parent.width
            text: root.message || (root.inventory.status === "unavailable" ? "ekkOS unavailable · claims could not be refreshed" : root.inventory.terminalStatus === "unavailable" ? "Hyprland unavailable · terminal inventory is incomplete" : "/ search · Tab panes · Enter terminal · E editor · G Git · F focus · R refresh · ekkOS " + root.inventory.status + (root.inventory.duration !== undefined ? " · " + root.inventory.duration + "s scan" : ""))
            color: root.message ? root.text : root.muted
          }
        }
      }
    }
  }
}
