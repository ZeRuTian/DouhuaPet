#!/usr/bin/env python3
"""Render v0.10 window-interaction contact sheet and motion preview."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resources", type=Path)
    parser.add_argument("gif_output", type=Path)
    parser.add_argument("contact_output", type=Path)
    return parser.parse_args()


def load_clip(directory: Path, prefix: str) -> list[Image.Image]:
    return [
        Image.open(directory / f"{prefix}_{index:02d}.png").convert("RGBA")
        for index in range(8)
    ]


def progressive(frames: list[Image.Image], progress: float) -> Image.Image:
    value = max(0.0, min(progress, 1.0))
    return frames[min(len(frames) - 1, int(value * len(frames)))]


def perch_frame(frames: list[Image.Image], elapsed: float) -> Image.Image:
    durations = (1.15, 0.72, 0.62, 0.44, 0.34, 0.58, 0.76, 1.05)
    local = elapsed % sum(durations)
    for index, duration in enumerate(durations):
        if local < duration:
            return frames[index]
        local -= duration
    return frames[0]


def ease(value: float) -> float:
    value = max(0.0, min(value, 1.0))
    return value * value * (3 - 2 * value)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = Path("/System/Library/Fonts/Hiragino Sans GB.ttc")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def window_x(time: float) -> float:
    if time < 4.1:
        return 190
    if time < 5.7:
        return 190 + 105 * ease((time - 4.1) / 1.6)
    return 295


def make_contact(
    clips: list[tuple[str, list[Image.Image]]],
    output: Path,
) -> None:
    scale = 0.5
    cell_width, cell_height = 105, 72
    canvas = Image.new("RGB", (8 * cell_width + 110, 3 * cell_height + 34), (26, 29, 31))
    draw = ImageDraw.Draw(canvas)
    label_font = font(15)
    for row, (label, frames) in enumerate(clips):
        draw.text((10, 22 + row * cell_height), label, font=label_font, fill=(232, 232, 228))
        for column, frame in enumerate(frames):
            sprite = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.NEAREST)
            x = 100 + column * cell_width
            y = 8 + row * cell_height
            canvas.paste(sprite, (x, y), sprite)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)


def main() -> None:
    args = parse_args()
    jump = load_clip(args.resources / "PixelSpritesV9Jump", "douhua_pixel_v9_jump")
    settle = load_clip(
        args.resources / "PixelSpritesV11WindowSettle",
        "douhua_pixel_v11_window_settle",
    )
    perch = load_clip(
        args.resources / "PixelSpritesV11WindowPerch",
        "douhua_pixel_v11_window_perch",
    )
    tap = load_clip(
        args.resources / "PixelSpritesV11WindowTap",
        "douhua_pixel_v11_window_tap",
    )
    make_contact([("落座", settle), ("驻留", perch), ("拍边缘", tap)], args.contact_output)

    fps = 24
    seconds = 14
    title_font = font(20)
    stage_font = font(17)
    output_frames: list[Image.Image] = []
    ground_y = 468.0
    window_top = 188.0
    cat_ground_x = 88.0

    for frame_number in range(round(fps * seconds)):
        time = frame_number / fps
        wx = window_x(time)
        window_width = 580
        canvas = Image.new("RGB", (960, 540), (231, 237, 244))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, ground_y + 1, 960, 539), fill=(210, 217, 224))
        draw.rounded_rectangle(
            (wx, window_top, wx + window_width, window_top + 252),
            radius=11,
            fill=(250, 250, 250),
            outline=(112, 122, 134),
            width=2,
        )
        draw.rectangle((wx + 1, window_top + 25, wx + window_width - 1, window_top + 26), fill=(205, 210, 218))
        for offset, color in ((0, (244, 98, 93)), (18, (244, 190, 72)), (36, (93, 201, 102))):
            draw.ellipse((wx + 12 + offset, window_top + 8, wx + 22 + offset, window_top + 18), fill=color)
        draw.text((22, 18), "豆花 v0.10 · 真实窗口边缘互动", font=title_font, fill=(49, 56, 64))

        perch_center_x = wx + window_width * 0.34
        sprite = perch[0]
        cat_x = cat_ground_x
        contact_y = ground_y
        stage = "地面观察"
        if time < 1.0:
            sprite = jump[0]
        elif time < 2.05:
            p = (time - 1.0) / 1.05
            smooth = ease(p)
            cat_x = cat_ground_x + (perch_center_x - 50 - cat_ground_x) * smooth
            contact_y = ground_y + (window_top - ground_y) * smooth - 82 * 4 * p * (1 - p)
            sprite = progressive(jump, p)
            stage = "跳上最前方窗口"
        elif time < 3.33:
            cat_x = perch_center_x - 50
            contact_y = window_top
            sprite = progressive(settle, (time - 2.05) / 1.28)
            stage = "缓冲落地，屈后腿坐稳"
        elif time < 6.5:
            cat_x = perch_center_x - 50
            contact_y = window_top
            sprite = perch_frame(perch, time - 3.33)
            stage = "随窗口移动，身体保持稳定"
        elif time < 8.05:
            cat_x = perch_center_x - 50
            contact_y = window_top
            sprite = progressive(tap, (time - 6.5) / 1.55)
            stage = "点击豆花：低头、抬爪、拍边缘"
        elif time < 10.0:
            cat_x = perch_center_x - 50
            contact_y = window_top
            sprite = perch_frame(perch, time - 8.05)
            stage = "继续安静观察"
        elif time < 11.28:
            cat_x = perch_center_x - 50
            contact_y = window_top
            sprite = progressive(settle, 1 - (time - 10.0) / 1.28)
            stage = "窗口关闭：先自然起身"
        elif time < 12.38:
            p = (time - 11.28) / 1.1
            smooth = ease(p)
            start_x = perch_center_x - 50
            cat_x = start_x + (520 - start_x) * smooth
            contact_y = window_top + (ground_y - window_top) * smooth - 66 * 4 * p * (1 - p)
            sprite = progressive(jump, p)
            stage = "跳回地面"
        else:
            cat_x = 520
            contact_y = ground_y
            sprite = jump[0]
            stage = "安全回到地面"

        draw.text((22, 53), stage, font=stage_font, fill=(86, 96, 107))
        sprite = sprite.resize((100, 60), Image.Resampling.NEAREST)
        canvas.paste(sprite, (round(cat_x), round(contact_y - 56)), sprite)
        output_frames.append(canvas)

    args.gif_output.parent.mkdir(parents=True, exist_ok=True)
    output_frames[0].save(
        args.gif_output,
        save_all=True,
        append_images=output_frames[1:],
        duration=round(1000 / fps),
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(f"Rendered {len(output_frames)} frames to {args.gif_output}")
    print(f"Rendered contact sheet to {args.contact_output}")


if __name__ == "__main__":
    main()
