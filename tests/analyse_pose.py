#!/usr/bin/env python3
"""Assertions over the plugin's own pose trace.

Reads "[animated-wallpaper] pose {...}" lines on stdin (see tests/pose.test.sh)
and checks the behaviour each scenario asks for. Prints PASS/FAIL per assertion
and exits with the number of failures.

Testing the trace rather than the screen is deliberate: the trace prints the
exact properties the window consumes, so the assertions are deterministic and
cannot be poisoned by whichever window happens to have focus.

Slopes are always measured per unit of `seg`, never per sample: the trace timer
jitters, so a per-sample difference measures the sampling, not the easing.
"""
import json
import math
import statistics
import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else "plateau"
failures = 0


def ok(label, detail=""):
    print("  PASS  %s%s" % (label, ("  (%s)" % detail) if detail else ""))


def bad(label, detail=""):
    global failures
    failures += 1
    print("  FAIL  %s%s" % (label, ("  (%s)" % detail) if detail else ""))


def check(condition, label, detail=""):
    (ok if condition else bad)(label, detail)


samples = []
for line in sys.stdin:
    if "pose " not in line:
        continue
    try:
        samples.append(json.loads(line.split("pose ", 1)[1]))
    except ValueError:
        pass

if not samples:
    bad("the plugin produced a pose trace")
    print("failures %d" % failures)
    sys.exit(failures)

samples.sort(key=lambda s: s["t"])
ok("the plugin produced a pose trace", "%d samples" % len(samples))

deltas_t = [b["t"] - a["t"] for a, b in zip(samples, samples[1:]) if b["t"] > a["t"]]
step_s = (statistics.median(deltas_t) / 1000.0) if deltas_t else 0.15

by_cycle = {}
for s in samples:
    by_cycle.setdefault(s["cy"], []).append(s)
cycle_ids = sorted(by_cycle)
# The last cycle in the window is usually truncated mid-traverse: judge only the
# ones we saw from the start.
complete = [(c, by_cycle[c]) for c in cycle_ids[:-1]]

zooms = [s["z"] for s in samples]
xs = [s["x"] for s in samples]
ys = [s["y"] for s in samples]


def boundary_estimates():
    """Midpoint of each straddle between consecutive cycles: the true boundary
    lies between the last sample of one cycle and the first of the next, so the
    midpoint is the best estimate a sampled trace can give."""
    out = []
    for (ca, ga), (cb, gb) in zip(complete, complete[1:]):
        before = max(s["t"] for s in ga)
        after = min(s["t"] for s in gb)
        if after >= before:
            out.append((before + after) / 2000.0)
    return out


def slopes_of(group):
    """|dz| per unit of segment: jitter-immune, and the cosine ease has a
    characteristic peak/mean of ~1.57 against ~1.0 for linear."""
    out = []
    for a, b in zip(group, group[1:]):
        dseg = b["seg"] - a["seg"]
        if dseg > 0.02:
            out.append(abs(b["z"] - a["z"]) / dseg)
    return [s for s in out if s > 1e-7]


if MODE == "plateau":
    pause = float(sys.argv[2])
    duration = float(sys.argv[3])
    period = pause + duration
    check(len(complete) >= 2, "at least two complete cycles observed",
          "complete=%d of %d" % (len(complete), len(cycle_ids)))
    for cy, group in complete[:4]:
        dwell = [s["z"] for s in group if s["seg"] >= 0.999]
        if dwell:
            spread = max(dwell) - min(dwell)
            check(spread < 1e-6, "cycle %d holds a still pose during pauseAtEnd" % cy,
                  "spread=%.8f" % spread)
            held = (len(dwell) - 1) * step_s
            check(abs(held - pause) <= 0.75, "cycle %d dwell lasts ~%.1fs" % (cy, pause),
                  "measured %.2fs" % held)
        else:
            bad("cycle %d has a dwell" % cy)
        moving = [s["z"] for s in group if s["seg"] < 0.999]
        if len(moving) >= 3:
            rising = all(b >= a - 1e-9 for a, b in zip(moving, moving[1:]))
            falling = all(b <= a + 1e-9 for a, b in zip(moving, moving[1:]))
            check(rising or falling, "cycle %d traverses in one direction" % cy)
        else:
            bad("cycle %d has enough moving samples" % cy, "n=%d" % len(moving))
    bounds = boundary_estimates()
    gaps = [b - a for a, b in zip(bounds, bounds[1:])]
    if gaps:
        check(all(abs(g - period) <= 0.5 for g in gaps),
              "cycle period is duration+pauseAtEnd (%.1fs)" % period,
              "gaps=%s" % ", ".join("%.2f" % g for g in gaps))
    else:
        bad("could estimate the cycle period")

