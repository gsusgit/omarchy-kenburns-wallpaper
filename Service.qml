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
  // `motion` is the zoom/pan dial: the image breathes 1.000 <-> 1.070 every
  // 34 s, which moves the image edge at up to ~4 px/s -- the point where you
  // can see it moving when you look at it, without it reading as a screensaver.
  //  0.03 barely alive | 0.07 shipped | 0.12 obvious
  // Speed matters more than size: 2% over 90 s is 0.7 px/s and no eye catches
  // that, which is why this used to be invisible.
  readonly property real motion: 0.07
  readonly property int frameMs: 70            // repaint interval (~14 fps)
  readonly property int scalePeriodMs: 34000   // one in-and-out zoom
  readonly property int panPeriodMs: 47000     // one pan orbit
  readonly property real panAmount: 0.65       // fraction of the zoom slack the pan uses
  readonly property real exposureDepth: 0.025  // room-light breath
  readonly property int exposurePeriodMs: 22000
  readonly property int revealMs: 420          // Omarchy's own reveal duration

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string currentLink: stateDir + "/background"

  // ---------------------------------------------------------------- values
  function wave(periodMs) {
    return 0.5 - 0.5 * Math.cos(2 * Math.PI * (root.clock % periodMs) / periodMs)
  }

  function orbit(periodMs, phase) {
    return Math.sin(2 * Math.PI * ((root.clock % periodMs) / periodMs) + (phase || 0))
  }

  readonly property real zoom: 1 + motion * root.wave(scalePeriodMs)

  // The pan is a fraction of the slack the zoom creates, so the image always
  // covers the screen: no pan at all while the zoom is at its minimum, which
  // is what keeps a black edge from ever showing up.
  readonly property real panUnitX: panAmount * root.orbit(panPeriodMs, 0)
  readonly property real panUnitY: panAmount * root.orbit(panPeriodMs * 0.8, 1.6)

  readonly property real exposure: exposureDepth * root.wave(exposurePeriodMs)

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
    console.log("[animated-wallpaper] ready v0.5: screens=" + Quickshell.screens.length
      + " motion=" + root.motion + " scalePeriodMs=" + root.scalePeriodMs)
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
        x: root.panUnitX * (root.zoom - 1) / 2 * win.width
        y: root.panUnitY * (root.zoom - 1) / 2 * win.height
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

      // Nothing is painted on top of the wallpaper any more: the v0.1 accent
      // bloom, the v0.3 glint band and the motes are all gone. The image is
      // the entire effect -- it moves, and that is all.

      // Exposure: the whole picture darkens a little and comes back, like the
      // light in the room changing. Topmost, so it grades everything.
      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.exposure
      }
    }
  }
}
