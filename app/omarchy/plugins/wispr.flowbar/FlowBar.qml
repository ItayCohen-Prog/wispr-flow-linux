import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "FlowBarModel.js" as Model

// Native layer-shell Flow Bar for Wispr Flow.
//
// The patched Wispr Flow main process (linux-native-flowbar.sh) connects to
// the Unix socket served here and mirrors its status-window IPC as JSON lines.
// This item reduces those messages into a small state and draws the pill on
// the focused monitor: cancel (x), a live level meter, and stop (check).
// Notifications go to the desktop notification daemon (notify-send) with the
// app's action buttons; a chosen action is sent back over the socket exactly
// like the renderer's own IPC message, so the app cannot tell the difference.
Item {
  id: root

  property var state: Model.initial()
  property var strings: ({})
  property var clients: []
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string sockDir: runtimeDir + "/wispr-flow"
  readonly property string sockPath: sockDir + "/flowbar.sock"
  readonly property bool shown: Model.visible(state)
  readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  // Animation clock for the level meter / processing pulse.
  property real phase: 0
  // Count of notifications handed to the daemon (test hook).
  property int notified: 0
  property string lastNotificationAction: ""

  function apply(line) {
    try {
      var msg = JSON.parse(line)
      state = Model.reduce(state, msg, strings)
      if (msg.t === "hello" && state.resourcesPath !== "") {
        stringsFile.path = state.resourcesPath + "/flowbar-strings.en.json"
        stringsFile.reload()
      }
      if (msg.t === "notification:show" && state.notification) notify(state.notification)
    } catch (e) {
      console.log("[wispr.flowbar] bad line: " + e)
    }
  }

  function send(t, p) {
    var line = JSON.stringify({ t: t, p: p === undefined ? null : p }) + "\n"
    for (var i = 0; i < clients.length; i++) {
      clients[i].write(line)
      clients[i].flush()
    }
  }

  function iconPath() {
    // AppImage/package layout: <prefix>/usr/lib/wispr-flow/resources ->
    // <prefix>/usr/share/icons/hicolor/256x256/apps/ai.wisprflow.WisprFlow.png
    if (state.resourcesPath === "") return "wispr-flow"
    return state.resourcesPath + "/../../../share/icons/hicolor/256x256/apps/ai.wisprflow.WisprFlow.png"
  }

  // The action a click on the popup should run: the app's primary action,
  // else its first one. Omarchy's daemon renders no named buttons; it only
  // invokes the freedesktop "default" action when the toast is clicked.
  function primaryAction(n) {
    for (var i = 0; i < n.actions.length; i++) {
      if (n.actions[i].style === "primary") return n.actions[i]
    }
    return n.actions.length > 0 ? n.actions[0] : null
  }

  // Hand a notification to the desktop daemon. With a primary action,
  // notify-send waits and prints "default" when the toast is clicked; we relay
  // that as the renderer's notification:callback for the primary action.
  // Each call gets its own Process so overlapping notifications don't clobber
  // each other.
  function notify(n) {
    var args = ["notify-send", "-a", "Wispr Flow", "-i", iconPath(), "-t", String(n.timeout)]
    var primary = primaryAction(n)
    if (primary) {
      args.push("-A")
      args.push("default=" + primary.text)
    }
    args.push("--")
    args.push(n.title !== "" ? n.title : "Wispr Flow")
    if (n.body !== "") args.push(n.body)
    var proc = notifyProcess.createObject(root, { command: args, notification: n })
    proc.running = true
    notified += 1
  }

  Component {
    id: notifyProcess
    Process {
      id: proc
      property var notification: null
      stdout: SplitParser {
        onRead: data => {
          var key = String(data).trim()
          if (key !== "default" || !proc.notification) return
          var a = root.primaryAction(proc.notification)
          if (!a) return
          root.lastNotificationAction = a.callback
          root.send("notification:callback", Model.callbackPayload(proc.notification, a))
        }
      }
      onExited: proc.destroy()
    }
  }

  // English UI strings the build step extracts next to app.asar; the app
  // tells us where over the socket ("hello").
  FileView {
    id: stringsFile
    path: ""
    onLoaded: {
      try { root.strings = JSON.parse(text()) } catch (e) { console.log("[wispr.flowbar] strings: " + e) }
    }
    onLoadFailed: error => console.log("[wispr.flowbar] strings unavailable: " + error)
  }

  // The socket directory may not exist yet (fresh login); create it before
  // binding. Quickshell has no mkdir, so shell out once.
  Process {
    id: mkdir
    command: ["mkdir", "-p", root.sockDir]
    running: true
    onExited: server.active = true
  }

  SocketServer {
    id: server
    path: root.sockPath
    active: false
    handler: Socket {
      id: client
      parser: SplitParser {
        onRead: data => root.apply(data)
      }
      onConnectedChanged: {
        if (connected) {
          root.clients = root.clients.concat([client])
        } else {
          root.clients = root.clients.filter(function (c) { return c !== client })
        }
      }
    }
  }

  Timer {
    interval: 40
    repeat: true
    running: root.shown
    onTriggered: root.phase = (root.phase + 0.18) % (Math.PI * 2)
  }

  // `omarchy-shell wisprflowbar <fn> [args]` for scripted testing.
  IpcHandler {
    target: "wisprflowbar"
    function inject(line: string): string { root.apply(line); return "ok" }
    function press(action: string): string { root.send(action); return "ok" }
    function state(): string { return JSON.stringify(root.state) }
    function socket(): string { return root.sockPath }
    function clients(): string { return String(root.clients.length) }
    function stringsCount(): string { return String(Object.keys(root.strings).length) }
    function notified(): string { return String(root.notified) }
    function lastAction(): string { return root.lastNotificationAction }
  }

  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.shown && modelData.name === root.focusedName
      anchors { bottom: true; left: true; right: true }
      implicitHeight: 90
      color: "transparent"
      WlrLayershell.namespace: "wispr-flowbar"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Only the pill takes input; the rest of the surface is click-through
      // so the desktop below stays usable.
      mask: Region { item: pill }

      readonly property int pillHeight: 40
      readonly property int pillWidth: 132
      readonly property int bottomMargin: 30

      Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.bottomMargin
        width: panel.pillWidth
        height: panel.pillHeight
        radius: height / 2
        color: Qt.rgba(0.1, 0.1, 0.1, 0.96)
        border.width: root.state.mode === "error" ? 2 : 1
        border.color: root.state.mode === "error" ? "#e0554d" : Qt.rgba(1, 1, 1, 0.14)

        // Cancel (left).
        Rectangle {
          id: cancelBtn
          anchors.left: parent.left
          anchors.leftMargin: 5
          anchors.verticalCenter: parent.verticalCenter
          width: 30; height: 30; radius: 15
          color: cancelArea.containsMouse ? "#3a3a3a" : "#2c2c2c"
          Text {
            anchors.centerIn: parent
            text: "✕"
            color: "#f5f4f0"
            font.pixelSize: 13
            font.bold: true
          }
          MouseArea {
            id: cancelArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.send("status:cancelClicked")
          }
        }

        // Level meter / processing pulse (centre).
        Row {
          id: meter
          anchors.centerIn: parent
          spacing: 3
          Repeater {
            model: 9
            delegate: Rectangle {
              required property int index
              readonly property real weight: 1 - Math.abs(index - 4) / 6
              readonly property real listen: 4 + 16 * root.state.level * (0.55 + 0.45 * Math.sin(root.phase * 2 + index * 0.9)) * weight
              readonly property real pulse: 4 + 10 * Math.max(0, Math.sin(root.phase - index * 0.5))
              width: 3
              height: root.state.mode === "listening" ? Math.max(4, listen) : (root.state.mode === "processing" ? pulse : 4)
              radius: 1.5
              anchors.verticalCenter: parent.verticalCenter
              color: root.state.mode === "error" ? "#e0554d" : "#f5f4f0"
              Behavior on height { NumberAnimation { duration: 60 } }
            }
          }
        }

        // Stop / confirm (right).
        Rectangle {
          id: stopBtn
          anchors.right: parent.right
          anchors.rightMargin: 5
          anchors.verticalCenter: parent.verticalCenter
          width: 30; height: 30; radius: 15
          color: stopArea.containsMouse ? "#ffffff" : "#f5f4f0"
          Text {
            anchors.centerIn: parent
            text: "✓"
            color: "#1a1a1a"
            font.pixelSize: 15
            font.bold: true
          }
          MouseArea {
            id: stopArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.send("status:stopClicked")
          }
        }
      }
    }
  }
}
