import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "FlowBarModel.js" as Model

// Socket-driven native capsule. The recording renderer stays in Wispr.
Item {
  id: root

  property var state: Model.initial()
  property var strings: ({})
  property var clients: []
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string sockDir: runtimeDir + "/wispr-flow"
  readonly property string sockPath: Quickshell.env("WISPR_FLOWBAR_SOCKET") || sockDir + "/flowbar.sock"
  readonly property bool reducedMotion: Quickshell.env("WISPR_FLOWBAR_REDUCED_MOTION") === "1"
  readonly property bool translucent: Quickshell.env("WISPR_FLOWBAR_MATERIAL") === "frosted"
  readonly property bool shown: Model.visible(state)
  readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
  // Notification/action counts used by the integration test.
  property int notified: 0
  property string lastNotificationAction: ""
  property bool pointerInCapsule: false

  function apply(line) {
    try {
      var msg = JSON.parse(line)
      state = Model.reduce(state, msg, strings)
      if (msg.t === "hello" && state.resourcesPath !== "") {
        stringsFile.path = state.resourcesPath + "/flowbar-strings.en.json"
        stringsFile.reload()
      }
      if (msg.t === "notification:show" && state.notification) { notified += 1; if (!pointerInCapsule) expiry.restart() }
      if (msg.t === "notification:clear") expiry.stop()
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

  function dismiss() {
    state = Model.reduce(state, {t: "notification:clear"})
    expiry.stop()
  }

  Timer {
    id: expiry
    interval: root.state.notification ? root.state.notification.timeout : 6000
    onTriggered: root.dismiss()
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
          if (root.clients.length === 0) { root.state = Model.initial(); expiry.stop() }
        }
      }
    }
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
      visible: (root.shown || capsule.opacity > 0) && modelData.name === root.focusedName
      anchors { bottom: true; left: true; right: true }
      implicitHeight: Math.ceil(capsule.height) + 48
      color: "transparent"
      WlrLayershell.namespace: "wispr-flowbar"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Only the pill takes input; the rest of the surface is click-through
      // so the desktop below stays usable.
      mask: Region { item: capsule }

      GlassCapsule {
        id: capsule
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        availableWidth: panel.width - 32
        availableHeight: panel.screen.height - 80
        mode: root.state.mode
        level: root.state.level
        notification: root.state.notification
        active: panel.visible
        reducedMotion: root.reducedMotion
        translucent: root.translucent
        onCancel: root.send("status:cancelClicked")
        onStop: root.send("status:stopClicked")
        onDismiss: root.dismiss()
        onHoveredChanged: {
          root.pointerInCapsule = hovered
          if (hovered) expiry.stop()
          else if (root.state.notification) expiry.restart()
        }
        onAction: (notification, action) => {
          root.lastNotificationAction = action.callback
          root.send("notification:callback", Model.callbackPayload(notification, action))
          root.dismiss()
        }
      }
    }
  }
}
