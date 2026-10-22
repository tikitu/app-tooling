#!/usr/bin/env -S uv run --locked --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==11.3.0"]
# ///
#
# make-scratch-icon.py — derive a scratch build's app icon from the real one.
#
# Imported by peru from app-tooling's pattern `scratch-look`
# (https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look).
# Never edit it here: the change belongs in app-tooling, and
# `make app-tooling-check` fails while this copy differs.
#
# Usage: scripts/make-scratch-icon.py <AppIcon.appiconset> <AppIcon-Scratch.appiconset>
#
# Copies the icon set and draws a yellow-and-black caution band across the
# lower right corner of every image, with "SCRATCH" on it where the image is
# big enough to read. A build on scratch data then cannot be mistaken for
# the real app in the Dock, the app switcher or the home screen.
#
# It reads any .appiconset. Rerun it whenever the real icon changes, and
# commit the output; the build does not run it. Pillow is pinned here and
# locked in make-scratch-icon.py.lock beside it (`--locked` refuses to run
# if the two disagree; `uv lock --script` updates the lock).
import json
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BAND_YELLOW = (250, 204, 21, 255)
STRIPE_BLACK = (24, 24, 27, 255)
# Below this many pixels the word is a smudge; the stripes alone say it.
MIN_SIZE_FOR_TEXT = 128
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFCompact.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
]


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                f = ImageFont.truetype(path, size)
                try:
                    f.set_variation_by_name("Bold")
                except (OSError, ValueError, AttributeError):
                    pass
                return f
            except OSError:
                continue
    return ImageFont.load_default(size)


def band(size: int) -> Image.Image:
    """The band, drawn horizontally on a canvas twice the icon's size, to be
    rotated 45° and laid over the icon's lower right corner."""
    canvas = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    # Thicker when small, so the band still reads in a menu or a Dock tile.
    height = max(4, round(size * (0.22 if size >= MIN_SIZE_FOR_TEXT else 0.34)))
    top = size - height // 2
    draw.rectangle([0, top, size * 2, top + height], fill=BAND_YELLOW)

    edge = max(1, round(height * 0.16))
    stripe = max(2, round(height * 0.5))
    for edge_top in (top, top + height - edge):
        for x in range(-stripe, size * 2 + stripe, stripe * 2):
            draw.polygon(
                [
                    (x, edge_top + edge),
                    (x + stripe, edge_top + edge),
                    (x + stripe * 2, edge_top),
                    (x + stripe, edge_top),
                ],
                fill=STRIPE_BLACK,
            )

    if size >= MIN_SIZE_FOR_TEXT:
        text_font = font(round((height - 2 * edge) * 0.72))
        draw.text(
            (size, top + height / 2),
            "SCRATCH",
            font=text_font,
            fill=STRIPE_BLACK,
            anchor="mm",
        )
    return canvas


def mark(image: Image.Image) -> Image.Image:
    size = image.width
    overlay = band(size).rotate(45, resample=Image.BICUBIC)
    # The rotated canvas is centred on the icon's centre; shift it so the
    # band crosses the lower right corner.
    offset = round(size * (0.3 if size >= MIN_SIZE_FOR_TEXT else 0.24))
    placed = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    placed.paste(overlay, (-size // 2 + offset, -size // 2 + offset), overlay)
    return Image.alpha_composite(image.convert("RGBA"), placed)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__ or "", file=sys.stderr)
        print("usage: make-scratch-icon.py <source.appiconset> <dest.appiconset>", file=sys.stderr)
        return 2
    source, dest = Path(sys.argv[1]), Path(sys.argv[2])
    contents = source / "Contents.json"
    if not contents.is_file():
        print(f"✗ no Contents.json in {source}", file=sys.stderr)
        return 1
    if dest.resolve() == source.resolve():
        print("✗ the destination must differ from the source", file=sys.stderr)
        return 1

    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    shutil.copy2(contents, dest / "Contents.json")

    names = {i["filename"] for i in json.loads(contents.read_text())["images"] if "filename" in i}
    for name in sorted(names):
        with Image.open(source / name) as image:
            if image.width != image.height:
                print(f"✗ {name} is not square", file=sys.stderr)
                return 1
            mark(image).save(dest / name)
        print(f"  {dest / name}")
    print(f"✓ {len(names)} images in {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
