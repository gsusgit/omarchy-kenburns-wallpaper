.pragma library

// Single source of truth for the plugin's user-facing parameters. Shared by
// Service.qml (which applies them) and Menu.qml (which edits them), so it lives
// in its own module instead of being duplicated in both files.
//
// v5 schema. Still small. Removed after living with them:
// `preset` (a shortcut through four values, not an effect of its own),
// `handheld` (a ~50 px wobble on top of a 40 s traverse read as the wallpaper
// vibrating, not as a hand), `breathing` (with a continuous loop its "off" state
// is a hard snap back, and its "on" state left the direction switch looking
// inert) and `smoothEasing` (ease-in-out is simply the better default; the toggle
// only offered a worse one).
//
// Motion blur and a freeform tint were considered for v5 and rejected: at these
// speeds the per-frame travel is about a pixel, and a colour wash fights the
// photograph the theme already chose.
//
// Eight values remain, and each one changes something you can see: whether it
// moves, how long the loop takes, how far it zooms, which way it drifts, whether
// that heading changes at the loop seam, whether a finished loop asks Omarchy
// for the next wallpaper, and an optional motion trail. The trail draws lagged
// copies of the same photograph at earlier poses along the Ken Burns path, so
// the move reads as a cinematic streak. It does not change the zoom.
// Atmosphere was tried in v5 and dropped after living with it: a grade on top
// of the photograph never read as room light, only as a faint pulse, so it
// failed the same test as breathing and the v0.5 overlays.
// There is no zoom-direction control: with a symmetric loop, "in" and "out" are
// the same oscillation half a period apart, so the switch could only ever choose
// the pose you start on -- invisible within seconds of a loop that never stops.
// The drift's length is fixed too (see Service.qml): its useful range is narrow,
// and the ceiling is what you want anyway.

// The drift is the move's other axis: which way the image creeps while the zoom
// opens. It is a vector, so the eight compass points plus "centre" cover every
// diagonal a person actually wants -- a straight-only control was tried and
// rejected, and the alternative (two X/Y ranges, or an angle in degrees) spends
// a slider on something a single click can say.
//
// Note the diagonals are per-axis fractions, not unit vectors: "upLeft" takes
// half the horizontal margin and half the vertical margin, the way someone
// framing a shot would say it. That makes a diagonal travel 1.41x further in
// total than a straight drift, at the same per-axis safety.
var DRIFTS = ["center", "left", "right", "up", "down",
              "upLeft", "upRight", "downLeft", "downRight"]

var DRIFT_VECTORS = {
  center: [0, 0],
  left: [-1, 0], right: [1, 0], up: [0, -1], down: [0, 1],
  upLeft: [-1, -1], upRight: [1, -1], downLeft: [-1, 1], downRight: [1, 1]
}

// Arrows and a dot, laid out as a 3x3 diana in the panel (see DRIFT_ORDER).
// U+2190..U+2199 and U+25CF are all present in the shell's font, checked with
// fc-list rather than assumed.
var DRIFT_LABELS = {
  center: "\u25cf",
  left: "\u2190", right: "\u2192", up: "\u2191", down: "\u2193",
  upLeft: "\u2196", upRight: "\u2197", downLeft: "\u2199", downRight: "\u2198"
}

var DRIFT_TOOLTIPS = {
  center: "No drift: the zoom stays centred",
  left: "Drift left", right: "Drift right", up: "Drift up", down: "Drift down",
  upLeft: "Drift up-left", upRight: "Drift up-right",
  downLeft: "Drift down-left", downRight: "Drift down-right"
}

// Reading order for a 3x3 grid: up-left, up, up-right / left, centre, right /
// down-left, down, down-right. The centre dot lands in the middle, which is what
// makes the control read as a diana rather than as nine buttons.
var DRIFT_ORDER = ["upLeft", "up", "upRight",
                   "left", "center", "right",
                   "downLeft", "down", "downRight"]

