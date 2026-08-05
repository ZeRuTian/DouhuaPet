#!/usr/bin/env python3
"""Validate geometry and transition registration for v0.10 window sprites."""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops


CLIPS = {
    "window-settle": ("PixelSpritesV11WindowSettle", "douhua_pixel_v11_window_settle"),
    "window-perch": ("PixelSpritesV11WindowPerch", "douhua_pixel_v11_window_perch"),
    "window-tap": ("PixelSpritesV11WindowTap", "douhua_pixel_v11_window_tap"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resources", type=Path)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args()


def interior_holes(alpha: Image.Image) -> list[int]:
    width, height = alpha.size
    transparent = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if alpha.getpixel((x, y)) == 0
    }
    holes: list[int] = []
    while transparent:
        seed = transparent.pop()
        queue = deque([seed])
        size = 0
        edge = False
        while queue:
            x, y = queue.popleft()
            size += 1
            edge = edge or x in (0, width - 1) or y in (0, height - 1)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                point = (nx, ny)
                if point in transparent:
                    transparent.remove(point)
                    queue.append(point)
        if not edge:
            holes.append(size)
    return sorted(holes, reverse=True)


def bbox_shape(box: tuple[int, int, int, int]) -> tuple[int, int, float]:
    left, top, right, bottom = box
    return right - left, bottom - top, (left + right) * 0.5


def main() -> None:
    args = parse_args()
    errors: list[str] = []
    warnings: list[str] = []
    report: dict[str, object] = {"clips": {}}
    loaded: dict[str, list[Image.Image]] = {}

    for clip, (directory, prefix) in CLIPS.items():
        paths = sorted((args.resources / directory).glob(f"{prefix}_*.png"))
        if len(paths) != 8:
            errors.append(f"{clip}: expected 8 frames, found {len(paths)}")
            continue
        frames = [Image.open(path).convert("RGBA") for path in paths]
        loaded[clip] = frames
        boxes: list[tuple[int, int, int, int]] = []
        clip_holes: list[list[int]] = []
        for index, frame in enumerate(frames):
            if frame.size != (200, 120):
                errors.append(f"{clip}/{index:02d}: size is {frame.size}, expected 200x120")
            alpha = frame.getchannel("A")
            box = alpha.getbbox()
            if box is None:
                errors.append(f"{clip}/{index:02d}: empty frame")
                continue
            boxes.append(box)
            if box[3] != 112:
                errors.append(f"{clip}/{index:02d}: baseline is {box[3]}, expected 112")
            if any(
                alpha.crop(edge).getbbox() is not None
                for edge in ((0, 0, 200, 1), (0, 119, 200, 120), (0, 0, 1, 120), (199, 0, 200, 120))
            ):
                errors.append(f"{clip}/{index:02d}: visible pixels touch a canvas edge")
            holes = interior_holes(alpha)
            clip_holes.append(holes)
            if holes and holes[0] > 6:
                errors.append(f"{clip}/{index:02d}: enclosed alpha hole has {holes[0]} pixels")

        centers = [bbox_shape(box)[2] for box in boxes]
        if clip in ("window-perch", "window-tap") and centers:
            drift = max(centers) - min(centers)
            if drift > 3:
                errors.append(f"{clip}: horizontal registration drifts {drift:.1f}px")
        report["clips"][clip] = {
            "frames": len(frames),
            "bounds": boxes,
            "center_range": (min(centers), max(centers)) if centers else None,
            "largest_interior_hole": max((max(h) for h in clip_holes if h), default=0),
        }

    transitions = [
        ("settle-to-perch", "window-settle", 7, "window-perch", 0),
        ("perch-to-tap", "window-perch", 0, "window-tap", 0),
        ("tap-to-perch", "window-tap", 7, "window-perch", 0),
    ]
    transition_report: dict[str, object] = {}
    for label, left_clip, left_index, right_clip, right_index in transitions:
        if left_clip not in loaded or right_clip not in loaded:
            continue
        left = loaded[left_clip][left_index]
        right = loaded[right_clip][right_index]
        left_box = left.getchannel("A").getbbox()
        right_box = right.getchannel("A").getbbox()
        assert left_box is not None and right_box is not None
        lw, lh, lc = bbox_shape(left_box)
        rw, rh, rc = bbox_shape(right_box)
        alpha_difference = ImageChops.difference(
            left.getchannel("A"), right.getchannel("A")
        )
        diff_ratio = sum(alpha_difference.get_flattened_data()) / (255 * 200 * 120)
        transition_report[label] = {
            "left_bounds": left_box,
            "right_bounds": right_box,
            "alpha_difference_ratio": round(diff_ratio, 6),
        }
        if abs(lw - rw) > 3 or abs(lh - rh) > 3 or abs(lc - rc) > 2:
            errors.append(
                f"{label}: geometry jumps from {left_box} to {right_box}"
            )
        if diff_ratio > 0.025:
            warnings.append(f"{label}: alpha difference ratio is {diff_ratio:.4f}")

    report["transitions"] = transition_report
    report["errors"] = errors
    report["warnings"] = warnings
    report["ok"] = not errors
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
