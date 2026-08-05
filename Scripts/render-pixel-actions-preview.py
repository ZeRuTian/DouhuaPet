#!/usr/bin/env python3
"""Render the current behavior reel with the same distance-driven gait math as the app."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resources", type=Path)
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def load_clip(directory: Path, prefix: str, count: int = 8) -> list[Image.Image]:
    return [
        Image.open(directory / f"{prefix}_{index:02d}.png").convert("RGBA")
        for index in range(count)
    ]


def frame_for_phase(frames: list[Image.Image], phase: float) -> Image.Image:
    wrapped = phase - math.floor(phase)
    return frames[min(len(frames) - 1, int(wrapped * len(frames)))]


def action_index(progress: float, dialogue: bool) -> int:
    thresholds = (0.16, 0.34, 0.56) if dialogue else (0.18, 0.36, 0.72)
    if progress < thresholds[0]:
        return 0
    if progress < thresholds[1]:
        return 1
    if progress < thresholds[2]:
        return 2
    return 3


def jump_index(progress: float, frame_count: int) -> int:
    return min(frame_count - 1, int(max(0.0, min(progress, 1.0)) * frame_count))


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = Path("/System/Library/Fonts/Hiragino Sans GB.ttc")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def main() -> None:
    args = parse_args()
    idle = load_clip(args.resources / "PixelSpritesV9Idle", "douhua_pixel_v9_idle")
    walk = load_clip(args.resources / "PixelSpritesV9Walk", "douhua_pixel_v9_walk")
    run = load_clip(args.resources / "PixelSpritesV9Run", "douhua_pixel_v9_run")
    jump = load_clip(args.resources / "PixelSpritesV9Jump", "douhua_pixel_v9_jump")
    actions = load_clip(args.resources / "PixelSpritesV9JumpDialog", "douhua_pixel_v9_action")

    fps = 30
    seconds = 10.2
    x = 72.0
    gait_phase = 0.0
    ground_y = 286
    label_font = font(20)
    bubble_font = font(22)
    output_frames: list[Image.Image] = []

    for frame_number in range(round(fps * seconds)):
        time = frame_number / fps
        canvas = Image.new("RGB", (960, 360), (237, 232, 222))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, ground_y + 1, 960, 359), fill=(222, 214, 199))
        draw.text((22, 18), "豆花 v0.8.1 · 闲置身份锁 / 八帧跳跃 / 位移步态", font=label_font, fill=(54, 50, 45))

        sprite = idle[0]
        lift = 0.0
        bubble = False
        stage = "安静观察"

        if time < 1.2:
            sprite = idle[0]
        elif time < 4.2:
            stage = "慢走 22 pt/s · 22 pt/步态周期"
            distance = 22 * (1 / fps)
            x += distance * 2
            gait_phase = (gait_phase + distance / 22) % 1
            sprite = frame_for_phase(walk, gait_phase)
        elif time < 5.5:
            stage = "短跑 66 pt/s · 34 pt/步态周期"
            distance = 66 * (1 / fps)
            x += distance * 2
            gait_phase = (gait_phase + distance / 34) % 1
            sprite = frame_for_phase(run, gait_phase)
        elif time < 6.28:
            stage = "预压 → 蹬地 → 腾空 → 落地"
            progress = (time - 5.5) / 0.78
            smooth = progress * progress * (3 - 2 * progress)
            x += (28 * 2 * (6 * progress * (1 - progress)) / 0.78) / fps
            lift = 4 * 26 * progress * (1 - progress) * 2
            sprite = jump[jump_index(progress, len(jump))]
        elif time < 6.9:
            stage = "落地停顿"
            sprite = idle[0]
        elif time < 10.1:
            stage = "发现 → 抬头 → 抬爪 → 回应"
            progress = (time - 6.9) / 3.2
            sprite = actions[4 + action_index(progress, dialogue=True)]
            bubble = 0.12 <= progress < 0.9

        draw.text((22, 54), stage, font=label_font, fill=(91, 82, 70))
        sprite_x = round(x)
        sprite_y = round(ground_y - 112 - lift)
        canvas.paste(sprite, (sprite_x, sprite_y), sprite)

        if bubble:
            bubble_rect = (sprite_x + 38, sprite_y - 43, sprite_x + 180, sprite_y + 2)
            draw.rounded_rectangle(
                bubble_rect,
                radius=12,
                fill=(255, 255, 255),
                outline=(75, 70, 65),
                width=2,
            )
            draw.polygon(
                ((sprite_x + 92, sprite_y + 1), (sprite_x + 104, sprite_y + 1), (sprite_x + 98, sprite_y + 9)),
                fill=(255, 255, 255),
            )
            draw.text((sprite_x + 83, sprite_y - 36), "嗯？", font=bubble_font, fill=(32, 30, 28))

        output_frames.append(canvas)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output_frames[0].save(
        args.output,
        save_all=True,
        append_images=output_frames[1:],
        duration=round(1000 / fps),
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(f"Rendered {len(output_frames)} frames to {args.output}")


if __name__ == "__main__":
    main()
