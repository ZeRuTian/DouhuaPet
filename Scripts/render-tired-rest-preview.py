#!/usr/bin/env python3
"""Render the v0.9 run-fatigue-rest interaction using the app's timings."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resources", type=Path)
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def load_clip(directory: Path, prefix: str) -> list[Image.Image]:
    return [
        Image.open(directory / f"{prefix}_{index:02d}.png").convert("RGBA")
        for index in range(8)
    ]


def progressive(frames: list[Image.Image], progress: float) -> Image.Image:
    value = max(0.0, min(progress, 1.0))
    return frames[min(len(frames) - 1, int(value * len(frames)))]


def loop_frame(frames: list[Image.Image], elapsed: float) -> Image.Image:
    durations = (1.3, 0.8, 0.8, 0.7, 0.55, 0.5, 0.75, 1.0)
    local = elapsed % sum(durations)
    for index, duration in enumerate(durations):
        if local < duration:
            return frames[index]
        local -= duration
    return frames[0]


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = Path("/System/Library/Fonts/Hiragino Sans GB.ttc")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def main() -> None:
    args = parse_args()
    idle = load_clip(args.resources / "PixelSpritesV9Idle", "douhua_pixel_v9_idle")
    run = load_clip(args.resources / "PixelSpritesV9Run", "douhua_pixel_v9_run")
    tired = load_clip(args.resources / "PixelSpritesV10TiredDown", "douhua_pixel_v10_tired_down")
    rest = load_clip(args.resources / "PixelSpritesV10Rest", "douhua_pixel_v10_rest")
    reaction = load_clip(
        args.resources / "PixelSpritesV10RestReaction",
        "douhua_pixel_v10_rest_reaction",
    )

    fps = 30
    seconds = 16.0
    x = 96.0
    gait_phase = 0.0
    ground_y = 286
    title_font = font(20)
    output_frames: list[Image.Image] = []

    for frame_number in range(round(fps * seconds)):
        time = frame_number / fps
        canvas = Image.new("RGB", (960, 360), (237, 232, 222))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, ground_y + 1, 960, 359), fill=(222, 214, 199))
        draw.text((22, 18), "豆花 v0.9 · 跑累 → 伏地 → 休息 → 点击侧翻 → 起身", font=title_font, fill=(54, 50, 45))

        sprite = idle[0]
        stage = "安静观察"
        if time < 1.0:
            sprite = idle[0]
        elif time < 4.0:
            stage = "短跑消耗体力，落脚后减速"
            distance = 66 / fps
            x += distance * 1.7
            gait_phase = (gait_phase + distance / 34) % 1
            sprite = run[min(7, int(gait_phase * 8))]
        elif time < 5.45:
            stage = "低头、屈肢、胸口落地"
            sprite = progressive(tired, (time - 4.0) / 1.45)
        elif time < 8.7:
            stage = "香箱休息：慢呼吸与慢眨眼"
            sprite = loop_frame(rest, time - 5.45)
        elif time < 10.55:
            stage = "点击互动：懒洋洋侧翻、露腹、抬爪"
            sprite = progressive(reaction, (time - 8.7) / 1.85)
        elif time < 13.7:
            stage = "继续伏卧恢复体力"
            sprite = loop_frame(rest, time - 10.55)
        elif time < 15.15:
            stage = "反向关节序列自然起身"
            sprite = progressive(tired, 1 - (time - 13.7) / 1.45)
        else:
            stage = "恢复观察"
            sprite = idle[0]

        draw.text((22, 54), stage, font=title_font, fill=(91, 82, 70))
        canvas.paste(sprite, (round(x), ground_y - 112), sprite)
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
