import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "KenBurnsSettings.js" as Settings

// Ken Burns Wallpaper.
//
// The wallpaper is painted by *us* (see the PanelWindow below) instead of by
// Omarchy's own background plugin, because that is the only way the image
// itself can move. Omarchy's surface stays underneath as a perfect fallback:
// same crop, same scale, so a disabled plugin or a failed image load looks
// like nothing happened instead of looking broken.
//
// The move is a Ken Burns loop, and the zoom is the whole of it: one loop takes
// the zoom out to the far pose and brings it back along a single cosine, so the
// motion never stops and never jumps. There is no zoom-direction control, and
// that is deliberate: with a symmetric loop, "in" and "out" are the same
// oscillation half a period apart, so the switch could only choose the pose you
// start on -- invisible within seconds of a loop that never stops.
//
// Every animated value is a pure function of one accumulating clock, so the
// repaint rate is ours (frameMs) instead of the compositor's, and there is
// exactly one per-frame timer in the plugin. Nothing here allocates per frame.
Item {
  id: root

  // Injected by the shell host.
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------- internal dials
  // Frame budget is not user-configurable. On AC it stays at ~14 fps; on
  // battery it drops to ~8 fps, which is still smooth for a 10–60 s traverse.
  readonly property int frameMs: UPower.onBattery ? 125 : 70
  readonly property int revealMs: 1400
  readonly property int traceMs: 150           // pose trace interval (tests read it)
  readonly property int traceWindowMs: 90000   // trace is bounded: no line-per-second forever
  readonly property string screensaverClass: "org.omarchy.screensaver"

  // NOT inside the plugin directory: the shell watches a plugin's whole folder
  // for changes and reloads it, so a settings file written there reloads the
  // plugin on every save (4 reloads per write, measured) -- which unmaps and
  // remaps the bar panel mid-interaction. Omarchy's own stateful plugins keep
  // their config outside too (omarchy-lock-style -> ~/.config/omarchy/lock-style.json).
  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/kenburnswallpaper.json"

  // ------------------------------------------------------- user configuration
  // The settings file is the single source of truth; Settings.js clamps
  // everything, so `config` is always complete and in range whatever is on disk.
  property var config: Settings.sanitize({})
  property bool enabled: true                  // mirrors config.enabled
  property bool configReady: false
  property real appliedSpeed: -1

  // Wander's live heading lives in memory only. Writing it to the settings
  // file every loop would reload the plugin. `config.drift` is the locked
  // heading the panel persists.
  property string liveDrift: "center"
  property bool liveDriftLocked: false
  property real panX: 0
  property real panY: 0
  property int lastLoopIndex: 0

  function wantsTrace(rawText) {
    if (Quickshell.env("KENBURNS_TRACE") === "1") return true
    return Settings.wantsTrace(rawText)
  }

  function applyConfig(rawText) {
    var parsed = Settings.parse(rawText)
    var same = root.configReady && Settings.serialise(parsed) === Settings.serialise(root.config)
    if (!same) {
      root.config = parsed
      root.configReady = true
    }
    console.log("[kenburnswallpaper] config: " + JSON.stringify(parsed))
    if (root.wantsTrace(rawText)) root.startTrace()
  }

  // Writing goes through a Process, not through FileView.setText.
  //
  // Measured behaviour of the FileView route: once the file has been modified
  // externally, the view stops persisting writes entirely -- a save right after
  // any external edit never lands, whatever the delay (tested up to 4 s), the
  // on-disk file keeps the stale content, and nothing is logged because
  // printErrors is off. That is a silent "I changed a control and it did
  // nothing". A one-shot writer is boring and always works.
  //
  // The JSON travels as an argv entry (Quickshell passes `command` as a real
  // argv, so quotes and braces are safe), and the write is atomic: temp file in
  // the same directory, then rename over the target.
  // The config this write will carry, captured when save() fires. The command reads
  // this plain string instead of binding to root.config: a binding would let the
  // argv change under a write that is already running, so the file could receive a
  // config nobody asked to save at that moment.
  property string pendingWrite: ""

  Process {
    id: settingsWriter
    command: ["sh", "-c",
      'umask 077; tmp="$1.tmp.$$"; trap \'rm -f "$tmp"\' EXIT; printf \'%s\\n\' "$2" > "$tmp" && mv -f "$tmp" "$1"',
      "sh", root.settingsPath, root.pendingWrite]
    onExited: function(code) {
      if (code !== 0)
        console.warn("[kenburnswallpaper] settings write failed, exit " + code)
    }
  }

  function save() {
    root.pendingWrite = Settings.serialise(root.config)
    settingsWriter.running = false      // a newer save supersedes one in flight
    settingsWriter.running = true
  }

  function set(key, value) {
    var next = {}
    for (var k in root.config) next[k] = root.config[k]
    next[key] = value
    root.config = Settings.sanitize(next)
  }

  // Keep in sync with defaults.json (checked in tests/settings.test.sh).
  // Literal assignment + direct JSON write: a stale Settings.js cache cannot
  // turn switches off again when save() would have re-sanitised through it.
  function resetDefaults() {
    var next = {
      enabled: true,
      speed: 48,
      maxZoom: 1.2,
      drift: "center",
      wander: true,
      advance: true,
      trail: true,
      trailLag: 0.03
    }
    root.liveDrift = next.drift
    root.liveDriftLocked = false
    root.snapPanToLive()
    root.config = next
    root.pendingWrite = JSON.stringify(next, null, 2) + "\n"
    settingsWriter.running = false
    settingsWriter.running = true
  }

  function snapPanToLive() {
    var v = Settings.driftVector(root.liveDrift)
    root.panX = v[0] * root.driftLength
    root.panY = v[1] * root.driftLength
  }

  onLiveDriftChanged: root.snapPanToLive()

  // Keep the pose when SPEED changes: the same fraction of the loop, on the
  // new period, so dragging the slider does not snap back to zoom 1.
  function reparameterizeSpeed(newSpeed) {
    var speed = Number(newSpeed)
    if (!isFinite(speed)) speed = Settings.DEFAULTS.speed
    if (root.appliedSpeed < 0) {
      root.appliedSpeed = speed
      return
    }
    if (speed === root.appliedSpeed) return
    var oldCycle = Math.max(1000, root.appliedSpeed * 1000)
    var seg = Math.max(0, Math.min(1, (root.clock % oldCycle) / oldCycle))
    var loop = Math.floor(root.clock / oldCycle)
    root.appliedSpeed = speed
    var newCycle = Math.max(1000, speed * 1000)
    root.clock = loop * newCycle + seg * newCycle
    root.lastLoopIndex = loop
  }

  // Scriptable surface. Handy from a terminal, and it is how the persistence
  // assertions in tests/persist.test.sh drive a real write + reload round trip.
  //
  // One function per key rather than a generic set(key, value): the CLI reads
  // better (`qs ipc call kenburnswallpaper setSpeed 50`) and a typo in the
  // key cannot reach the config. Note when linting: use /usr/lib/qt6/bin/qmllint
  // -- the /usr/bin/qmllint on this box is Qt5's (5.15) and crashes silently
  // (exit 255, no message) on Quickshell's Qt6 types. Run it as
  // `/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell Service.qml Menu.qml`:
  // it exits 0 and prints ~100 warnings, almost all of them from `qs.Ui` /
  // `qs.Commons` failing to resolve outside the running shell (plus the
  // `unqualified` noise that cascades from it). The exit code and any `Error:`
  // line are the signal; the warning count is not.
  function applyIpc(key, value) {
    var v = value
    if (value === "true") v = true
    else if (value === "false") v = false
    else if (value !== "" && !isNaN(Number(value))) v = Number(value)
    root.set(key, v)
    root.save()
  }

  IpcHandler {
    target: "kenburnswallpaper"

    function setEnabled(value: string): void { root.applyIpc("enabled", value) }
    function setSpeed(value: string): void { root.applyIpc("speed", value) }
    function setMaxZoom(value: string): void { root.applyIpc("maxZoom", value) }
    function setDrift(value: string): void { root.applyIpc("drift", value) }
    function setWander(value: string): void { root.applyIpc("wander", value) }
    function setAdvance(value: string): void { root.applyIpc("advance", value) }
    function setTrail(value: string): void { root.applyIpc("trail", value) }
    function setTrailLag(value: string): void { root.applyIpc("trailLag", value) }

    function reset(): void {
      root.resetDefaults()
      root.clock = 0
      root.lastTickMs = 0
      root.lastLoopIndex = 0
      root.advanceArmedForLoop = -1
    }

    function status(): string {
      return JSON.stringify(root.config)
    }
  }

  // Settings apply on the current pose. A SPEED change keeps the loop
  // fraction; turning wander off snaps the live heading back to the locked
  // one. Wallpaper changes and reset still zero the clock.
  onConfigChanged: {
    root.enabled = root.config.enabled
    root.reparameterizeSpeed(root.config.speed)
    if (!root.config.wander) {
      root.liveDrift = root.config.drift
      root.liveDriftLocked = false
    } else if (!root.liveDriftLocked) {
      root.liveDrift = root.config.drift
    }
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
      console.warn("[kenburnswallpaper] " + root.settingsPath + " unreadable, using defaults: " + error)
      root.applyConfig("")
      root.save()
    }
    onFileChanged: reload()
  }

  // A bounded trace of the pose. Off unless KENBURNS_TRACE=1 or the settings
  // file carries `"trace": true` (pose tests write that flag; it is not part
  // of the sanitised schema, so a panel save cannot leave it on).
  property bool tracing: false

  function startTrace() {
    root.clock = 0
    root.lastTickMs = 0
    root.lastLoopIndex = 0
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
    // The trace the test suites read. The units matter to whoever parses it: `t` is
    // MILLISECONDS of the plugin's own clock, `seg` is the position in the loop
    // (0..1), `z` is the scale factor (1.0 up to maxZoom), and `x`/`y` are the pan
    // as a fraction of the margin the zoom opens. Reading `t` as seconds gives
    // silently zero speeds -- a measurement of mine went wrong exactly that way.
    // `drift` is the live heading (wander may have moved it since the file).
    onTriggered: console.log("[kenburnswallpaper] pose " + JSON.stringify({
      t: Math.round(root.clock),
      cy: root.loopIndex,
      seg: Number(root.segment.toFixed(4)),
      z: Number(root.zoom.toFixed(6)),
      x: Number(root.panOffsetX.toFixed(6)),
      y: Number(root.panOffsetY.toFixed(6)),
      drift: root.liveDrift
    }))
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/current"
  readonly property string currentLink: stateDir + "/background"

  // ------------------------------------------------------------- Ken Burns pose
  // One loop is one smooth oscillation: the zoom travels out to the far pose and
  // back again over `duration`, along a single cosine. One cosine across the whole
  // loop is C-infinity continuous -- zero velocity at both turnarounds and at the
  // seam where the loop restarts -- so the pose can neither stop nor jump.
  //
  // Both halves get exactly half of `duration`. An earlier version spent three
  // quarters of the loop going out and a quarter coming back, which made the
  // return three times quicker than the outbound leg and read as a jump at the end
  // of the move (reported from the desktop). Equal halves are the fix.
  readonly property real cycleMs: Math.max(1000, config.speed * 1000)
  readonly property int loopIndex: Math.floor(clock / cycleMs)
  readonly property real segment: Math.max(0, Math.min(1, (clock % cycleMs) / cycleMs))

  // 0 -> 1 -> 0 across one period, cosine-eased at both ends.
  function cosineWave(periodMs, t) {
    var when = (t === undefined) ? root.clock : t
    return 0.5 - 0.5 * Math.cos(2 * Math.PI * (when % periodMs) / periodMs)
  }

  readonly property real progress: root.cosineWave(cycleMs)

  function mix(a, b, t) { return a + (b - a) * t }

  function zoomAt(t) {
    return mix(1, config.maxZoom, root.cosineWave(cycleMs, Math.max(0, t)))
  }

  function panOffsetXAt(t) {
    var z = zoomAt(t)
    return panX * (z - 1) / 2
  }

  function panOffsetYAt(t) {
    var z = zoomAt(t)
    return panY * (z - 1) / 2
  }

  // The loop always runs 1 -> maxZoom -> 1, so it starts and ends on the whole
  // image: no zoom-direction setting could change anything but the pose you land
  // on when the config is applied.
  readonly property real zoom: zoomAt(root.clock)

  // ------------------------------------------------------------------- drift
  // Which way the image creeps while the zoom opens: an axis of its own, so any
  // zoom can drift any way. The offset rides on the margin the zoom creates,
  // (zoom - 1) / 2, never on absolute pixels -- so at zoom 1 there is no drift,
  // and no combination of settings can pull the image inside the window and show
  // a black edge.
  // Fixed, not configurable: a Length slider was tried and removed. Its useful
  // range is narrow (the visible difference between 30 % and 60 % is small next to
  // the zoom it rides on) and the ceiling is what you want anyway. 0.9 rather than
  // 1.0 on purpose: at 1.0 the image edge lands exactly on the screen edge, so a
  // sub-pixel rounding could show a hairline of whatever is underneath. 0.9 leaves
  // ~14 px of slack at the default zoom.
  readonly property real driftLength: 0.9
  readonly property real panOffsetX: panX * (zoom - 1) / 2   // as a fraction of the screen
  readonly property real panOffsetY: panY * (zoom - 1) / 2

  property real clock: 0
  property real lastTickMs: 0

  onLoopIndexChanged: {
    var idx = root.loopIndex
    var prev = root.lastLoopIndex
    root.lastLoopIndex = idx
    if (idx <= prev) return
    if (root.config.wander) {
      root.liveDrift = Settings.pickWanderDrift(root.liveDrift)
      root.liveDriftLocked = true
    }
  }

  // ------------------------------------------------------- pause when unseen
  readonly property var lockService: shell && shell.serviceFor ? shell.serviceFor("omarchy.lock") : null
  readonly property bool sessionLocked: !!(lockService && lockService.locked)

  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0
  property var coveredScreenNames: []

  readonly property bool allScreensCovered: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return false
    var names = root.coveredScreenNames
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (!screen || !screen.name) return false
      var hit = false
      for (var j = 0; j < names.length; j++) {
        if (names[j] === screen.name) { hit = true; break }
      }
      if (!hit) return false
    }
    return true
  }

  readonly property bool clockRunning: enabled && !sessionLocked
                                       && screensaverWindowCount === 0
                                       && !allScreensCovered

  function eventParts(event, count) {
    try {
      if (event && event.parse) return event.parse(count)
    } catch (e) {
    }
    return String(event && event.data ? event.data : "").split(",")
  }

  function setScreensaverWindow(address, visible) {
    var key = String(address || "")
    if (!key) return
    var next = {}
    var count = 0
    var current = root.screensaverWindows || {}
    for (var existing in current) {
      if (existing !== key && current[existing]) {
        next[existing] = true
        count += 1
      }
    }
    if (visible) {
      next[key] = true
      count += 1
    }
    root.screensaverWindows = next
    root.screensaverWindowCount = count
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openwindow") {
      var open = root.eventParts(event, 4)
      if (String(open[2] || "") === root.screensaverClass)
        root.setScreensaverWindow(open[0], true)
    } else if (name === "closewindow") {
      var close = root.eventParts(event, 1)
      var address = String(close[0] || "")
      if (root.screensaverWindows[address])
        root.setScreensaverWindow(address, false)
    }
  }

  function refreshCoverage() {
    var names = []
    try {
      var tops = ToplevelManager.toplevels.values
      for (var i = 0; i < tops.length; i++) {
        var t = tops[i]
        if (!t || !t.fullscreen) continue
        var ss = t.screens
        for (var j = 0; j < ss.length; j++) {
          if (ss[j] && ss[j].name) names.push(ss[j].name)
        }
      }
    } catch (e) {
    }
    root.coveredScreenNames = names
  }

  function screenCovered(screen) {
    if (!screen || !screen.name) return false
    var names = root.coveredScreenNames
    for (var i = 0; i < names.length; i++) {
      if (names[i] === screen.name) return true
    }
    return false
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Timer {
    interval: 400
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshCoverage()
  }

  onEnabledChanged: root.lastTickMs = 0
  onClockRunningChanged: root.lastTickMs = 0

  Timer {
    interval: root.frameMs
    running: root.clockRunning
    repeat: true
    // Real elapsed time, not a tick count: a Timer that slips when the shell is
    // busy must not stretch `duration: 20` into 30 real seconds. lastTickMs is
    // discarded on pause so the first tick after cannot add a huge delta.
    onTriggered: {
      var now = Date.now()
      if (root.lastTickMs > 0) root.clock += (now - root.lastTickMs)
      root.lastTickMs = now
      root.maybeAdvanceEarly()
    }
  }

  // ------------------------------------------------------- wallpaper state
  property string displayPath: ""     // what is on screen right now
  property string incomingPath: ""    // what the fade is blending in
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
    // Keep the Ken Burns pose: the incoming image already shared the same
    // zoom and pan during the fade, so restarting the clock would snap back
    // to zoom 1 and break the cinematic handoff.
  }

  function imageUrl(path) {
    return path ? Util.fileUrl(path) : ""
  }

  // Ask for the next wallpaper before the loop seam, so the file is decoded
  // and the crossfade is already running while the move is still going. Firing
  // at the seam left a stall: the cosine is stopped there, and the next image
  // only arrived after Omarchy and the decoder had finished.
  property int advanceArmedForLoop: -1

  function maybeAdvanceEarly() {
    if (!root.config.advance) return
    if (root.advanceArmedForLoop === root.loopIndex) return
    if (root.revealProgress < 1 || root.incomingPath !== "") return
    if (advanceProc.running) return
    var lead = root.revealMs + 700
    var intoLoop = root.clock % root.cycleMs
    if (root.cycleMs - intoLoop > lead) return
    root.advanceArmedForLoop = root.loopIndex
    advanceProc.running = true
  }

  Process {
    id: advanceProc
    command: ["omarchy-theme-bg-next"]
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
        // The fade itself waits until the incoming image is Ready (startReveal),
        // so we never blend in an empty frame. This timer is the
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
      console.warn("[kenburnswallpaper] incoming image never became ready; swapping anyway")
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
  // The 30 s readlink poll is only a net if the watcher ever dies.
  Process {
    id: watcher
    command: ["inotifywait", "-m", "-q", "-e", "create,moved_to,close_write,delete", root.stateDir]
    stdout: SplitParser { onRead: function(line) { root.refresh() } }
    onExited: console.warn("[kenburnswallpaper] inotifywait exited; relying on the 30 s poll")
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    root.snapPanToLive()
    refresh()
    watcher.running = true
    // Do not log config here: FileView has not read the file yet, so it would
    // print the defaults. applyConfig logs the real file a moment later.
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      color: baseImage.status === Image.Ready ? "black" : "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      visible: !remapGuard.remapping && !win.covered
               && !root.sessionLocked && root.screensaverWindowCount === 0

      readonly property bool covered: {
        var names = root.coveredScreenNames
        var n = modelData && modelData.name
        if (!n) return false
        for (var i = 0; i < names.length; i++) {
          if (names[i] === n) return true
        }
        return false
      }

      ScreenMoveRemap {
        id: remapGuard
        window: win
      }

      // Visual only: an empty input region, so the surface never eats a click
      // (desktop double-click still opens Omarchy's background switcher).
      mask: Region { }
      // Never reserve space or push windows around.
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "kenburnswallpaper"
      // The stock wallpaper is on the *background* layer; the inter-layer order
      // (background < bottom < top < overlay) puts this above the wallpaper and
      // below every window and the bar.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Decode only as much as the zoomed crop needs. The parent scales up to
      // maxZoom, so the texture has to be that much larger than the panel, not
      // the wallpaper's native 6K. mipmap is off: the zoom magnifies.
      readonly property int decodeW: Math.ceil(Math.max(1, win.width) * root.config.maxZoom)
      readonly property int decodeH: Math.ceil(Math.max(1, win.height) * root.config.maxZoom)

      // ------------------------------------------------------- wallpaper
      // Sharp pose first, then lagged copies on top. Each pose is its own item
      // so the trail can sit where the image was a moment ago.
      Item {
        id: wallpaperStack
        width: win.width
        height: win.height

        readonly property bool trailActive: root.config.trail === true
                     && baseImage.status === Image.Ready
                     && root.revealProgress >= 1
                     && root.incomingPath === ""
        readonly property real trailLagMs: root.cycleMs * root.config.trailLag

        Item {
          id: sharpLayer
          width: parent.width
          height: parent.height
          x: root.panOffsetX * width
          y: root.panOffsetY * height
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
            mipmap: false
            sourceSize.width: win.decodeW
            sourceSize.height: win.decodeH
            opacity: status !== Image.Ready ? 0
                     : (incomingImage.fading ? (1 - root.revealProgress) : 1)
          }

          Image {
            id: incomingImage
            readonly property bool fading: root.incomingPath !== ""
                     && root.revealProgress < 1
                     && status === Image.Ready
            anchors.fill: parent
            visible: fading
            source: root.imageUrl(root.incomingPath)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            mipmap: false
            sourceSize.width: win.decodeW
            sourceSize.height: win.decodeH
            opacity: root.revealProgress
            onStatusChanged: if (status === Image.Ready) root.startReveal()
          }
        }

        // Farther ghost: twice the lag, softer and more blurred.
        Item {
          id: trailFar
          visible: wallpaperStack.trailActive
          width: parent.width
          height: parent.height
          x: root.panOffsetXAt(root.clock - wallpaperStack.trailLagMs * 2) * width
          y: root.panOffsetYAt(root.clock - wallpaperStack.trailLagMs * 2) * height
          scale: root.zoomAt(root.clock - wallpaperStack.trailLagMs * 2)
          transformOrigin: Item.Center
          opacity: 0.18

          Image {
            id: trailFarImage
            anchors.fill: parent
            source: baseImage.source
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: false
            sourceSize.width: win.decodeW
            sourceSize.height: win.decodeH
            visible: false
          }

          MultiEffect {
            anchors.fill: parent
            source: trailFarImage
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 14
            blurMultiplier: 0
          }
        }

        // Nearer ghost: one lag step behind the sharp pose.
        Item {
          id: trailNear
          visible: wallpaperStack.trailActive
          width: parent.width
          height: parent.height
          x: root.panOffsetXAt(root.clock - wallpaperStack.trailLagMs) * width
          y: root.panOffsetYAt(root.clock - wallpaperStack.trailLagMs) * height
          scale: root.zoomAt(root.clock - wallpaperStack.trailLagMs)
          transformOrigin: Item.Center
          opacity: 0.28

          Image {
            id: trailNearImage
            anchors.fill: parent
            source: baseImage.source
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: false
            sourceSize.width: win.decodeW
            sourceSize.height: win.decodeH
            visible: false
          }

          MultiEffect {
            anchors.fill: parent
            source: trailNearImage
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1.0
            blurMax: 8
            blurMultiplier: 0
          }
        }
      }
    }
  }
}
