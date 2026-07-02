#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class Component:
    x0: int
    y0: int
    x1: int
    y1: int
    count: int

    @property
    def width(self) -> int:
        return self.x1 - self.x0 + 1

    @property
    def height(self) -> int:
        return self.y1 - self.y0 + 1

    @property
    def center_y(self) -> float:
        return (self.y0 + self.y1) / 2


def components(mask: np.ndarray, y_offset: int) -> list[Component]:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    out: list[Component] = []

    for y in range(height):
        for x in np.where(mask[y] & ~visited[y])[0]:
            if visited[y, x] or not mask[y, x]:
                continue
            stack = [(x, y)]
            visited[y, x] = True
            min_x = max_x = x
            min_y = max_y = y
            count = 0
            while stack:
                cx, cy = stack.pop()
                count += 1
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height and not visited[ny, nx] and mask[ny, nx]:
                        visited[ny, nx] = True
                        stack.append((nx, ny))
            out.append(Component(min_x, min_y + y_offset, max_x, max_y + y_offset, count))
    return out


def remove_contained_components(items: list[Component]) -> list[Component]:
    out: list[Component] = []
    for item in items:
        is_inside_larger_component = False
        for other in items:
            if item is other:
                continue
            if other.width <= item.width or other.height <= item.height:
                continue
            if (
                item.x0 >= other.x0
                and item.y0 >= other.y0
                and item.x1 <= other.x1
                and item.y1 <= other.y1
            ):
                is_inside_larger_component = True
                break
        if not is_inside_larger_component:
            out.append(item)
    return out


def extract_rows(
    path: Path,
    from_fraction: float,
) -> tuple[int, int, list[list[Component]], tuple[int, int]]:
    image = Image.open(path).convert("RGB")
    pixels = np.array(image)
    height, width, _ = pixels.shape
    y_offset = int(height * from_fraction)
    sub = pixels[y_offset:]

    max_channel = sub.max(axis=2)
    min_channel = sub.min(axis=2)
    gray = sub.mean(axis=2)
    # iOS 26 keyboard keys are translucent gray surfaces over a glass
    # backdrop. The useful signal is the key interior brightness, not a fixed
    # opaque key color. Keep the saturation bound wide enough for blurred
    # wallpaper bleed, but exclude white glyphs and dark backdrop.
    mask = (gray >= 50) & (gray <= 120) & ((max_channel - min_channel) <= 32)

    key_components: list[Component] = []
    for component in components(mask, y_offset):
        fill = component.count / (component.width * component.height)
        if 35 <= component.width <= 900 and 25 <= component.height <= 220 and fill > 0.35:
            key_components.append(component)

    rows: list[list[Component]] = []
    row_centers: list[float] = []
    key_components = remove_contained_components(key_components)

    for component in sorted(key_components, key=lambda item: (item.y0, item.x0)):
        for index, center in enumerate(row_centers):
            if abs(center - component.center_y) < 55:
                rows[index].append(component)
                row_centers[index] = sum(item.center_y for item in rows[index]) / len(rows[index])
                break
        else:
            rows.append([component])
            row_centers.append(component.center_y)

    rows = [sorted(row, key=lambda item: item.x0) for row in rows if len(row) >= 3]
    rows.sort(key=lambda row: sum(item.center_y for item in row) / len(row))

    full_gray = pixels.mean(axis=2)
    y_index = np.indices((height, width))[0]
    active = (full_gray > 18) & (y_index > int(height * from_fraction))
    active_ys = np.where(active.any(axis=1))[0]
    active_range = (int(active_ys.min()), int(active_ys.max())) if len(active_ys) else (0, 0)

    return width, height, rows, active_range


def summarize(label: str, path: Path, scale: float | None, logical_width: float, from_fraction: float) -> dict[str, object]:
    width, height, rows, active_range = extract_rows(path, from_fraction)
    effective_scale = scale or (width / logical_width)
    print(f"\n{label}: {path}")
    print(f"image: {width}x{height}px scale={effective_scale:g}")
    active_height = active_range[1] - active_range[0] + 1
    print(
        "active bottom visual:"
        f" y={active_range[0]}..{active_range[1]}"
        f" height={active_height}px/{active_height / effective_scale:.2f}pt"
    )

    result_rows = []
    for index, row in enumerate(rows, 1):
        y_center = sum(item.center_y for item in row) / len(row)
        widths = [item.width / effective_scale for item in row]
        heights = [item.height / effective_scale for item in row]
        gaps = [
            (row[i + 1].x0 - row[i].x1 - 1) / effective_scale
            for i in range(len(row) - 1)
        ]
        span = (row[-1].x1 - row[0].x0 + 1) / effective_scale
        print(
            f"row {index}: n={len(row)}"
            f" y={y_center / effective_scale:.2f}pt"
            f" x0={row[0].x0 / effective_scale:.2f}pt"
            f" x1={row[-1].x1 / effective_scale:.2f}pt"
            f" span={span:.2f}pt"
        )
        print("  widths:", " ".join(f"{value:.2f}" for value in widths))
        print("  heights:", " ".join(f"{value:.2f}" for value in heights))
        print("  gaps:", " ".join(f"{value:.2f}" for value in gaps))
        result_rows.append(
            {
                "widths": widths,
                "heights": heights,
                "gaps": gaps,
                "span": span,
                "x0": row[0].x0 / effective_scale,
                "x1": row[-1].x1 / effective_scale,
                "y": y_center / effective_scale,
            }
        )

    return {"active_height": active_height / effective_scale, "rows": result_rows}


def compare(native: dict[str, object], candidate: dict[str, object]) -> None:
    print("\nDelta: candidate - native")
    print(f"active height: {candidate['active_height'] - native['active_height']:.2f}pt")
    native_rows = native["rows"]
    candidate_rows = candidate["rows"]
    assert isinstance(native_rows, list)
    assert isinstance(candidate_rows, list)
    for index, (base, current) in enumerate(zip(native_rows, candidate_rows), 1):
        base_h = sum(base["heights"]) / len(base["heights"])
        current_h = sum(current["heights"]) / len(current["heights"])
        base_w = sum(base["widths"]) / len(base["widths"])
        current_w = sum(current["widths"]) / len(current["widths"])
        base_gap = sum(base["gaps"]) / len(base["gaps"]) if base["gaps"] else 0
        current_gap = sum(current["gaps"]) / len(current["gaps"]) if current["gaps"] else 0
        print(
            f"row {index}:"
            f" y {current['y'] - base['y']:+.2f}pt,"
            f" height {current_h - base_h:+.2f}pt,"
            f" avg width {current_w - base_w:+.2f}pt,"
            f" avg gap {current_gap - base_gap:+.2f}pt,"
            f" span {current['span'] - base['span']:+.2f}pt"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("native", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--scale", type=float)
    parser.add_argument(
        "--logical-width",
        type=float,
        default=440,
        help="logical screen width used when --scale is omitted",
    )
    parser.add_argument(
        "--from-fraction",
        type=float,
        default=0.48,
        help="image-height fraction where keyboard key detection starts",
    )
    args = parser.parse_args()

    native = summarize("native", args.native, args.scale, args.logical_width, args.from_fraction)
    candidate = summarize("candidate", args.candidate, args.scale, args.logical_width, args.from_fraction)
    compare(native, candidate)


if __name__ == "__main__":
    main()
