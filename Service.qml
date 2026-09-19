import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons

// Animated wallpaper.
//
// The wallpaper is painted by *us* (see the PanelWindow below) instead of by
// Omarchy's own background plugin, because that is the only way the image
// itself can move. Omarchy's surface stays underneath as a perfect fallback:
// same crop, same scale, so a disabled plugin or a failed image load looks
// like nothing happened instead of looking broken.
//
// Every animated value is a pure function of one accumulating clock, so the
// repaint rate is ours (frameMs) instead of the compositor's, and there is
// exactly one timer in the plugin.
//
// The window is deliberately inline rather than a separate file component:
// Quickshell's Variants delegate model only initialises the model roles
// (modelData) for delegates it can see, so a separate component silently gets
// an undefined screen and never maps. Omarchy's own background plugin is
// written the same way for the same reason.
Item {
  id: root

  // Injected by the shell host.
  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  // ------------------------------------------------------------ taste dial
  // 0.02 = the "2%" setting: the image zooms 1.000 -> 1.020, wanders +-8 px,
  // and the exposure darkens by up to 2%. Raise to 0.05 for unmistakable,
  // drop to 0.01 to have to hunt for it.
  readonly property real motion: 0.02
  readonly property int frameMs: 70            // repaint interval (~14 fps)
  readonly property int scalePeriodMs: 90000   // one in-and-out zoom
  readonly property int panPeriodMs: 140000    // one pan orbit
  readonly property int exposurePeriodMs: 25000
  readonly property int bloomPeriodMs: 11000
  readonly property real bloomIntensity: 0.10
  readonly property int moteCount: 18
  readonly property real moteAlpha: 0.05
  readonly property int revealMs: 420          // Omarchy's own reveal duration

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string currentLink: stateDir + "/background"
  readonly property color accent: Color.accent !== undefined ? Color.accent : "#ffffff"

  // ---------------------------------------------------------------- values
  function wave(periodMs) {
    return 0.5 - 0.5 * Math.cos(2 * Math.PI * (root.clock % periodMs) / periodMs)
  }

  readonly property real zoom: 1 + motion * root.wave(scalePeriodMs)
  readonly property real panX: 400 * motion * (2 * root.wave(panPeriodMs) - 1)
  readonly property real panY: 300 * motion * (2 * root.wave(panPeriodMs * 0.7) - 1)
  readonly property real exposure: motion * root.wave(exposurePeriodMs)
  readonly property real bloom: bloomIntensity * root.wave(bloomPeriodMs)

  property real clock: 0
  Timer {
    interval: root.frameMs
    running: true
    repeat: true
    onTriggered: root.clock += root.frameMs
  }

  // ------------------------------------------------------- wallpaper state
  property string displayPath: ""     // what is on screen right now
  property string incomingPath: ""    // what the reveal is wiping in
  property real revealProgress: 1

  function refresh() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function startReveal() {
    if (root.incomingPath === "" || root.revealProgress >= 1) return
    if (revealAnimation.running) return
    revealAnimation.restart()
  }

  function finishReveal() {
    revealFallback.stop()
    if (root.incomingPath === "") return
    root.displayPath = root.incomingPath
    root.incomingPath = ""
    root.revealProgress = 1
  }

  function imageUrl(path) {
    return path ? Util.fileUrl(path) : ""
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (!path || path === root.displayPath || path === root.incomingPath) return
        if (root.displayPath === "" || root.revealProgress < 1) {
          // First load, or the wallpaper changed again mid-reveal: cut straight
          // to it instead of queueing transitions.
          root.displayPath = path
          root.incomingPath = ""
          root.revealProgress = 1
          return
        }
        root.incomingPath = path
        root.revealProgress = 0
        // The reveal itself waits until the incoming image is Ready
        // (startReveal), so we never wipe in an empty frame. This timer is the
        // belt and braces: a corrupt image must not leave a stale wallpaper on
        // screen for ever.
        revealFallback.restart()
      }
    }
  }

  Timer {
    id: revealFallback
    interval: 4000
    repeat: false
    onTriggered: {
      if (root.incomingPath === "") return
      console.warn("[animated-wallpaper] incoming image never became ready; swapping anyway")
      root.finishReveal()
    }
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: root.revealMs
    easing.type: Easing.InOutCubic
    onFinished: root.finishReveal()
  }

  // Instant reaction to a wallpaper/theme change: the symlink is replaced
  // inside the state dir, so watching the directory catches it immediately.
  // The 5 s readlink poll is only a net if the watcher ever dies.
  Process {
    id: watcher
    command: ["inotifywait", "-m", "-q", "-e", "create,moved_to,close_write,delete", root.stateDir]
    stdout: SplitParser { onRead: function(line) { root.refresh() } }
    onExited: console.warn("[animated-wallpaper] inotifywait exited; relying on the 5 s poll")
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    refresh()
    watcher.running = true
    console.log("[animated-wallpaper] ready: screens=" + Quickshell.screens.length
      + " motion=" + root.motion + " accent=" + root.accent)
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      // Visual only: an empty input region, so the surface never eats a click
      // (desktop double-click still opens Omarchy's background switcher).
      mask: Region { }
      // Never reserve space or push windows around.
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "gsus-animated-wallpaper"
      // The stock wallpaper is on the *background* layer; the inter-layer order
      // (background < bottom < top < overlay) puts this above the wallpaper and
      // below every window and the bar.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // ------------------------------------------------------- wallpaper
      // Pan first, zoom second: two nested items instead of a transform list,
      // so the pan stays linear while the zoom scales around the centre. The
      // surface clips whatever leaves the screen, which is what makes a zoom
      // read as a zoom.
      Item {
        id: panLayer
        x: root.panX
        y: root.panY
        width: win.width
        height: win.height

        Item {
          id: zoomLayer
          anchors.fill: parent
          scale: root.zoom
          transformOrigin: Item.Center

          Image {
            id: baseImage
            anchors.fill: parent
            source: root.imageUrl(root.displayPath)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            // Never paint an empty frame: while our copy is not ready,
            // Omarchy's own wallpaper underneath shows through.
            opacity: status === Image.Ready ? 1 : 0
          }

          Item {
            id: incomingLayer
            anchors.fill: parent
            visible: root.incomingPath !== "" && root.revealProgress < 1
                     && incomingImage.status === Image.Ready
            layer.enabled: visible
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: revealMask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 0.02
            }

            Image {
              id: incomingImage
              anchors.fill: parent
              source: root.imageUrl(root.incomingPath)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              smooth: true
              mipmap: true
              onStatusChanged: if (status === Image.Ready) root.startReveal()
            }
          }

          // The same slanted reveal Omarchy's stock background uses (slant
          // -0.18), so a theme switch still arrives looking the way it always
          // did -- it just also breathes now.
          Item {
            id: revealMask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            readonly property real slant: -0.18
            readonly property real centerTop: width / 2 - slant * height / 2
            readonly property real centerBottom: width / 2 + slant * height / 2
            readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
            readonly property real spread: reach * root.revealProgress

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "white"
                strokeColor: "transparent"
                startX: revealMask.centerTop - revealMask.spread; startY: 0
                PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
                PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
                PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
                PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
              }
            }
          }
        }
      }

      // --------------------------------------------------- ambient light
      // Bloom: a soft accent-tinted haze that breathes. Deliberately steady --
      // with the wallpaper itself drifting, a moving haze on top would be one
      // moving thing too many.
      Item {
        id: bloom
        width: win.width * 1.3
        height: width
        anchors.centerIn: parent
        opacity: root.bloom

        Image {
          id: bloomTexture
          anchors.fill: parent
          source: Qt.resolvedUrl("glow.png")
          fillMode: Image.PreserveAspectFit
          visible: false
        }

        MultiEffect {
          source: bloomTexture
          anchors.fill: bloomTexture
          colorization: 1.0
          colorizationColor: root.accent
        }
      }

      // Motes: dust in the light. Positions come from the same clock -- no
      // particle system, because Qt's particle system drives its own frame
      // ticker and would cost several times the repaints.
      Repeater {
        model: root.moteCount

        Item {
          id: mote
          required property int index

          readonly property real seed: (index * 0.6180339887) % 1
          readonly property real period: 55000 + seed * 45000
          readonly property real t: ((root.clock + seed * 90000) % period) / period
          readonly property real size: (70 + seed * 150) * (win.width / 1920)

          width: size
          height: size
          x: seed * win.width + win.width * 0.04 * Math.sin(2 * Math.PI * (t + seed)) - size / 2
          y: win.height * (1.08 - 1.16 * t)
          opacity: root.moteAlpha * Math.sin(Math.PI * t)

          Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("glow.png")
            fillMode: Image.PreserveAspectFit
          }
        }
      }

      // Exposure: the whole picture darkens by up to `motion` and comes back,
      // like the light in the room changing. Topmost, so it grades everything.
      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.exposure
      }
    }
  }
}
