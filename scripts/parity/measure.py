#!/usr/bin/env python3
"""Native-parity measurement over a sweep capture directory: geometry and color,
native vs Obadh, with tolerance-gated PASS/FAIL (exit 1 on any failure).

Capture contract (produced by sweep.sh):
  <slug>-<host>-<appearance>-{obadh,native}.png   full-screen simulator shots on the
      debug harness's --measure-bg backdrop (mid-gray, appearance-independent)
  <slug>-<host>-<appearance>.probe.txt            OBADH-PROBE lines (screen size in pt,
      rendered strip) logged by the DEBUG probe overlay

Measurement contract (all verified against known geometry):
  Obadh geometry is self-certified by the probe's yellow fiducial hairlines (view
  top, strip bottom = q row), sampled at x 0.90..0.985W — right of the probe label,
  which reaches ~0.88W on the narrowest device (keep new probe fields on its
  shortest line). Native q comes from key-brightness bands with
  a glyph-structure fallback; container edges from panel-color runs walking UP from
  the q row (the mid-gray backdrop guarantees contrast in both appearances).
  Colors are medians inside the 'w' key (fill away from the glyph), the q/a row
  gap (panel), glyph extremes (text), and the strip interior at x 0.90..0.96W.

Usage: measure.py CAPTURE_DIR [--json OUT.json]
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

TOL = {
    "zone": 3.0,     # container edge -> q row, native vs obadh (pt)
    "q": 2.0,        # absolute q-row position delta (pt)
    "keyfill": 4.0,  # max channel delta (native measured 1-2 after calibration)
    "panel": 3.0,
    "glyph": 6.0,
    "strip": 3.0,
}

def probe_vals(d, slug, host, app):
    p = d / f"{slug}-{host}-{app}.probe.txt"
    if not p.exists():
        return None, None
    t = p.read_text()
    w = re.search(r"scr (\d+)×", t)
    s = re.findall(r"m s(\d+)", t)
    return (float(w.group(1)) if w else None), (float(s[-1]) if s else None)

def hairlines(a, x0, x1, y_from):
    seg = a[y_from:, x0:x1]
    r, g, b = seg[..., 0], seg[..., 1], seg[..., 2]
    yellow = (r > 190) & (g > 150) & (b < 130) & ((r - b) > 90)
    frac = yellow.mean(axis=1)
    ys = np.where(frac > 0.5)[0]
    if len(ys) == 0:
        return []
    groups = [[ys[0]]]
    for y in ys[1:]:
        (groups[-1].append(y) if y - groups[-1][-1] <= 3 else groups.append([y]))
    return [y_from + int(np.mean(gp)) for gp in groups]

def edge_walk_up(rows, q_px, S):
    panel = rows[q_px - int(6 * S):q_px - int(2 * S)].mean(axis=0)
    breaks = 0
    i = q_px - int(2 * S)
    while i > 0:
        if np.linalg.norm(rows[i] - panel) > 25:
            breaks += 1
            if breaks >= int(3 * S):
                return i + breaks
        else:
            breaks = 0
        i -= 1
    return None

def native_q(a, g, edge_px, S, x0, x1, h):
    rows = g[:, x0:x1].mean(axis=1)
    y0 = max(edge_px + int(6 * S), int(0.62 * h))
    y1 = min(len(rows) - 1, y0 + int(130 * S))
    seg = rows[y0:y1]
    panel = np.percentile(seg, 20)
    keyish = np.abs(seg - panel) > 5
    inb, start = False, 0
    for i, v in enumerate(keyish):
        if v and not inb:
            inb, start = True, i
        elif not v and inb:
            inb = False
            if 25 * S < i - start < 60 * S:
                return y0 + start
    return None

def measure_geometry(path, ptw, is_obadh):
    img = Image.open(path)
    S = img.width / ptw
    a = np.asarray(img.convert("RGB"), dtype=float)
    g = np.asarray(img.convert("L"), dtype=float)
    ex0, ex1 = int(0.90 * img.width), int(0.985 * img.width)
    rows = a[:, ex0:ex1].mean(axis=1)
    y_search = int(0.55 * img.height)

    if is_obadh:
        lines = hairlines(a, int(0.90 * img.width), int(0.985 * img.width), y_search)
        if len(lines) < 2:
            return None
        view_top, q_px = lines[0], lines[1]
    else:
        bg = rows[y_search:y_search + int(6 * S)].mean(axis=0)
        prov, run = None, 0
        for i in range(y_search, len(rows) - int(12 * S)):
            if np.linalg.norm(rows[i] - bg) > 25:
                run += 1
                if run >= int(8 * S):
                    prov = i - run + 1
                    break
            else:
                run = 0
        if prov is None:
            return None
        q_px = native_q(a, g, prov, S, int(0.2 * img.width), int(0.8 * img.width), img.height)
        if q_px is None:
            return None
        view_top = None

    edge_px = edge_walk_up(rows, q_px, S)
    if edge_px is None:
        return None
    return {
        "edge": edge_px / S,
        "q": q_px / S,
        "zone": (q_px - edge_px) / S,
        "view_top": view_top / S if view_top is not None else None,
    }

def median_rgb(a, y0, y1, x0, x1):
    return np.median(a[y0:y1, x0:x1].reshape(-1, 3), axis=0)

def measure_colors(path, ptw, q_pt, compact):
    img = Image.open(path)
    S = img.width / ptw
    a = np.asarray(img.convert("RGB"), dtype=float)
    q = int(q_pt * S)
    keyh = int((43 if compact else 45) * S)
    pitch = int((54 if compact else 56) * S)
    xw = int(1.5 / 10 * img.width)
    kx0, kx1 = xw - int(8 * S), xw + int(8 * S)
    fill = (median_rgb(a, q + int(5 * S), q + int(11 * S), kx0, kx1)
            + median_rgb(a, q + keyh - int(11 * S), q + keyh - int(4 * S), kx0, kx1)) / 2
    panel = median_rgb(a, q + keyh + int(2 * S), q + pitch - int(2 * S), kx0, kx1)
    box = a[q + int(4 * S):q + keyh - int(3 * S), kx0:kx1].reshape(-1, 3)
    d = np.linalg.norm(box - fill, axis=1)
    sel = box[d > 60]
    glyph = np.median(sel, axis=0) if len(sel) > 10 else None
    sx0, sx1 = int(0.90 * img.width), int(0.96 * img.width)
    strip = median_rgb(a, q - int(16 * S), q - int(6 * S), sx0, sx1)
    return {"keyfill": fill, "panel": panel, "glyph": glyph, "strip": strip}

def main():
    d = Path(sys.argv[1])
    json_out = None
    if "--json" in sys.argv:
        json_out = Path(sys.argv[sys.argv.index("--json") + 1])

    pairs = {}
    for f in sorted(d.glob("*.png")):
        m = re.match(r"(.+)-(modern|legacy)-(light|dark)-(obadh|native)\.png", f.name)
        if m:
            slug, host, app, who = m.groups()
            pairs.setdefault((slug, host, app), {})[who] = f

    if not pairs:
        print(f"parity: no capture pairs found in {d}")
        return 2

    failures = 0
    results = []
    print(f"{'device':26s} {'host':7s} {'mode':6s} {'check':9s} {'native':>11s} {'obadh':>11s} {'delta':>7s}  verdict")
    for (slug, host, app), pair in sorted(pairs.items()):
        ptw, _ = probe_vals(d, slug, host, app)
        if ptw is None or "native" not in pair or "obadh" not in pair:
            print(f"{slug:26s} {host:7s} {app:6s} INCOMPLETE CELL")
            failures += 1
            continue
        compact = ptw < 410
        gn = measure_geometry(pair["native"], ptw, False)
        go = measure_geometry(pair["obadh"], ptw, True)
        if gn is None or go is None:
            print(f"{slug:26s} {host:7s} {app:6s} DETECT FAILED (native={gn is None} obadh={go is None})")
            failures += 1
            continue
        cell = {"device": slug, "host": host, "mode": app, "checks": {}}
        for name, nv, ov, tol in [
            ("zone", gn["zone"], go["zone"], TOL["zone"]),
            ("q", gn["q"], go["q"], TOL["q"]),
        ]:
            delta = abs(nv - ov)
            ok = delta <= tol
            failures += 0 if ok else 1
            cell["checks"][name] = {"native": nv, "obadh": ov, "delta": delta, "ok": ok}
            print(f"{slug:26s} {host:7s} {app:6s} {name:9s} {nv:11.1f} {ov:11.1f} {delta:7.1f}  {'ok' if ok else 'FAIL'}")
        cn = measure_colors(pair["native"], ptw, gn["q"], compact)
        co = measure_colors(pair["obadh"], ptw, go["q"], compact)
        for name in ("keyfill", "panel", "glyph", "strip"):
            nv, ov = cn[name], co[name]
            if nv is None or ov is None:
                continue
            delta = float(np.abs(nv - ov).max())
            ok = delta <= TOL[name]
            failures += 0 if ok else 1
            cell["checks"][name] = {
                "native": [round(float(v), 1) for v in nv],
                "obadh": [round(float(v), 1) for v in ov],
                "delta": delta,
                "ok": ok,
            }
            nrgb = "/".join(f"{v:.0f}" for v in nv)
            orgb = "/".join(f"{v:.0f}" for v in ov)
            print(f"{slug:26s} {host:7s} {app:6s} {name:9s} {nrgb:>11s} {orgb:>11s} {delta:7.1f}  {'ok' if ok else 'FAIL'}")
        results.append(cell)

    print(f"\nparity: {'PASS' if failures == 0 else f'FAIL ({failures} violations)'}")
    if json_out:
        json_out.write_text(json.dumps(results, indent=2))
    return 0 if failures == 0 else 1

if __name__ == "__main__":
    raise SystemExit(main())
