.pragma library

// Single source of truth for the plugin's user-facing parameters. Shared by
// Service.qml (which applies them) and Menu.qml (which edits them), so it lives
// in its own module instead of being duplicated in both files.
//
// v3.0 schema, and deliberately small. Removed after living with them:
// `preset` (a shortcut through four values, not an effect of its own),
// `handheld` (a ~50 px wobble on top of a 40 s traverse read as the wallpaper
// vibrating, not as a hand), `breathing` (with a continuous loop its "off" state
// is a hard snap back, and its "on" state left the direction switch looking
// inert) and `smoothEasing` (ease-in-out is simply the better default; the toggle
// only offered a worse one).
//
// Four values remain, and each one changes something you can see: whether it
// moves, how long the loop takes, how far it zooms, and which way.

var DIRECTIONS = ["in", "out"]

var DIRECTION_LABELS = { in: "In", out: "Out" }

function directionOptions() {
  var out = []
  for (var i = 0; i < DIRECTIONS.length; i++)
    out.push({ value: DIRECTIONS[i], label: DIRECTION_LABELS[DIRECTIONS[i]] })
  return out
}

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

var DEFAULTS = {
  enabled: true,
  duration: 20.0,
  maxZoom: 1.15,
  direction: "in",
  drift: "center",
  driftLength: 0.5
}

var LIMITS = {
  duration: { min: 5, max: 60 },
  maxZoom: { min: 1.05, max: 1.30 },   // 1.30 is the cap: above it the copy shows its pixels
  // How far the drift travels, as a fraction of the margin the zoom opens. The
  // ceiling is 0.9 rather than 1.0 on purpose: at 1.0 the image edge lands
  // exactly on the screen edge, so a sub-pixel rounding could show a hairline of
  // whatever is underneath. 0.9 leaves ~14 px of slack at the default zoom.
  driftLength: { min: 0, max: 0.9 }
}

// One step per slider. PanelSlider does not apply `step` itself, so the panel
// reads these and snaps (see snapToStep).
var STEPS = { duration: 1, maxZoom: 0.01, driftLength: 0.05 }

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)) }

function decimalsOf(n) {
  var text = String(n)
  var dot = text.indexOf(".")
  return dot < 0 ? 0 : text.length - dot - 1
}

// PanelSlider's mouse path does NOT apply `step` -- it only rounds when
// `integer` is true (see valueFromX in Ui/PanelSlider.qml), so a drag otherwise
// hands us values like 1.1456522623697918. Snap in the panel, relative to the
// minimum so the grid lines up with the track's own ticks.
//
// Two float traps, both hit while writing this: 1.15 / 0.01 is 114.99999999999999
// so a naive Math.round lands on 1.14, and 1.05 + 10 * 0.01 is
// 1.1500000000000001 so the snapped result needs rounding too.
function snapToStep(value, step, minimum) {
  var n = typeof value === "number" ? value : parseFloat(value)
  if (!isFinite(n)) return value
  var s = typeof step === "number" ? step : parseFloat(step)
  if (!isFinite(s) || s <= 0) return n
  var base = isFinite(minimum) ? minimum : 0
  var snapped = base + Math.round(Number(((n - base) / s).toFixed(6))) * s
  return Number(snapped.toFixed(Math.max(decimalsOf(s), decimalsOf(base))))
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

function normaliseDirection(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  for (var i = 0; i < DIRECTIONS.length; i++) {
    if (DIRECTIONS[i] === raw) return DIRECTIONS[i]
    if (DIRECTION_LABELS[DIRECTIONS[i]].toLowerCase() === raw) return DIRECTIONS[i]
  }
  return DEFAULTS.direction
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
// round-trips to a canonical shape.
function sanitize(raw) {
  var input = (raw && typeof raw === "object") ? raw : {}
  return {
    enabled: bool(input.enabled, DEFAULTS.enabled),
    duration: number(input.duration, LIMITS.duration.min, LIMITS.duration.max, DEFAULTS.duration),
    maxZoom: number(input.maxZoom, LIMITS.maxZoom.min, LIMITS.maxZoom.max, DEFAULTS.maxZoom),
    direction: normaliseDirection(input.direction),
    drift: normaliseDrift(input.drift),
    driftLength: number(input.driftLength, LIMITS.driftLength.min, LIMITS.driftLength.max, DEFAULTS.driftLength)
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
