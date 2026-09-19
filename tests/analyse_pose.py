#!/usr/bin/env python3
"""Assertions over the plugin's own pose trace (v3.0 engine).

Reads "[animated-wallpaper] pose {...}" lines on stdin (see tests/pose.test.sh)
and checks the behaviour each scenario asks for. Prints PASS/FAIL per assertion
and exits with the number of failures.

Trace fields: t (clock ms), cy (loop index), seg (0..1 through the loop), z (zoom).

Testing the trace rather than the screen is deliberate: the trace prints the
exact properties the window consumes, so the assertions are deterministic and
cannot be poisoned by whichever window happens to have focus -- this desktop
belongs to a human, and a suite that needs it idle fails for the wrong reason.

Slopes are always measured per unit of `seg`, never per sample: the trace timer
jitters, so a per-sample difference measures the sampling, not the motion.

The loop is ONE cosine across the whole period (see Service.qml). That is the
property the "no stop, no jump" requirement rests on, and it is what the
rate-symmetry assertion below pins down: an earlier version spent 3/4 of the loop
outbound and 1/4 returning, and the 3x quicker return read as a jump at the end
of the move on the real desktop. Equal halves are the fix.
"""
import json
import math
import statistics
import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else "loop"
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
# The last loop in the window is usually truncated mid-traverse: judge only the
# ones seen from the start.
complete = [(c, by_cycle[c]) for c in cycle_ids[:-1]]

zooms = [s["z"] for s in samples]


def boundary_deltas(pairs):
    """|dz| between the last sample of one loop and the first of the next: the
    hand-off the eye sees when the loop restarts."""
    return [abs(b[1][0]["z"] - a[1][-1]["z"]) for a, b in zip(pairs, pairs[1:])]


def boundary_estimates(pairs):
    """Midpoint of each straddle between consecutive loops: the true boundary
    lies between the last sample of one and the first of the next, so the
    midpoint is the best estimate a sampled trace can give."""
    out = []
    for (ca, ga), (cb, gb) in zip(pairs, pairs[1:]):
        before = max(s["t"] for s in ga)
        after = min(s["t"] for s in gb)
        if after >= before:
            out.append((before + after) / 2000.0)
    return out


def rates(group):
    """(outbound, return) mean |dz| per unit of seg. Equal halves make them
    equal; a quicker return leg makes the second one larger."""
    out, back = [], []
    for a, b in zip(group, group[1:]):
        dseg = b["seg"] - a["seg"]
        if dseg > 0.02:                      # ignores the seam, where seg wraps
            (out if a["seg"] < 0.5 else back).append(abs(b["z"] - a["z"]) / dseg)
    mean = lambda xs: (sum(xs) / len(xs)) if xs else 0.0
    return mean(out), mean(back)


