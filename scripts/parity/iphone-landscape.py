#!/usr/bin/env python3
"""Measure the native iPhone keyboard in LANDSCAPE, and gate Obadh against it.

WHY A SEPARATE TOOL
    Landscape is structurally unlike portrait: the keyboard container does not
    span the screen, it is inset on both sides, and on notched iPhones the globe
    and dictation keys sit OUTSIDE it in the safe-area corners. So the portrait
    suite's assumptions (container starts at the screen edge, bottom row is part
    of the same block) do not hold, and its container probe samples the host's
    text field instead of the keyboard backdrop.

    The container top is therefore found by scanning a column INSIDE the
    container's horizontal span but clear of any key, which only ever sees the
    backdrop or the host background.

USAGE
    scripts/parity/iphone-landscape.py measure <png> <logical-width>
    scripts/parity/iphone-landscape.py fit                  # every reference
    scripts/parity/iphone-landscape.py compare <shots-dir>  # gate, non-zero on fail
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
REFERENCE = ROOT / "Reference" / "native-iphone" / "landscape"

# Landscape widths of every iPhone class we ship to, with the portrait width that
# picks the geometry class. The SE is its own class: no safe-area inset to work
# around, so it gets a smaller side inset and LARGER keys than any notched phone.
FLEET = [
    ("se3-native.png", 667.0, 375.0, "iPhone SE (3rd generation)"),
    ("i16-native.png", 852.0, 393.0, "iPhone 16"),
    ("i17pro-native.png", 874.0, 402.0, "iPhone 17 Pro"),
    ("air-native.png", 912.0, 420.0, "iPhone Air"),
    ("i16plus-native.png", 932.0, 430.0, "iPhone 16 Plus"),
    ("i17promax-native.png", 956.0, 440.0, "iPhone 17 Pro Max"),
]


@dataclass
class Row:
    n: int
    top: float
    height: float
    x0: float
    x1: float
    widths: list[float]


@dataclass
class Geometry:
    width: float
    screen_height: float
    side_inset: float
    key_height: float
    pitch: float
    gap: float
    key_top: float
    key_bottom: float
    container_top: float
    rows: list[Row]


def key_boxes(px: np.ndarray, scale: float) -> list[tuple]:
    """Bright, well-filled rectangles in the bottom half — the keys."""
    gray = px.mean(axis=2)
    h = gray.shape[0]
    y0 = int(h * 0.35)
    labels, _ = ndimage.label(gray[y0:] > 233)
    boxes = []
    for index, sl in enumerate(ndimage.find_objects(labels), 1):
        ys, xs = sl
        kw, kh = xs.stop - xs.start, ys.stop - ys.start
        # Landscape keys are short and wide: 27pt tall on notched phones, 32 on an
        # SE. The floor has to sit below that, but above glyph fragments.
        if kw < 18 * scale or kh < 18 * scale:
            continue
        if (labels[sl] == index).sum() / (kw * kh) < 0.6:
            continue
        boxes.append((ys.start + y0, ys.stop + y0, xs.start, xs.stop))
    return boxes


def group_rows(boxes: list[tuple], scale: float) -> list[list[tuple]]:
    grouped: list[list[tuple]] = []
    for box in sorted(boxes, key=lambda b: (b[0], b[2])):
        cy = (box[0] + box[1]) / 2
        for row in grouped:
            rcy = sum((a + b) / 2 for a, b, _, _ in row) / len(row)
            if abs(rcy - cy) < 12 * scale:
                row.append(box)
                break
        else:
            grouped.append([box])
    grouped = [sorted(r, key=lambda b: b[2]) for r in grouped if len(r) >= 3]
    grouped.sort(key=lambda r: r[0][0])
    return grouped


def measure(path: Path, logical_width: float) -> Geometry:
    px = np.array(Image.open(path).convert("RGB")).astype(float)
    h, w, _ = px.shape
    scale = w / logical_width
    grouped = group_rows(key_boxes(px, scale), scale)
    if not grouped:
        raise SystemExit(f"{path.name}: no keys found — is the keyboard on screen?")

    rows: list[Row] = []
    for row in grouped:
        widths = [(b[3] - b[2]) / scale for b in row]
        heights = [(b[1] - b[0]) / scale for b in row]
        rows.append(
            Row(
                n=len(row),
                top=round(min(b[0] for b in row) / scale, 2),
                height=round(float(np.median(heights)), 2),
                x0=round(row[0][2] / scale, 2),
                x1=round(row[-1][3] / scale, 2),
                widths=[round(v, 2) for v in widths],
            )
        )

    tops = [r.top for r in rows]
    pitch = float(np.median(np.diff(tops))) if len(tops) > 1 else 0.0
    key_height = float(np.median([r.height for r in rows]))
    # Gap: the median horizontal space between adjacent keys on the top row.
    top = grouped[0]
    gaps = [(top[i + 1][2] - top[i][3]) / scale for i in range(len(top) - 1)]
    gap = float(np.median(gaps)) if gaps else 0.0

    side_inset = min(r.x0 for r in rows)
    # Container top, by matching the BACKDROP rather than by leaving the host
    # background. Sampling "first row that differs from the page" walks into the
    # host's text field, which on the wide-inset classes overlaps the column any
    # probe would pick — that is what made the earlier attempt report a 152pt zone.
    # Instead: take the backdrop colour from just above the first key row, then
    # walk UP while rows still match it. Where they stop is the container's edge.
    band_x0 = int((side_inset + gap) * scale)
    band_x1 = int((max(r.x1 for r in rows) - gap) * scale)
    first_key_top = int(rows[0].top * scale)
    backdrop = px[first_key_top - int(4 * scale):first_key_top - int(1 * scale),
                  band_x0:band_x1, :].reshape(-1, 3).mean(axis=0)
    # Use the row MEDIAN, and require the change to persist. The prediction strip
    # sits between the container edge and the first key row, so its separators and
    # text are the first things an upward scan meets; a mean trips on them, a
    # median ignores them, and the persistence check ignores the rest.
    container_top = rows[0].top
    run = 0
    persist = max(2, int(3 * scale))
    for y in range(first_key_top - int(2 * scale), 0, -1):
        rowmedian = np.median(px[y, band_x0:band_x1, :], axis=0)
        if float(np.abs(rowmedian - backdrop).max()) > 6:
            run += 1
            if run >= persist:
                container_top = (y + run) / scale
                break
        else:
            run = 0

    return Geometry(
        width=logical_width,
        screen_height=round(h / scale, 2),
        side_inset=round(side_inset, 2),
        key_height=round(key_height, 2),
        pitch=round(pitch, 2),
        gap=round(gap, 2),
        key_top=round(rows[0].top, 2),
        key_bottom=round(rows[-1].top + rows[-1].height, 2),
        container_top=round(container_top, 2),
        rows=rows,
    )


def fit() -> None:
    print(f"{'device':28}{'W':>6}{'portrait':>9}{'inset':>7}{'key':>7}{'pitch':>7}"
          f"{'gap':>6}{'container':>10}{'rows':>6}")
    for name, width, portrait, label in FLEET:
        g = measure(REFERENCE / name, width)
        container = round(g.screen_height - g.container_top, 1)
        print(f"{label:28}{width:6.0f}{portrait:9.0f}{g.side_inset:7.1f}{g.key_height:7.1f}"
              f"{g.pitch:7.2f}{g.gap:6.1f}{container:10.1f}{len(g.rows):6}")
        print(f"{'':28}rows " + " ".join(f"{r.n}" for r in g.rows)
              + f"   key_top {g.key_top:.1f}  key_bottom {g.key_bottom:.1f}")


def compare(shots: Path, tolerance: float) -> int:
    failures = 0
    for name, width, _portrait, label in FLEET:
        candidate = shots / name.replace("-native.png", "-obadh.png")
        if not candidate.exists():
            print(f"\n=== {label} — NO CAPTURE, skipped")
            continue
        native = measure(REFERENCE / name, width)
        ours = measure(candidate, width)
        print(f"\n=== {label} ({width:g}pt landscape)")
        problems = []
        for field in ("side_inset", "key_height", "pitch", "key_top", "key_bottom"):
            n, o = getattr(native, field), getattr(ours, field)
            flag = "" if abs(o - n) <= tolerance else "  <-- OUT OF TOLERANCE"
            if flag:
                problems.append(f"{field} {o - n:+.2f}pt")
            print(f"  {field:<11} native {n:8.2f}   obadh {o:8.2f}   {o - n:+7.2f}{flag}")
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
    c.add_argument("shots", type=Path)
    c.add_argument("--tolerance", type=float, default=2.0)
    args = parser.parse_args()

    if args.cmd == "measure":
        print(json.dumps(asdict(measure(args.image, args.width)), indent=2))
    elif args.cmd == "compare":
        raise SystemExit(compare(args.shots, args.tolerance))
    else:
        fit()


if __name__ == "__main__":
    main()