elif MODE in ("eased", "linear"):
    if MODE == "eased":
        dev = [abs(s["e"] - (0.5 - 0.5 * math.cos(math.pi * s["seg"]))) for s in samples]
        check(max(dev) < 0.01, "smoothEasing is the cosine ease", "max deviation %.4f" % max(dev))
    else:
        dev = [abs(s["e"] - s["seg"]) for s in samples]
        check(max(dev) < 0.01, "linear easing keeps eased == segment", "max deviation %.4f" % max(dev))

    if not complete:
        bad("a complete cycle to judge the easing shape")
    else:
        cy, group = max(complete, key=lambda cg: len(cg[1]))
        slopes = slopes_of(group)
        if len(slopes) < 4:
            bad("enough moving samples to judge the easing shape", "n=%d in cycle %d" % (len(slopes), cy))
        else:
            peak, mean = max(slopes), sum(slopes) / len(slopes)
            ratio = peak / mean
            if MODE == "eased":
                check(ratio > 1.35, "smoothEasing ramps (peak/mean slope)", "%.2f" % ratio)
            else:
                check(ratio < 1.15, "linear does not ramp (peak/mean slope)", "%.2f" % ratio)

elif MODE == "horizontal":
    check(max(abs(y) for y in ys) < 1e-6, "horizontal keeps panY at zero",
          "max=%.6f" % max(abs(y) for y in ys))
    check(min(xs) < -0.2 and max(xs) > 0.2, "horizontal sweeps panX both ways",
          "%.3f..%.3f" % (min(xs), max(xs)))
    check(max(zooms) - min(zooms) < 1e-6, "horizontal pins the zoom",
          "drift=%.6f" % (max(zooms) - min(zooms)))

elif MODE == "vertical":
    check(max(abs(x) for x in xs) < 1e-6, "vertical keeps panX at zero",
          "max=%.6f" % max(abs(x) for x in xs))
    check(min(ys) < -0.2 and max(ys) > 0.2, "vertical sweeps panY both ways",
          "%.3f..%.3f" % (min(ys), max(ys)))
    check(max(zooms) - min(zooms) < 1e-6, "vertical pins the zoom",
          "drift=%.6f" % (max(zooms) - min(zooms)))

elif MODE == "maxzoom":
    target = float(sys.argv[2])
    check(abs(max(zooms) - target) < 0.005, "zoom reaches maxZoom",
          "%.4f vs %.2f" % (max(zooms), target))
    check(abs(min(zooms) - 1.0) < 0.005, "zoom returns to 1.0", "%.4f" % min(zooms))
    check(max(abs(x) for x in xs) < 1e-6 and max(abs(y) for y in ys) < 1e-6, "zoomIn does not pan",
          "x=%.6f y=%.6f" % (max(abs(x) for x in xs), max(abs(y) for y in ys)))

elif MODE == "random":
    allowed = ["zoomIn", "zoomOut", "horizontal", "vertical"]
    seen = {s["var"] for s in samples}
    check(seen.issubset(set(allowed)), "random only uses the four variants", ",".join(sorted(seen)))
    pairs = {}
    for s in samples:
        pairs.setdefault(s["pair"], []).append(s)
    # One pair of cycles is 2*(duration+pauseAtEnd), and duration cannot go below
    # 5 s, so a short window simply may not contain three pairs to compare.
    if len(pairs) >= 3:
        check(len(seen) >= 2, "random varies across pairs",
              "%d distinct over %d pairs" % (len(seen), len(pairs)))
    else:
        ok("random varies across pairs", "not enough pairs to judge (%d)" % len(pairs))
    ordered = [pairs[k] for k in sorted(pairs)[:-1]]      # drop the truncated one
    jumps = []
    for a, b in zip(ordered, ordered[1:]):
        last, first = a[-1], b[0]
        jumps.append(abs(first["z"] - last["z"]) + abs(first["x"] - last["x"]) + abs(first["y"] - last["y"]))
    if jumps:
        check(max(jumps) < 0.05, "random never jumps at a pair boundary",
              "max jump %.4f over %d boundaries" % (max(jumps), len(jumps)))
    else:
        bad("random produced more than one complete pair", "%d pairs seen" % len(pairs))
else:
    bad("unknown analyser mode: %s" % MODE)

print("failures %d" % failures)
sys.exit(failures)
