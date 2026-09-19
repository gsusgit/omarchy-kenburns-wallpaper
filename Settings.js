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

var DEFAULTS = {
  enabled: true,
  duration: 20.0,
  maxZoom: 1.15,
  direction: "in"
}

var LIMITS = {
  duration: { min: 5, max: 60 },
  maxZoom: { min: 1.05, max: 1.30 }    // 1.30 is the cap: above it the copy shows its pixels
}

// One step per slider. PanelSlider does not apply `step` itself, so the panel
// reads these and snaps (see snapToStep).
var STEPS = { duration: 1, maxZoom: 0.01 }

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
    direction: normaliseDirection(input.direction)
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