function driftOptions() {
  var out = []
  for (var i = 0; i < DRIFT_ORDER.length; i++) {
    var name = DRIFT_ORDER[i]
    out.push({ value: name, label: DRIFT_LABELS[name], tooltip: DRIFT_TOOLTIPS[name] })
  }
  return out
}

function driftVector(value) {
  var v = DRIFT_VECTORS[String(value === undefined || value === null ? "" : value)]
  return v ? v : DRIFT_VECTORS.center
}

// A new heading for wander, never the one we just used. At the loop seam the
// zoom is 1 and the pan is 0, so the swap is invisible. Math.random is fine:
// this is a heading, not a cryptographic choice.
function pickWanderDrift(current) {
  var cur = normaliseDrift(current)
  var choices = []
  for (var i = 0; i < DRIFTS.length; i++) {
    if (DRIFTS[i] !== cur) choices.push(DRIFTS[i])
  }
  if (choices.length === 0) return cur
  return choices[Math.floor(Math.random() * choices.length)]
}

var DEFAULTS = {
  enabled: true,
  speed: 48,
  maxZoom: 1.20,
  drift: "center",
  wander: true,
  advance: true,
  trail: true,
  // Second notch: a short streak. Long enough to read, short enough that the
  // cosine turnarounds still collapse it.
  trailLag: 0.03
}

// The key is `speed` -- that is what the panel calls it -- and its value is the
// loop PERIOD in seconds, so a smaller number is faster. Five levels, evenly
// spaced from the extra-fast end (10 s) to the calm end (60 s). The panel
// addresses them through a speed index that runs the other way (see
// speedLevelIndex). Zoom stays five even 0.05 steps, capped at 1.30.
var DURATION_LEVELS = [10, 23, 35, 48, 60]

// The zoom's five levels. They end at 1.30 on purpose: that is the hard cap,
// above which the copy shows its own pixels instead of the wallpaper's. The
// default, 1.20, is the middle notch.
var MAXZOOM_LEVELS = [1.10, 1.15, 1.20, 1.25, 1.30]

// How far back along the loop the trail looks, as a fraction of one period.
// Ordered low-to-high so the panel's minus button always means a shorter trail.
var TRAIL_LAG_LEVELS = [0.015, 0.03, 0.045, 0.06, 0.08]

var LIMITS = {
  speed: { min: DURATION_LEVELS[0], max: DURATION_LEVELS[DURATION_LEVELS.length - 1] },
  maxZoom: { min: MAXZOOM_LEVELS[0], max: MAXZOOM_LEVELS[MAXZOOM_LEVELS.length - 1] }
}

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)) }

// Nearest level, ties going up -- the rule the tests pin down. Shared by both
// level-based controls so they cannot drift apart in behaviour.
function snapToLevel(levels, value, fallback) {
  var n = typeof value === "number" ? value : parseFloat(value)
  if (!isFinite(n)) return fallback
  var best = levels[0]
  for (var i = 1; i < levels.length; i++) {
    if (Math.abs(levels[i] - n) <= Math.abs(best - n)) best = levels[i]
  }
  return best
}

function levelIndexOf(levels, value, fallback) {
  var level = snapToLevel(levels, value, fallback)
  for (var i = 0; i < levels.length; i++) {
    if (levels[i] === level) return i
  }
  return 0
}

function snapSpeed(value) { return snapToLevel(DURATION_LEVELS, value, DEFAULTS.speed) }

// The key was called `duration` until 3.4. A file written before that still works
// -- its value is read as the speed -- and the next write stores it under the new
// name only, so the file migrates itself.
function readSpeed(input) {
  var raw = (input.speed !== undefined) ? input.speed : input.duration
  return snapToLevel(DURATION_LEVELS, raw, DEFAULTS.speed)
}

function durationLevelIndex(value) { return levelIndexOf(DURATION_LEVELS, value, DEFAULTS.speed) }

// The panel calls this control SPEED while the value underneath is a loop period,
// so the two run in opposite directions: the fastest setting is the SHORTEST
// duration. This is the speed index -- 0 is the slowest level (the longest loop)
// and the last is the fastest -- and it is what the slider and the +/- buttons
// walk, so "more" always means faster and "less" always means slower, and the
// slider's right end is the quick one.
function speedLevelIndex(value) {
  return DURATION_LEVELS.length - 1 - levelIndexOf(DURATION_LEVELS, value, DEFAULTS.speed)
}

