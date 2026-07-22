#!/usr/bin/env python3
"""Generate a pixel-art bitmap font (.fnt + .png) for Godot 4.7."""

import argparse
from PIL import Image, ImageDraw, ImageFont

GLYPH_W = 8
GLYPH_H = 8
GLYPH_COLS = 16
CHARS = [chr(i) for i in range(32, 127)]  # ASCII printable


def generate_font(output_stem: str, font_path: str | None, font_size: int) -> None:
    """Render each glyph onto an atlas and write BMFont-compatible .fnt."""
    if font_path:
        font = ImageFont.truetype(font_path, font_size)
    else:
        font = ImageFont.load_default()

    rows = (len(CHARS) + GLYPH_COLS - 1) // GLYPH_COLS
    atlas_w = GLYPH_COLS * GLYPH_W
    atlas_h = rows * GLYPH_H
    atlas = Image.new("L", (atlas_w, atlas_h), 0)
    draw = ImageDraw.Draw(atlas)

    lines = []
    lines.append(f'info face="PixelFont" size={GLYPH_H} bold=0 italic=0 charset=""')
    lines.append(f'common lineHeight={GLYPH_H} base={GLYPH_H - 1} scaleW={atlas_w} scaleH={atlas_h} pages=1')
    lines.append(f'page id=0 file="{output_stem}_0.png"')
    lines.append(f'chars count={len(CHARS)}')

    for idx, ch in enumerate(CHARS):
        col = idx % GLYPH_COLS
        row = idx // GLYPH_COLS
        x = col * GLYPH_W
        y = row * GLYPH_H
        draw.text((x, y), ch, fill=255, font=font)
        lines.append(f'char id={ord(ch)} x={x} y={y} width={GLYPH_W} height={GLYPH_H} xoffset=0 yoffset=0 xadvance={GLYPH_W} page=0 chnl=15')

    atlas.save(f"{output_stem}_0.png")
    with open(f"{output_stem}.fnt", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Generated: {output_stem}.fnt + {output_stem}_0.png ({atlas_w}x{atlas_h})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate pixel-art bitmap font")
    parser.add_argument("--output", default="assets/fonts/pixel_font", help="Output stem path")
    parser.add_argument("--font", help="Path to TTF/OTF font to rasterize (default: PIL default)")
    parser.add_argument("--size", type=int, default=8, help="Font size in pixels (default: 8)")
    args = parser.parse_args()
    generate_font(args.output, args.font, args.size)
