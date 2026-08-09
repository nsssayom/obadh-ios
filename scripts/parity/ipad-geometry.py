#!/usr/bin/env python3
"""Measure native iPadOS keyboard geometry from a screenshot, and fit the
proportional model Obadh uses to reproduce it.

WHY THIS EXISTS
    iPhone taught us that native key geometry is class-quantized, not
    width-proportional (43pt keys below ~410pt, 45pt above). iPad turned out to
    be quantized in a much stronger sense: the *row structure itself* changes
    with width — 4 rows without tab/caps on a mini, 4 rows with them on a
    standard iPad, 5 rows with a dedicated number row on a 13-inch. So a single
    ratio table measured on one iPad cannot be trusted, and this tool exists so
    the claim "we match native" is a measurement rather than an opinion.

MODEL
    Within one layout family, native lays every row out as

        sum(weight_k) * u + (n - 1) * gap + 2 * margin == screenWidth

    with `margin` and `gap` constant for the family and `u` (the letter-key
    width) falling out of that equation. Every row of a device therefore
    resolves to the SAME u — which is the falsifiable part of the model, and
    what `--fit` checks.

USAGE
    scripts/parity/ipad-geometry.py measure Reference/native-ipad/pro11-native.png 834
    scripts/parity/ipad-geometry.py fit           # fit + residuals for every reference
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, asdict
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "Reference" / "native-ipad"

# Portrait widths of every iPad that can run our deployment target. There is
# nothing between 744 and 820, so the compact/standard boundary cannot be
# probed further with real hardware — these five ARE the fleet.
FLEET = [
    ("mini-native.png", 744.0, "iPad mini (A17 Pro) / mini 6"),
    ("ipad-native.png", 820.0, "iPad (A16) / iPad 10 / Air 11"),
    ("pro11-native.png", 834.0, "iPad Pro 11-inch"),
    ("air13-native.png", 1024.0, "iPad Air 13-inch / Pro 12.9 6th gen"),
    ("pro13-native.png", 1032.0, "iPad Pro 13-inch"),
]


@dataclass
class Row:
    n: int
    top: float
    height: float
    x0: float
    x1: float
    gap: float
    widths: list[float]


@dataclass
class Geometry:
    width: float
    screen_height: float
    margin: float
    gap: float
    key_top: float
    key_bottom: float
    pitch: float
    rows: list[Row]


def measure(path: Path, logical_width: float) -> Geometry:
    px = np.array(Image.open(path).convert("RGB")).astype(float)
    h, w, _ = px.shape
    scale = w / logical_width
    gray = px.mean(axis=2)

    y0 = int(h * 0.55)
    labels, _ = ndimage.label(gray[y0:] > 233)
    boxes = []
    for index, sl in enumerate(ndimage.find_objects(labels), 1):
        ys, xs = sl
        kw, kh = xs.stop - xs.start, ys.stop - ys.start
        if kw < 30 * scale or kh < 20 * scale:
            continue
        if (labels[sl] == index).sum() / (kw * kh) < 0.6:
            continue
        boxes.append((ys.start + y0, ys.stop + y0, xs.start, xs.stop))

    grouped: list[list[tuple]] = []
    for box in sorted(boxes, key=lambda b: (b[0], b[2])):
        cy = (box[0] + box[1]) / 2
        for row in grouped:
            rcy = sum((a + b) / 2 for a, b, _, _ in row) / len(row)
            if abs(rcy - cy) < 20 * scale:
                row.append(box)
                break
        else:
            grouped.append([box])
    grouped = [sorted(r, key=lambda b: b[2]) for r in grouped if len(r) >= 3]
    grouped.sort(key=lambda r: r[0][0])

    rows: list[Row] = []
    for row in grouped:
        widths = [(b[3] - b[2]) / scale for b in row]
        heights = [(b[1] - b[0]) / scale for b in row]
        gaps = [(row[i + 1][2] - row[i][3]) / scale for i in range(len(row) - 1)]
        rows.append(
            Row(
                n=len(row),
                top=round(min(b[0] for b in row) / scale, 2),
                height=round(float(np.median(heights)), 2),
                x0=round(row[0][2] / scale, 2),
                x1=round(row[-1][3] / scale, 2),
                gap=round(float(np.median(gaps)), 2),
                widths=[round(v, 2) for v in widths],
            )
        )

    centres = [r.top + r.height / 2 for r in rows]
    pitches = [centres[i + 1] - centres[i] for i in range(len(centres) - 1)]
    return Geometry(
        width=logical_width,
        screen_height=round(h / scale, 1),
        margin=round(min(r.x0 for r in rows), 2),
        gap=round(float(np.median([r.gap for r in rows])), 2),
        key_top=round(min(r.top for r in rows), 2),
        key_bottom=round(max(r.top + r.height for r in rows), 2),
        pitch=round(float(np.median(pitches)), 2),
        rows=rows,
    )


def letter_unit(g: Geometry) -> float:
    """The letter-key width u. Taken from the letter rows only: the bottom row
    has no letter keys, so its modal width is the globe key and would poison the
    estimate (an earlier version of this script did exactly that and reported a
    false INCONSISTENT)."""
    candidates: list[float] = []
    for row in g.rows:
        hist: dict[float, int] = {}
        for value in row.widths:
            hist[round(value * 2) / 2] = hist.get(round(value * 2) / 2, 0) + 1
        mode, count = max(hist.items(), key=lambda kv: (kv[1], -kv[0]))
        if count >= 5:  # a genuine run of letter keys
            candidates.append(mode)
    return float(np.median(candidates))


def fit(geometries: list[tuple[str, Geometry]]) -> None:
    """Check the falsifiable claim: within a device, every row resolves to the
    same letter-key unit u once margin and gap are removed."""
    for label, g in geometries:
        u = letter_unit(g)
        print(f"\n{label}: W={g.width:g}pt  margin={g.margin}  gap={g.gap}  u={u}")
        residuals = []
        for i, row in enumerate(g.rows, 1):
            content = g.width - 2 * g.margin - (row.n - 1) * g.gap
            measured = sum(row.widths)
            residuals.append(measured - content)
            print(
                f"  row {i}: n={row.n:2d} h={row.height:5.2f} "
                f"sum(w)={content / u:7.3f}  fill residual {measured - content:+.2f}pt"
            )
            print("     weights: " + " ".join(f"{v / u:.3f}" for v in row.widths))
        worst = max(abs(r) for r in residuals)
        verdict = "CONSISTENT" if worst <= 1.5 else f"INCONSISTENT (residual {worst:.2f}pt)"
        print(f"  rows fill the width to within {worst:.2f}pt -> {verdict}")
        print(
            f"  key band {g.key_top}..{g.key_bottom}pt of {g.screen_height}pt "
            f"(bottom inset {g.screen_height - g.key_bottom:.1f}), pitch {g.pitch}, "
            f"row spacing {g.pitch - g.rows[-1].height:.2f}"
        )


def compare(shots: Path, tolerance: float) -> int:
    """Diff Obadh against the stored native reference on every fleet width.

    Expects `<shots>/<label>-obadh.png` alongside the reference captures. Returns
    a non-zero exit status if anything is outside tolerance, so this can gate a
    merge the way the iPhone parity suite does.
    """
    failures = 0
    for name, width, devices in FLEET:
        label = name.replace("-native.png", "")
        candidate = shots / f"{label}-obadh.png"
        if not candidate.exists():
            print(f"\n=== {label} ({width:g}pt) — NO CAPTURE, skipped")
            continue
        native = measure(REFERENCE / name, width)
        ours = measure(candidate, width)
        print(f"\n=== {label} ({width:g}pt) — {devices}")
        problems: list[str] = []

        for field in ("margin", "gap", "pitch", "key_top", "key_bottom"):
            n, o = getattr(native, field), getattr(ours, field)
            flag = "" if abs(o - n) <= tolerance else "  <-- OUT OF TOLERANCE"
            if flag:
                problems.append(f"{field} {o - n:+.2f}pt")
            print(f"  {field:<11} native {n:8.2f}   obadh {o:8.2f}   {o - n:+7.2f}{flag}")

        if len(native.rows) != len(ours.rows):
            problems.append(f"row count {len(ours.rows)} vs {len(native.rows)}")
            print(f"  ROW COUNT native {len(native.rows)} obadh {len(ours.rows)}")
        for i, (rn, ro) in enumerate(zip(native.rows, ours.rows), 1):
            if rn.n != ro.n:
                problems.append(f"row {i} has {ro.n} keys, native has {rn.n}")
                print(f"  row {i}: KEY COUNT native {rn.n} obadh {ro.n}")
                continue
            deltas = [b - a for a, b in zip(rn.widths, ro.widths)]
            worst = max(deltas, key=abs)
            flag = "" if abs(worst) <= tolerance else "  <-- OUT OF TOLERANCE"
            if flag:
                problems.append(f"row {i} key width {worst:+.2f}pt")
            print(
                f"  row {i}: n={rn.n:2d}  h {rn.height:5.1f}/{ro.height:5.1f}  "
                f"worst key {worst:+.2f}pt{flag}"
            )

        if problems:
            failures += 1
            print(f"  FAIL: {'; '.join(problems)}")
        else:
            print(f"  PASS (everything within {tolerance:g}pt)")

    print(f"\n{'ALL PASS' if not failures else f'{failures} device(s) FAILED'}")
    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("measure")
    m.add_argument("image", type=Path)
    m.add_argument("width", type=float)
    sub.add_parser("fit")
    c = sub.add_parser("compare")
    c.add_argument("shots", type=Path, help="directory holding <label>-obadh.png")
    c.add_argument("--tolerance", type=float, default=2.0)
    args = parser.parse_args()

    if args.cmd == "measure":
        print(json.dumps(asdict(measure(args.image, args.width)), indent=2))
        return
    if args.cmd == "compare":
        raise SystemExit(compare(args.shots, args.tolerance))

    fit([(name, measure(REFERENCE / name, width)) for name, width, _ in FLEET])


if __name__ == "__main__":
    main()