if MODE in ("loop", "out"):
    duration = float(sys.argv[2])
    target = float(sys.argv[3])
    descending = MODE == "out"
    check(len(complete) >= 3, "at least three complete loops observed",
          "complete=%d of %d" % (len(complete), len(cycle_ids)))

    # The loop period is what the DURATION slider promises: "Amount 20 seconds"
    # means the whole motion cycle takes 20 s, not half of it.
    bounds = boundary_estimates(complete)
    gaps = [b - a for a, b in zip(bounds, bounds[1:])]
    if gaps:
        check(all(abs(g - duration) <= 0.45 for g in gaps),
              "the loop period is `duration` (%.1fs)" % duration,
              "gaps=%s" % ", ".join("%.2f" % g for g in gaps))
    else:
        bad("could estimate the loop period")

    check(abs(max(zooms) - target) < 0.02, "the zoom reaches maxZoom",
          "%.4f vs %.2f" % (max(zooms), target))
    check(abs(min(zooms) - 1.0) < 0.02, "the zoom returns to 1.0", "%.4f" % min(zooms))

    # No stop anywhere: a loop that dwelt at an extreme would pile samples up
    # near it. Sampled every ~150 ms over a 5 s loop, the cosine spends ~0.4 s
    # within 2% of each end, so ~3 samples is the expected count, not a dwell.
    near_ends = sum(1 for z in zooms if z < 1.0 + 0.02 * (target - 1.0)
                                       or z > target - 0.02 * (target - 1.0))
    check(near_ends <= 0.25 * len(samples), "no loop dwells at either extreme",
          "%d of %d samples near an end (cosine would be ~%.0f)"
          % (near_ends, len(samples), 0.16 * len(samples)))

    # No jump anywhere: neither the turnaround nor the loop seam.
    deltas = boundary_deltas(complete)
    check(max(deltas) < 0.02, "the pose never jumps at the loop seam",
          "max boundary jump %.4f" % max(deltas))

    # No change of pace: the outbound and return halves run at the same mean
    # rate. This is the regression test for the 3/4-1/4 split, whose return leg
    # was 3x quicker and read as a jump at the end of the move.
    worst = 0.0
    for cy, group in complete:
        out_rate, back_rate = rates(group)
        if out_rate > 1e-9 and back_rate > 1e-9:
            worst = max(worst, back_rate / out_rate)
    check(worst < 1.25, "both halves of the loop run at the same pace",
          "worst return/outbound rate ratio = %.2f (3/4-1/4 split was ~3.0)" % worst)

    # One turnaround at each end, not a wobble: the zoom is monotonic within
    # each half of the loop.
    for cy, group in complete[:4]:
        for lo, hi, name in ((0.0, 0.5, "outbound"), (0.5, 1.0, "return")):
            values = [s["z"] for s in group if lo <= s["seg"] < hi]
            rising = all(b >= a - 1e-9 for a, b in zip(values, values[1:]))
            falling = all(b <= a + 1e-9 for a, b in zip(values, values[1:]))
            check(rising or falling, "loop %d: the %s half moves one way" % (cy, name))

    if complete:
        cy, group = complete[0]
        first = group[0]["z"]
        if descending:
            check(abs(first - target) < 0.03, "direction out starts zoomed in",
                  "%.4f at seg %.3f" % (first, group[0]["seg"]))
        else:
            check(abs(first - 1.0) < 0.03, "direction in starts unzoomed",
                  "%.4f at seg %.3f" % (first, group[0]["seg"]))

elif MODE == "ease":
    target = float(sys.argv[2])
    # Independent reimplementation of the loop's own curve: one cosine over the
    # whole period. This pins the easing shape to the trace rather than trusting
    # the engine's expression.
    dev = [abs(s["z"] - (1.0 + (target - 1.0) * (0.5 - 0.5 * math.cos(2 * math.pi * s["seg"]))))
           for s in samples]
    check(max(dev) < 0.01, "the zoom follows one cosine across the loop",
          "max deviation %.5f" % max(dev))

    if not complete:
        bad("a complete loop to judge the easing shape")
    else:
        cy, group = max(complete, key=lambda cg: len(cg[1]))
        slopes = []
        for a, b in zip(group, group[1:]):
            dseg = b["seg"] - a["seg"]
            if dseg > 0.02:
                slopes.append(abs(b["z"] - a["z"]) / dseg)
        slopes = [s for s in slopes if s > 1e-9]
        if len(slopes) < 4:
            bad("enough moving samples to judge the easing shape", "n=%d" % len(slopes))
        else:
            ratio = max(slopes) / (sum(slopes) / len(slopes))
            # A cosine has a characteristic peak/mean slope of pi/2 = 1.57, and
            # the peak sits at the middle of a half rather than at its start --
            # that is the difference between easing and a linear ramp (1.0).
            check(ratio > 1.35, "the zoom ramps in and out (peak/mean slope)",
                  "%.2f (linear would be 1.00)" % ratio)

            # The rate of a cosine is proportional to |sin(2*pi*seg)|: near zero
            # at both turnarounds and maximal halfway through a half. Comparing
            # against the ENDS specifically -- an earlier version of this check
            # compared the middle against "everything else", which includes the
            # fast shoulder and therefore proves nothing.
            mid, edge = [], []
            for a, b in zip(group, group[1:]):
                dseg = b["seg"] - a["seg"]
                if dseg <= 0.02:
                    continue
                v = abs(b["z"] - a["z"]) / dseg
                half = a["seg"] % 0.5
                if 0.20 < half < 0.30:
                    mid.append(v)
                elif half < 0.05 or half > 0.45:
                    edge.append(v)
            if mid and edge:
                check(max(mid) > 2 * max(edge), "the fastest zoom is mid-half, not at the ends",
                      "mid %.5f vs ends %.5f" % (max(mid), max(edge)))
            else:
                bad("samples in both the middle and the ends of a half")
else:
    bad("unknown analyser mode: %s" % MODE)

print("failures %d" % failures)
sys.exit(failures)
