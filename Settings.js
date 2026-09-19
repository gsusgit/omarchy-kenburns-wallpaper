.pragma library

// Single source of truth for the plugin's user-facing parameters. Shared by
// Service.qml (which applies them) and Menu.qml (which edits them), so it lives
// in its own module instead of being duplicated in both files.

var MODES = ["zoomIn", "zoomOut", "horizontal", "vertical", "random"]

var DEFAULTS = {
  enabled: true,
  duration: 20.0,
  maxZoom: 1.15,
  mode: "random",
  smoothEasing: true,
  pauseAtEnd: 2.0
}

var LIMITS = {
  duration: { min: 5, max: 120 },
  maxZoom: { min: 1.05, max: 1.30 },   // 1.30 is the cap: above it the copy shows its pixels
  pauseAtEnd: { min: 0, max: 10 }
}

var LABELS = {
  zoomIn: "Zoom In",
  zoomOut: "Zoom Out",
  horizontal: "Horizontal",
  vertical: "Vertical",
  random: "Random"
}

// Ordered {value,label} pairs for the mode dropdown: the human labels the menu
// shows, mapped to the values the engine switches on. Derived from MODES and
// LABELS so a new mode cannot end up half-wired.
function modeOptions() {
  var out = []
  for (var i = 0; i < MODES.length; i++) out.push({ value: MODES[i], label: LABELS[MODES[i]] })
  return out
}

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

function normaliseMode(value) {
  var raw = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (!raw) return DEFAULTS.mode
  var squashed = raw.replace(/[ _-]/g, "")
  for (var i = 0; i < MODES.length; i++) {
    if (MODES[i].toLowerCase() === raw) return MODES[i]
    if (LABELS[MODES[i]].toLowerCase().replace(/[ _-]/g, "") === squashed) return MODES[i]
  }
  return DEFAULTS.mode
}

// Whitelist + clamp. Anything unreadable, out of range or unknown becomes the
// default, so a hand-edited file can never break the renderer and the file
// always round-trips to a canonical shape.
function sanitize(raw) {
  var input = (raw && typeof raw === "object") ? raw : {}
  return {
    enabled: bool(input.enabled, DEFAULTS.enabled),
    duration: number(input.duration, LIMITS.duration.min, LIMITS.duration.max, DEFAULTS.duration),
    maxZoom: number(input.maxZoom, LIMITS.maxZoom.min, LIMITS.maxZoom.max, DEFAULTS.maxZoom),
    mode: normaliseMode(input.mode),
    smoothEasing: bool(input.smoothEasing, DEFAULTS.smoothEasing),
    pauseAtEnd: number(input.pauseAtEnd, LIMITS.pauseAtEnd.min, LIMITS.pauseAtEnd.max, DEFAULTS.pauseAtEnd)
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

// One variant per pair. Deliberately a hash of the pair index rather than
// Math.random(): a reload or a shell restart lands on the same pose instead of
// teleporting the image. Contract: deterministic, always one of the four, and
// covering all four as the pair index advances.
function variantForPair(pairIndex, mode) {
  if (mode !== "random") return MODES.indexOf(mode) >= 0 ? mode : "zoomIn"
  var x = (pairIndex + 1) * 2654435761
  x = (x ^ (x >> 13)) % 4
  return ["zoomIn", "zoomOut", "horizontal", "vertical"][Math.abs(x) % 4]
}
