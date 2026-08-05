#!/usr/bin/env python3
"""Render the v0.11 distance-driven ground/window locomotion preview."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("resources", type=Path)
    parser.add_argument("gif_output", type=Path)
    parser.add_argument("contact_output", type=Path)
    return parser.parse_args()


def clip(root: Path, directory: str, prefix: str) -> list[Image.Image]:
    return [
        Image.open(root / directory / f"{prefix}_{index:02d}.png").convert("RGBA")
        for index in range(8)
    ]


def progressive(frames: list[Image.Image], progress: float) -> Image.Image:
    value = max(0.0, min(progress, 1.0))
    return frames[min(7, int(value * 8))]


def locomotion(frames: list[Image.Image], distance: float, stride: float) -> Image.Image:
    phase = (distance / stride) % 1
    return frames[min(7, int(phase * 8))]


def timed_frame(
    frames: list[Image.Image], elapsed: float, durations: tuple[float, ...]
) -> Image.Image:
    local = elapsed % sum(durations)
    for index, duration in enumerate(durations):
        if local < duration:
            return frames[index]
        local -= duration
    return frames[0]


def ease(value: float) -> float:
    value = max(0.0, min(value, 1.0))
    return value * value * (3 - 2 * value)


def ui_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    path = Path("/System/Library/Fonts/Hiragino Sans GB.ttc")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


class Renderer:
    def __init__(self, resources: Path) -> None:
        self.idle = clip(resources, "PixelSpritesV9Idle", "douhua_pixel_v9_idle")
        self.walk = clip(resources, "PixelSpritesV9Walk", "douhua_pixel_v9_walk")
        self.run = clip(resources, "PixelSpritesV9Run", "douhua_pixel_v9_run")
        self.jump = clip(resources, "PixelSpritesV9Jump", "douhua_pixel_v9_jump")
        self.settle = clip(
            resources,
            "PixelSpritesV11WindowSettle",
            "douhua_pixel_v11_window_settle",
        )
        self.perch = clip(
            resources,
            "PixelSpritesV11WindowPerch",
            "douhua_pixel_v11_window_perch",
        )
        self.title_font = ui_font(18)
        self.stage_font = ui_font(15)
        self.note_font = ui_font(13)
        self.ground_y = 352.0
        self.first_window = (150.0, 156.0, 430.0, 174.0)
        self.second_window = (510.0, 92.0, 190.0, 188.0)

    def background(self) -> Image.Image:
        canvas = Image.new("RGB", (720, 405), (231, 237, 244))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, self.ground_y + 1, 720, 405), fill=(210, 217, 224))
        for x, y, width, height in (self.first_window, self.second_window):
            draw.rounded_rectangle(
                (x, y, x + width, y + height),
                radius=9,
                fill=(250, 250, 250),
                outline=(112, 122, 134),
                width=2,
            )
            draw.line((x + 1, y + 23, x + width - 1, y + 23), fill=(205, 210, 218), width=2)
            for offset, color in ((0, (244, 98, 93)), (15, (244, 190, 72)), (30, (93, 201, 102))):
                draw.ellipse((x + 10 + offset, y + 7, x + 18 + offset, y + 15), fill=color)
        draw.text((18, 15), "豆花 v0.11 · 位移驱动的自主漫游", font=self.title_font, fill=(49, 56, 64))
        draw.text(
            (18, 40),
            "真实模式：每次动作后会安静 12–22 秒；此预览缩短等待便于验收",
            font=self.note_font,
            fill=(92, 102, 112),
        )
        return canvas

    def render(self, time: float) -> Image.Image:
        canvas = self.background()
        draw = ImageDraw.Draw(canvas)
        sprite = self.idle[0]
        x = 70.0
        contact_y = self.ground_y
        facing = 1
        stage = "长时间安静观察"

        ground_walk_end_x = 70 + 16 * 5
        ground_run_end_x = ground_walk_end_x + 42 * 1.1
        first_target_x = self.first_window[0] + 155
        second_target_x = self.second_window[0] + 40

        if time < 3:
            sprite = timed_frame(
                self.idle,
                time,
                (1.4, 0.7, 0.7, 0.7, 1.8, 0.28, 0.22, 0.45),
            )
        elif time < 8:
            distance = 16 * (time - 3)
            x += distance
            sprite = locomotion(self.walk, distance, 28)
            stage = "地面慢走 16 pt/s · 每 28 pt 一个完整步态"
        elif time < 11:
            x = ground_walk_end_x
            sprite = timed_frame(
                self.idle,
                time - 8,
                (1.4, 0.7, 0.7, 0.7, 1.8, 0.28, 0.22, 0.45),
            )
            stage = "动作后停下观察"
        elif time < 12.1:
            distance = 42 * (time - 11)
            x = ground_walk_end_x + distance
            sprite = locomotion(self.run, distance, 40)
            stage = "低频短跑 42 pt/s · 腿速随位移同步"
        elif time < 13.2:
            p = (time - 12.1) / 1.1
            smooth = ease(p)
            x = ground_run_end_x + (first_target_x - ground_run_end_x) * smooth
            contact_y = self.ground_y + (self.first_window[1] - self.ground_y) * smooth - 62 * 4 * p * (1 - p)
            sprite = progressive(self.jump, p)
            stage = "偶尔跳上可见窗口"
        elif time < 14.48:
            x = first_target_x
            contact_y = self.first_window[1]
            sprite = progressive(self.settle, (time - 13.2) / 1.28)
            stage = "落地缓冲后坐稳"
        elif time < 17:
            x = first_target_x
            contact_y = self.first_window[1]
            sprite = timed_frame(
                self.perch,
                time - 14.48,
                (1.15, 0.72, 0.62, 0.44, 0.34, 0.58, 0.76, 1.05),
            )
            stage = "窗口顶边安静驻留"
        elif time < 23:
            distance = 12 * (time - 17)
            x = first_target_x + distance
            contact_y = self.first_window[1]
            sprite = locomotion(self.walk, distance, 28)
            stage = "沿窗口慢走 12 pt/s · 窗口移动不改变步频"
        elif time < 24.28:
            x = first_target_x + 72
            contact_y = self.first_window[1]
            sprite = progressive(self.settle, (time - 23) / 1.28)
            stage = "先收步站稳，再坐下"
        elif time < 25.56:
            x = first_target_x + 72
            contact_y = self.first_window[1]
            sprite = progressive(self.settle, 1 - (time - 24.28) / 1.28)
            stage = "低频跨窗口行动：先起身"
        elif time < 26.66:
            p = (time - 25.56) / 1.1
            smooth = ease(p)
            start_x = first_target_x + 72
            x = start_x + (second_target_x - start_x) * smooth
            contact_y = self.first_window[1] + (self.second_window[1] - self.first_window[1]) * smooth - 46 * 4 * p * (1 - p)
            facing = 1 if second_target_x >= start_x else -1
            sprite = progressive(self.jump, p)
            stage = "跳到另一个窗口"
        elif time < 27.94:
            x = second_target_x
            contact_y = self.second_window[1]
            sprite = progressive(self.settle, (time - 26.66) / 1.28)
            stage = "第二个窗口落座"
        else:
            x = second_target_x
            contact_y = self.second_window[1]
            sprite = timed_frame(
                self.perch,
                time - 27.94,
                (1.15, 0.72, 0.62, 0.44, 0.34, 0.58, 0.76, 1.05),
            )
            stage = "再次安静观察"

        draw.text((18, 65), stage, font=self.stage_font, fill=(73, 83, 94))
        if facing < 0:
            sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        canvas.paste(sprite, (round(x), round(contact_y - 56)), sprite)
        return canvas


def make_contact(renderer: Renderer, output: Path) -> None:
    samples = (
        (1.5, "安静"),
        (5.5, "地面慢走"),
        (11.6, "短跑"),
        (13.7, "窗口落座"),
        (20.0, "窗口慢走"),
        (26.1, "跨窗口跳跃"),
    )
    cell_w, cell_h = 360, 226
    sheet = Image.new("RGB", (cell_w * 2, cell_h * 3), (28, 31, 35))
    draw = ImageDraw.Draw(sheet)
    label_font = ui_font(15)
    for index, (time, label) in enumerate(samples):
        image = renderer.render(time).resize((342, 192), Image.Resampling.LANCZOS)
        x = (index % 2) * cell_w + 9
        y = (index // 2) * cell_h + 8
        sheet.paste(image, (x, y))
        draw.text((x, y + 196), label, font=label_font, fill=(236, 236, 232))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)


def main() -> None:
    args = arguments()
    renderer = Renderer(args.resources)
    fps = 16
    frames = [renderer.render(index / fps) for index in range(30 * fps)]
    args.gif_output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        args.gif_output,
        save_all=True,
        append_images=frames[1:],
        duration=round(1000 / fps),
        loop=0,
        optimize=False,
        disposal=2,
    )
    make_contact(renderer, args.contact_output)
    print(f"Rendered {len(frames)} frames to {args.gif_output}")
    print(f"Rendered contact sheet to {args.contact_output}")


if __name__ == "__main__":
    main()