function durationForSpeedIndex(index) {
  var n = typeof index === "number" ? index : parseFloat(index)
  if (!isFinite(n)) return DEFAULTS.speed
  var i = clamp(Math.round(n), 0, DURATION_LEVELS.length - 1)
  return DURATION_LEVELS[DURATION_LEVELS.length - 1 - i]
}

function snapMaxZoom(value) { return snapToLevel(MAXZOOM_LEVELS, value, DEFAULTS.maxZoom) }

function maxZoomLevelIndex(value) { return levelIndexOf(MAXZOOM_LEVELS, value, DEFAULTS.maxZoom) }

function snapTrailLag(value) {
  return snapToLevel(TRAIL_LAG_LEVELS, value, DEFAULTS.trailLag)
}

function trailLagLevelIndex(value) {
  return levelIndexOf(TRAIL_LAG_LEVELS, value, DEFAULTS.trailLag)
}

// One release carried `overlay` / `overlayOpacity` instead of trail. Read them
// once so an existing file keeps its on/off state and slider position, then
// write back under the new names only.
var OVERLAY_LEGACY_LEVELS = [0.5, 0.6, 0.7, 0.8, 0.9]

function readTrail(input) {
  if (input.trail !== undefined) return bool(input.trail, DEFAULTS.trail)
  if (input.overlay !== undefined) return bool(input.overlay, DEFAULTS.trail)
  return DEFAULTS.trail
}

function readTrailLag(input) {
  if (input.trailLag !== undefined) return snapTrailLag(input.trailLag)
  if (input.overlayOpacity !== undefined) {
    var idx = levelIndexOf(OVERLAY_LEGACY_LEVELS, input.overlayOpacity, 0.9)
    return TRAIL_LAG_LEVELS[Math.min(idx, TRAIL_LAG_LEVELS.length - 1)]
  }
  return DEFAULTS.trailLag
}

function number(value, min, max, fallback) {
  var n = typeof value === "number" ? value : parseFloat(value)
  if (!isFinite(n)) return fallback
  return clamp(n, min, max)
}

function bool(value, fallback) {
  if (typeof value === "boolean") return value
  if (value === "true") return true
  if (value === "false") return false
  return fallback
}

function normaliseDrift(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim()
  var lower = raw.toLowerCase().replace(/[\s_-]/g, "")
  for (var i = 0; i < DRIFTS.length; i++) {
    if (DRIFTS[i].toLowerCase() === lower) return DRIFTS[i]
  }
  return DEFAULTS.drift
}

// Whitelist + clamp. Anything unreadable, out of range or unknown becomes the
// default, so a hand-edited file can never break the renderer, a previous
// schema's keys are dropped rather than resurrected, and the file always
// round-trips to a canonical shape. `trace` is a test-only flag on the raw
// file; it is deliberately not part of this object so a panel save cannot
// persist it.
function sanitize(raw) {
  var input = (raw && typeof raw === "object") ? raw : {}
  return {
    enabled: bool(input.enabled, DEFAULTS.enabled),
    speed: readSpeed(input),
    maxZoom: snapMaxZoom(input.maxZoom),
    drift: normaliseDrift(input.drift),
    wander: bool(input.wander, DEFAULTS.wander),
    advance: bool(input.advance, DEFAULTS.advance),
    trail: readTrail(input),
    trailLag: readTrailLag(input)
  }
}

function parse(text) {
  var raw = null
  try { raw = JSON.parse(String(text || "")) } catch (e) { raw = null }
  return sanitize(raw)
}

function serialise(config) {
  return JSON.stringify(sanitize(config), null, 2) + "\n"
}

function wantsTrace(text) {
  try {
    var obj = JSON.parse(String(text || ""))
    return !!(obj && obj.trace === true)
  } catch (e) {
    return false
  }
}
