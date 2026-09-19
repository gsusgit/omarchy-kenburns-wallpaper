import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "Settings.js" as Settings

// Animated wallpaper.
//
// The wallpaper is painted by *us* (see the PanelWindow below) instead of by
// Omarchy's own background plugin, because that is the only way the image
// itself can move. Omarchy's surface stays underneath as a perfect fallback:
// same crop, same scale, so a disabled plugin or a failed image load looks
// like nothing happened instead of looking broken.
//
// The move is a Ken Burns segment: a cycle is one traverse (`duration`) plus a
// dwell (`pauseAtEnd`), and a pair is two cycles, out and back, so a pair always
// ends on the pose it started from and a fixed mode can never jump.
//
// Every animated value is a pure function of one accumulating clock, so the
// repaint rate is ours (frameMs) instead of the compositor's, and there is
// exactly one per-frame timer in the plugin. Nothing here allocates per frame.
Item {
  id: root

  // Injected by the shell host.
  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  // ---------------------------------------------------------- internal dials
  // Deliberately not user-configurable: the frame budget, the room-light breath
  // (unrelated to the Ken Burns move) and Omarchy's own reveal timing.
  readonly property int frameMs: 70            // repaint interval (~14 fps)
  readonly property real exposureDepth: 0.025
  readonly property int exposurePeriodMs: 22000
  readonly property int revealMs: 420
  readonly property real panSplit: 0.5         // pan extent as a fraction of the zoom slack
  readonly property real blendSec: 2.0         // pose cross-fade when a random pair changes variant
  readonly property int traceMs: 150           // pose trace interval (tests read it)
  readonly property int traceWindowMs: 60000   // trace is bounded: no line-per-second forever

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "gsus.animated-wallpaper"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId
  // NOT inside pluginDir: the shell watches a plugin's whole directory for
  // changes and reloads it, so a settings file written there reloads the plugin
  // on every save (4 reloads per write, measured) -- which unmaps and remaps the
  // bar panel mid-interaction. Omarchy's own stateful plugins keep their config
  // outside too (omarchy-lock-style -> ~/.config/omarchy/lock-style.json).
  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/animated-wallpaper.json"

  // ------------------------------------------------------- user configuration
  // The settings file is the single source of truth; Settings.js clamps
  // everything, so `config` is always complete and in range whatever is on disk.
  property var config: Settings.sanitize({})
  property bool enabled: true                  // mirrors config.enabled

  function applyConfig(rawText) {
    var parsed = Settings.parse(rawText)
    root.config = parsed
    root.enabled = parsed.enabled
    console.log("[animated-wallpaper] config: " + JSON.stringify(parsed))
    root.startTrace()
  }

  // The one place the settings file is written. The menu edits the values and calls
  // save() when a control is done being dragged; the IPC handler below calls it
  // too, which is what makes persistence testable without a mouse.
  function save() {
    settingsWriter.setText(Settings.serialise(root.config) + "\n")
  }

  function set(key, value) {
    var next = {}
    for (var k in root.config) next[k] = root.config[k]
    next[key] = value
    root.config = Settings.sanitize(next)
  }

  FileView {
    id: settingsWriter
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  // Scriptable surface. Handy from a terminal, and it is how the persistence
  // assertions in tests/persist.test.sh drive a real write + reload round trip.
  //
  // One function per key rather than a generic set(key, value): the CLI reads
  // better (`qs ipc call animated-wallpaper setDuration 45`) and a typo in the
  // key cannot reach the config. Note when linting: use /usr/lib/qt6/bin/qmllint
  // -- the /usr/bin/qmllint on this box is Qt5's (5.15) and crashes silently
  // (exit 255, no message) on Quickshell's Qt6 types.
  function applyIpc(key, value) {
    var v = value
    if (value === "true") v = true
    else if (value === "false") v = false
    else if (value !== "" && !isNaN(Number(value))) v = Number(value)
    root.set(key, v)
    root.save()
    console.log("[animated-wallpaper] ipc " + key + "=" + v)
  }

  IpcHandler {
    target: "animated-wallpaper"

    function setEnabled(value: string): void { root.applyIpc("enabled", value) }
    function setDuration(value: string): void { root.applyIpc("duration", value) }
    function setMaxZoom(value: string): void { root.applyIpc("maxZoom", value) }
    function setMode(value: string): void { root.applyIpc("mode", value) }
    function setSmoothEasing(value: string): void { root.applyIpc("smoothEasing", value) }
    function setPauseAtEnd(value: string): void { root.applyIpc("pauseAtEnd", value) }

    function reset(): void {
      root.config = Settings.sanitize({})
      root.save()
      console.log("[animated-wallpaper] ipc reset")
    }

    function status(): string {
      return JSON.stringify(root.config)
    }
  }

  // A config change restarts the cycle, so the new values apply from a pose you
  // can predict instead of mid-segment.
  onConfigChanged: {
    root.clock = 0
    root.lastTickMs = 0
  }

  FileView {
    id: configFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: function(error) {
      // First run (no file yet) and unreadable files land here. Fall back to the
      // defaults AND write them out, so the file exists for the next boot and a
      // hand-edited file can always be inspected to see the canonical shape.
      console.warn("[animated-wallpaper] " + root.settingsPath + " unreadable, using defaults: " + error)
      root.applyConfig("")
      root.save()
    }
    onFileChanged: reload()
  }

  // A bounded trace of the pose. It prints the very properties the window
  // consumes, which is what tests/pose.test.sh asserts against -- the screen
  // belongs to the user, so a test that needs it to be idle would be flaky.
  property bool tracing: false

  function startTrace() {
    root.tracing = true
    traceOff.restart()
  }

  Timer {
    id: traceOff
    interval: root.traceWindowMs
    repeat: false
    onTriggered: root.tracing = false
  }

  Timer {
    interval: root.traceMs
    running: root.tracing
    repeat: true
    onTriggered: console.log("[animated-wallpaper] pose " + JSON.stringify({
      t: Math.round(root.clock),
      cy: root.cycleIndex,
      pair: root.pairIndex,
      var: root.variant,
      seg: Number(root.segment.toFixed(4)),
      e: Number(root.eased.toFixed(4)),
      z: Number(root.zoom.toFixed(6)),
      x: Number(root.panX.toFixed(6)),
      y: Number(root.panY.toFixed(6))
    }))
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string currentLink: stateDir + "/background"

  // ------------------------------------------------------------- Ken Burns pose
  readonly property real cycleSec: Math.max(1, config.duration + config.pauseAtEnd)
  readonly property real cycleMs: cycleSec * 1000
  readonly property real pairMs: cycleMs * 2
  readonly property int cycleIndex: Math.floor(clock / cycleMs)
  readonly property int pairIndex: Math.floor(clock / pairMs)
  readonly property bool forwardCycle: (cycleIndex % 2) === 0
  readonly property real inCycleSec: (clock % cycleMs) / 1000
  readonly property real inPairSec: (clock % pairMs) / 1000
  readonly property real segment: Math.max(0, Math.min(1, inCycleSec / Math.max(0.5, config.duration)))
  readonly property real eased: config.smoothEasing
    ? 0.5 - 0.5 * Math.cos(Math.PI * segment)
    : segment

  readonly property string variant: Settings.variantForPair(pairIndex, config.mode)
  readonly property string previousVariant: Settings.variantForPair(Math.max(0, pairIndex - 1), config.mode)
  // Cross-fade the pose when a random pair changes variant, so the switch is
  // never a jump. Zero whenever the variant is unchanged (every fixed mode).
  readonly property real blend: variant !== previousVariant
    ? Math.max(0, 1 - inPairSec / blendSec)
    : 0

  function mix(a, b, t) { return a + (b - a) * t }
  function startZoom(v) { return v === "zoomOut" || v === "horizontal" || v === "vertical" ? config.maxZoom : 1 }
  function endZoom(v) { return v === "zoomOut" ? 1 : config.maxZoom }
  function startX(v) { return v === "horizontal" ? -panSplit : 0 }
  function endX(v) { return v === "horizontal" ? panSplit : 0 }
  function startY(v) { return v === "vertical" ? -panSplit : 0 }
  function endY(v) { return v === "vertical" ? panSplit : 0 }

  function variantZoom(v) { return mix(startZoom(v), endZoom(v), forwardCycle ? eased : 1 - eased) }
  function variantX(v) { return mix(startX(v), endX(v), forwardCycle ? eased : 1 - eased) }
  function variantY(v) { return mix(startY(v), endY(v), forwardCycle ? eased : 1 - eased) }

  // `blend` weighs how much of the *previous* pair's start pose is still in
  // play, so it is the second argument: at 0 the running pose wins, at 1 the
  // hand-off pose does. Getting this order wrong freezes the pose at the start
  // of every cycle (the fixed modes never blend), which is exactly how it broke
  // the first time -- the pose trace caught it, not the eye.
  readonly property real zoom: mix(variantZoom(variant), startZoom(previousVariant), blend)
  readonly property real panX: mix(variantX(variant), startX(previousVariant), blend)
  readonly property real panY: mix(variantY(variant), startY(previousVariant), blend)

  function wave(periodMs) {
    return 0.5 - 0.5 * Math.cos(2 * Math.PI * (root.clock % periodMs) / periodMs)
  }

  readonly property real exposure: exposureDepth * root.wave(exposurePeriodMs)

  property real clock: 0
  property real lastTickMs: 0

  onEnabledChanged: root.lastTickMs = 0

  Timer {
    interval: root.frameMs
    running: root.enabled
    repeat: true
    // Real elapsed time, not a tick count: a Timer that slips when the shell is
    // busy must not stretch `duration: 20` into 30 real seconds. lastTickMs is
    // discarded on pause and on a config change so the first tick after either
    // cannot add a huge delta.
    onTriggered: {
      var now = Date.now()
      if (root.lastTickMs > 0) root.clock += (now - root.lastTickMs)
      root.lastTickMs = now
    }
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
    root.clock = 0          // a new image starts a fresh Ken Burns move
    root.lastTickMs = 0
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
    console.log("[animated-wallpaper] ready v0.8: screens=" + Quickshell.screens.length
      + " config=" + JSON.stringify(root.config))
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
      // read as a zoom. Pan is a fraction of the slack the zoom creates, so the
      // image always covers the screen and no black edge can ever show up.
      Item {
        id: panLayer
        x: root.panX * (root.zoom - 1) / 2 * win.width
        y: root.panY * (root.zoom - 1) / 2 * win.height
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
