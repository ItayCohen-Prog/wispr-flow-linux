import QtQuick
import Quickshell
import Quickshell.Wayland

// A snapshot of the desktop under the layer plus a frosted copy blurred once.
//
// A layer surface cannot see through itself: a live capture includes the
// capsule from the previous frame, and Hyprland's no_screen_share rule
// paints the layer as a black box in every capture. So the glass refracts
// the frame from right before it appeared. Setting `active` creates the
// capture session and requests one frame; clearing it ends the session so
// the compositor can go back to direct scanout. The compositor only copies
// a frame when it commits one, so the caller maps its (still transparent)
// layer right after activating.
Item {
  id: backdrop
  property var captureScreen: null
  property bool active: false
  // Position of this item's top-left corner on captureScreen, logical px.
  property real originX: 0
  property real originY: 0
  property real dpr: 1
  readonly property bool ready: view.hasContent
  readonly property alias sharp: sharpSource
  readonly property alias frosted: frostSource
  // Mean luminance under the capsule, 0..1, from the frosted copy. -1 until known.
  property real luminance: -1
  signal captured()

  readonly property size texels: Qt.size(Math.max(1, Math.round(width * dpr)), Math.max(1, Math.round(height * dpr)))
  readonly property size halfTexels: Qt.size(Math.max(1, Math.round(width * dpr / 2)), Math.max(1, Math.round(height * dpr / 2)))

  Item {
    id: pipeline
    // Texture providers only update while visible. Park them far outside
    // the window; hideSource keeps the capture out of the main pass.
    x: -40000
    width: backdrop.width; height: backdrop.height

    ScreencopyView {
      id: view
      captureSource: backdrop.active ? backdrop.captureScreen : null
      live: false
      paintCursor: false
      width: backdrop.captureScreen ? backdrop.captureScreen.width : 1
      height: backdrop.captureScreen ? backdrop.captureScreen.height : 1
      onHasContentChanged: {
        if (!hasContent) { backdrop.luminance = -1; return }
        probe.scheduleUpdate()
        probe.grabToImage(function (result) { grabImage.grab = result })
      }
    }
    ShaderEffectSource {
      id: sharpSource
      sourceItem: view
      hideSource: true
      sourceRect: Qt.rect(backdrop.originX, backdrop.originY, backdrop.width, backdrop.height)
      textureSize: backdrop.texels
      width: backdrop.width; height: backdrop.height
      smooth: true
    }
    ShaderEffectSource {
      id: halfSource
      sourceItem: view
      hideSource: true
      sourceRect: sharpSource.sourceRect
      textureSize: backdrop.halfTexels
      width: backdrop.width / 2; height: backdrop.height / 2
      smooth: true
    }
    // Four single-texel Gaussian passes at half resolution: a smooth
    // sigma of about 7 logical px without striding over texels.
    ShaderEffect {
      id: blurH1
      width: halfSource.width; height: halfSource.height
      property var source: halfSource
      property vector2d texelStep: Qt.vector2d(1 / backdrop.halfTexels.width, 0)
      fragmentShader: "shaders/blur.frag.qsb"
      layer.enabled: true; layer.textureSize: backdrop.halfTexels; layer.smooth: true
    }
    ShaderEffect {
      id: blurV1
      width: halfSource.width; height: halfSource.height
      property var source: blurH1
      property vector2d texelStep: Qt.vector2d(0, 1 / backdrop.halfTexels.height)
      fragmentShader: "shaders/blur.frag.qsb"
      layer.enabled: true; layer.textureSize: backdrop.halfTexels; layer.smooth: true
    }
    ShaderEffect {
      id: blurH2
      width: halfSource.width; height: halfSource.height
      property var source: blurV1
      property vector2d texelStep: Qt.vector2d(1 / backdrop.halfTexels.width, 0)
      fragmentShader: "shaders/blur.frag.qsb"
      layer.enabled: true; layer.textureSize: backdrop.halfTexels; layer.smooth: true
    }
    ShaderEffect {
      id: blurV
      width: halfSource.width; height: halfSource.height
      property var source: blurH2
      property vector2d texelStep: Qt.vector2d(0, 1 / backdrop.halfTexels.height)
      fragmentShader: "shaders/blur.frag.qsb"
    }
    ShaderEffectSource {
      id: frostSource
      sourceItem: blurV
      hideSource: true
      textureSize: backdrop.halfTexels
      width: blurV.width; height: blurV.height
      smooth: true
    }
    // 8x8 downsample for the adaptive light/dark decision. QImage is opaque
    // to QML, so the grab goes through an Image into a Canvas to read pixels.
    ShaderEffectSource {
      id: probe
      sourceItem: blurV
      hideSource: true
      live: false
      textureSize: Qt.size(8, 8)
      mipmap: true
      width: 8; height: 8
      smooth: true
    }
    Image {
      id: grabImage
      width: 8; height: 8
      // The grab result owns the image behind its URL; keep it alive until loaded.
      property var grab: null
      source: grab ? grab.url : ""
      cache: false
      onStatusChanged: if (status === Image.Ready) meter.requestPaint()
    }
    Canvas {
      id: meter
      width: 8; height: 8
      renderStrategy: Canvas.Immediate
      renderTarget: Canvas.Image
      onPaint: {
        if (!grabImage.grab) return
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(grabImage, 0, 0, width, height)
        var d = ctx.getImageData(0, 0, width, height).data, sum = 0, n = 0
        for (var i = 0; i + 3 < d.length; i += 4) {
          sum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255; n++
        }
        backdrop.luminance = n ? sum / n : -1
        grabImage.grab = null
        backdrop.captured()
      }
    }
  }
}
