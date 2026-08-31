#!/usr/bin/env python3
"""Measure what is drawn INSIDE the keys, native vs Obadh, on every iPad family
and both orientations.

WHY THIS EXISTS
    `ipad-geometry.py` measures key RECTANGLES and passes. On a real iPad the
    keyboard still read as an imitation, because everything wrong was inside the
    keys: letters 43% too large, flick labels 36% too small and twice as bright,
    and every command glyph centred where native pins it to the key's bottom-outer
    corner. No gate looked at any of that.

    It is also where a single-device measurement will burn you. An iPad mini
    CENTRES its command glyphs; every larger iPad anchors them. Reading a Pro
    11-inch and applying it everywhere puts the mini's glyphs against the wrong
    edge, so this checks each family separately.

USAGE
    scripts/parity/ipad-type.py fit                       # native, all families
    scripts/parity/ipad-type.py compare <shots>           # gate ours against it
    scripts/parity/ipad-type.py compare <shots> --landscape

Captures must be LIGHT mode, to match the stored references.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "Reference" / "native-ipad"

FLEET = [
    ("mini", 744.0, "compact"), ("ipad", 820.0, "standard"), ("pro11", 834.0, "standard"),
    ("air13", 1024.0, "extended"), ("pro13", 1032.0, "extended"),
]
FLEET_LANDSCAPE = [
    ("mini", 1133.0, "compact"), ("ipad", 1180.0, "standard"), ("pro11", 1210.0, "standard"),
    ("air13", 1366.0, "extended"), ("pro13", 1376.0, "extended"),
]

# SF Pro proportions, used only to turn measured ink back into a point size.
X_HEIGHT = 0.517


def rows_of(path: Path, width: float):
    px = np.array(Image.open(path).convert("RGB")).astype(float)
    s = px.shape[1] / width
    g = px.mean(axis=2)
    lab, _ = ndimage.label(g > 233)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        ys, xs = sl
        kw, kh = xs.stop - xs.start, ys.stop - ys.start
        if kw < 40 * s or kh < 30 * s or kw > 260 * s or kh > 110 * s:
            continue
        if (lab[sl] == i).sum() / (kw * kh) < 0.6:
            continue
        out.append((ys.start / s, ys.stop / s, xs.start / s, xs.stop / s))
    grouped: dict[float, list] = {}
    for r in out:
        for k in list(grouped):
            if abs(k - r[0]) < 12:
                grouped[k].append(r)
                break
        else:
            grouped[r[0]] = [r]
    rows = [sorted(v, key=lambda k: k[2]) for _, v in sorted(grouped.items())]
    return px, s, [r for r in rows if len(r) >= 5]


def ink_box(px, s, rect, thr, y_from=0.0, y_to=1.0, pad=2.0):
    y0, y1, x0, x1 = rect
    kh = y1 - y0
    reg = px[int((y0 + y_from * kh) * s) + 1:int((y0 + y_to * kh) * s) - 1,
             int((x0 + pad) * s):int((x1 - pad) * s), :].mean(axis=2)
    m = reg < thr
    if not m.any():
        return None
    ys, xs = np.where(m)
    return dict(
        left=pad + xs.min() / s,
        right=(x1 - x0) - (pad + xs.max() / s),
        bottom=(y1 - y0) - (y_from * kh + ys.max() / s),
        w=(xs.max() - xs.min() + 1) / s,
        h=(ys.max() - ys.min() + 1) / s,
        darkest=float(reg[m].min()),
    )


def measure(path: Path, width: float, family: str) -> dict:
    px, s, rows = rows_of(path, width)
    if len(rows) < 4:
        raise SystemExit(f"{path.name}: found {len(rows)} key rows, expected 4-5")
    letter_row = rows[1] if family == "extended" else rows[0]
    command_row = rows[-1]
    mid = letter_row[len(letter_row) // 2]
    fill = float(np.median(px[int((mid[0] + 0.55 * (mid[1] - mid[0])) * s):
                              int((mid[0] + 0.7 * (mid[1] - mid[0])) * s),
                              int((mid[2] + 4) * s):int((mid[2] + 10) * s), :]))
    # Start below the flick label, or its ink inflates the letter's height. The
    # extended family draws no flick label, so the same window would instead clip
    # the top off the letter and under-report native by ~3pt.
    letter = ink_box(px, s, mid, 150, y_from=0.30 if family == "extended" else 0.45)
    second = ink_box(px, s, mid, fill - 12, y_from=0.05, y_to=0.40, pad=8)
    return dict(
        key_height=round(letter_row[0][1] - letter_row[0][0], 1),
        letter_pt=round(letter["h"] / X_HEIGHT, 1) if letter else 0.0,
        second_h=round(second["h"], 1) if second else 0.0,
        second_alpha=round(1 - second["darkest"] / fill, 2) if second else 0.0,
        # Row 0 ends in backspace in EVERY family. The extended letter row does
        # not - it ends in a backslash key - so taking it from `letter_row`
        # compared a character glyph against a symbol and reported 12pt of
        # error that was not there.
        backspace=ink_box(px, s, rows[0][-1], 150),
        globe=ink_box(px, s, command_row[0], 150),
        hide=ink_box(px, s, command_row[-1], 150),
    )


def line(tag: str, m: dict) -> str:
    def io(box, side):
        return f"{box[side]:5.1f}" if box else "  n/a"
    return (f"  {tag:8} keyH {m['key_height']:5.1f}  letter {m['letter_pt']:5.1f}pt"
            f"  flick {m['second_h']:4.1f}/{m['second_alpha']:.2f}"
            f"   backspace R{io(m['backspace'],'right')} B{io(m['backspace'],'bottom')}"
            f"   globe L{io(m['globe'],'left')} B{io(m['globe'],'bottom')}"
            f"   hide R{io(m['hide'],'right')} B{io(m['hide'],'bottom')}")


def run(shots: Path | None, landscape: bool, tolerance: float) -> int:
    fleet = FLEET_LANDSCAPE if landscape else FLEET
    sub = "landscape/" if landscape else ""
    failures = 0
    for name, width, family in fleet:
        native = measure(REFERENCE / f"{sub}{name}-native.png", width, family)
        print(f"\n=== {name} ({width:g}pt, {family})")
        print(line("native", native))
        if shots is None:
            continue
        candidate = shots / f"{name}-obadh.png"
        if not candidate.exists():
            print("  NO CAPTURE, skipped")
            continue
        ours = measure(candidate, width, family)
        print(line("obadh", ours))
        problems = []
        if abs(ours["letter_pt"] - native["letter_pt"]) > 2.5:
            problems.append(f"letter {ours['letter_pt'] - native['letter_pt']:+.1f}pt")
        if abs(ours["second_h"] - native["second_h"]) > 2.5:
            problems.append(f"flick size {ours['second_h'] - native['second_h']:+.1f}pt")
        if abs(ours["second_alpha"] - native["second_alpha"]) > 0.12:
            problems.append(f"flick alpha {ours['second_alpha'] - native['second_alpha']:+.2f}")
        # Only the side the glyph is anchored to, plus the bottom. The opposite
        # inset is just "key width minus glyph width", so it moves with the SF
        # Symbol's own size and says nothing about placement.
        for key, side in (("backspace", "right"), ("globe", "left"), ("hide", "right")):
            n, o = native[key], ours[key]
            if not n or not o:
                continue
            for axis in (side, "bottom"):
                if abs(o[axis] - n[axis]) > tolerance:
                    problems.append(f"{key}.{axis} {o[axis] - n[axis]:+.1f}pt")
        if problems:
            failures += 1
            print(f"  FAIL: {'; '.join(problems)}")
        else:
            print(f"  PASS (type within 2.5pt, glyph insets within {tolerance:g}pt)")
    if shots is not None:
        print(f"\n{'ALL PASS' if not failures else f'{failures} device(s) FAILED'}")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fit").add_argument("--landscape", action="store_true")
    c = sub.add_parser("compare")
    c.add_argument("shots", type=Path)
    c.add_argument("--landscape", action="store_true")
    c.add_argument("--tolerance", type=float, default=4.0)
    args = parser.parse_args()
    raise SystemExit(run(getattr(args, "shots", None), args.landscape,
                         getattr(args, "tolerance", 4.0)))


if __name__ == "__main__":
    main()
