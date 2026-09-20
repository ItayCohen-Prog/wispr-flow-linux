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
  readonly property bool translucent: Quickshell.env("WISPR_FLOWBAR_MATERIAL") !== "solid"
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
    function version(): string { return "0.4.0" }
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
      readonly property bool focusedHere: modelData.name === root.focusedName
      visible: (root.shown || capsule.visible) && focusedHere
      anchors { bottom: true }
      // 32 px each side for the rim lens, dispersion and shadow.
      implicitWidth: Math.min(panel.screen.width - 32, 356) + 64
      // A layer resize is a Wayland configure/ack transaction. Keep the
      // backing window stable while Qt animates the capsule inside it.
      property int bufferHeight: 106
      implicitHeight: bufferHeight
      function accommodateContent() {
        var needed = Math.ceil(capsule.targetHeight) + 60
        if (!visible || needed > bufferHeight) bufferHeight = needed
      }
      onVisibleChanged: if (!visible) accommodateContent()
      color: "transparent"
      WlrLayershell.namespace: "wispr-flowbar"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Only the pill takes input; the rest of the surface is click-through
      // so the desktop below stays usable.
      mask: Region { item: capsule }

      // The desktop under the layer, captured the instant before the glass
      // forms. The layer maps transparent first so the compositor commits a
      // frame for the capture; the capsule waits for `ready` (or the
      // fallback) before it appears, and the session ends when hidden.
      GlassBackdrop {
        id: backdrop
        width: panel.width; height: panel.height
        captureScreen: panel.screen
        dpr: panel.screen.devicePixelRatio
        active: root.translucent && panel.visible
        originX: Math.floor((panel.screen.width - panel.width) / 2)
        originY: panel.screen.height - panel.height
      }
      Timer {
        id: snapshotFallback
        interval: 150
        running: root.shown && root.translucent && !backdrop.ready
        onTriggered: panel.snapshotTimedOut = true
      }
      property bool snapshotTimedOut: false
      onFocusedHereChanged: snapshotTimedOut = false
      Connections { target: root; function onShownChanged() { if (!root.shown) panel.snapshotTimedOut = false } }

      GlassCapsule {
        id: capsule
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        availableWidth: panel.screen.width - 32
        availableHeight: panel.screen.height - 80
        mode: root.state.mode
        level: root.state.level
        notification: root.state.notification
        active: panel.visible
        reducedMotion: root.reducedMotion
        translucent: root.translucent
        backdrop: backdrop
        materialReady: !root.translucent || backdrop.ready || panel.snapshotTimedOut
        onTargetHeightChanged: panel.accommodateContent()
        Component.onCompleted: panel.accommodateContent()
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
