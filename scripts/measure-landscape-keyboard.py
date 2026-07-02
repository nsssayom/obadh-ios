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
            stack = [(int(x), y)]
            visited[y, x] = True
            min_x = max_x = int(x)
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
                    if 0 <= nx < width and 0 <= ny < height and mask[ny, nx] and not visited[ny, nx]:
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


def extract_key_rows(
    path: Path,
    from_fraction: float,
) -> tuple[int, int, list[list[Component]], tuple[int, int]]:
    image = Image.open(path).convert("RGB")
    pixels = np.array(image)
    height, width, _ = pixels.shape
    y_offset = int(height * from_fraction)
    sub = pixels[y_offset:]

    gray = sub.mean(axis=2)
    max_channel = sub.max(axis=2)
    min_channel = sub.min(axis=2)

    # iOS 26 landscape keys are translucent and often contain blurred wallpaper
    # colors. This wider saturation threshold catches native glass keys while
    # still excluding most text, icons, and app chrome.
    mask = (gray > 40) & (gray < 115) & ((max_channel - min_channel) < 48)

    key_components: list[Component] = []
    for component in components(mask, y_offset):
        fill = component.count / (component.width * component.height)
        if 90 <= component.width <= 460 and 55 <= component.height <= 150 and fill > 0.40:
            key_components.append(component)

    key_components = remove_contained_components(key_components)

    rows: list[list[Component]] = []
    row_centers: list[float] = []
    for component in sorted(key_components, key=lambda item: (item.y0, item.x0)):
        for index, center in enumerate(row_centers):
            if abs(center - component.center_y) < 70:
                rows[index].append(component)
                row_centers[index] = sum(item.center_y for item in rows[index]) / len(rows[index])
                break
        else:
            rows.append([component])
            row_centers.append(component.center_y)

    rows = [sorted(row, key=lambda item: item.x0) for row in rows if len(row) >= 3]
    rows.sort(key=lambda row: sum(item.center_y for item in row) / len(row))

    full_gray = pixels.mean(axis=2)
    active = (full_gray > 18) & (np.indices((height, width))[0] > int(height * from_fraction))
    active_ys = np.where(active.any(axis=1))[0]
    active_range = (int(active_ys.min()), int(active_ys.max())) if len(active_ys) else (0, 0)

    return width, height, rows, active_range


def summarize(label: str, path: Path, from_fraction: float) -> dict[str, object]:
    width, height, rows, active_range = extract_key_rows(path, from_fraction)
    print(f"\n{label}: {path}")
    print(f"image: {width}x{height}px")
    print(f"active y={active_range[0]}..{active_range[1]} height={active_range[1] - active_range[0] + 1}px")

    row_summaries = []
    for index, row in enumerate(rows, 1):
        widths = [item.width for item in row]
        heights = [item.height for item in row]
        gaps = [row[i + 1].x0 - row[i].x1 - 1 for i in range(len(row) - 1)]
        span = row[-1].x1 - row[0].x0 + 1
        center_y = sum(item.center_y for item in row) / len(row)
        print(
            f"row {index}: n={len(row)} y={center_y:.1f}px"
            f" x0={row[0].x0}px x1={row[-1].x1}px span={span}px"
        )
        print("  widths:", " ".join(str(value) for value in widths))
        print("  heights:", " ".join(str(value) for value in heights))
        print("  gaps:", " ".join(str(value) for value in gaps))
        row_summaries.append(
            {
                "count": len(row),
                "span": span,
                "x0": row[0].x0,
                "x1": row[-1].x1,
                "y": center_y,
                "avg_width": sum(widths) / len(widths),
                "avg_height": sum(heights) / len(heights),
                "avg_gap": sum(gaps) / len(gaps) if gaps else 0,
            }
        )
    return {"active_height": active_range[1] - active_range[0] + 1, "rows": row_summaries}


def compare(native: dict[str, object], candidate: dict[str, object]) -> None:
    print("\nDelta: candidate - native")
    print(f"active height: {candidate['active_height'] - native['active_height']:+.1f}px")
    native_rows = native["rows"]
    candidate_rows = candidate["rows"]
    assert isinstance(native_rows, list)
    assert isinstance(candidate_rows, list)
    for index, (base, current) in enumerate(zip(native_rows, candidate_rows), 1):
        print(
            f"row {index}:"
            f" n {current['count'] - base['count']:+.0f},"
            f" y {current['y'] - base['y']:+.1f}px,"
            f" span {current['span'] - base['span']:+.1f}px,"
            f" avg width {current['avg_width'] - base['avg_width']:+.1f}px,"
            f" avg height {current['avg_height'] - base['avg_height']:+.1f}px,"
            f" avg gap {current['avg_gap'] - base['avg_gap']:+.1f}px"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Measure landscape keyboard geometry from iOS screenshots. "
            "Use this with one native iOS keyboard screenshot and one Obadh "
            "screenshot captured from the same device/orientation."
        )
    )
    parser.add_argument("native", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument(
        "--from-fraction",
        type=float,
        default=0.48,
        help="image-height fraction where keyboard key detection starts",
    )
    args = parser.parse_args()

    native = summarize("native", args.native, args.from_fraction)
    candidate = summarize("candidate", args.candidate, args.from_fraction)
    compare(native, candidate)


if __name__ == "__main__":
    main()
