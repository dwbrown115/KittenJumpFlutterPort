#!/usr/bin/env python3
"""Independent Pillow validation and an unbundled inspection contact sheet."""

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "assets/manifest.json").read_text())
images = [asset for asset in manifest["assets"] if "image" in asset]
columns, cell_width, cell_height = 8, 150, 140
sheet = Image.new("RGB", (columns * cell_width, ((len(images) + columns - 1) // columns) * cell_height), "#e6e6e6")
draw = ImageDraw.Draw(sheet)
for index, asset in enumerate(images):
    path = root / asset["output"]
    with Image.open(path) as original:
        original.load()
        rgba = original.convert("RGBA")
        if rgba.size != (asset["image"]["width"], asset["image"]["height"]):
            raise ValueError(f"Pillow dimensions differ: {path}")
        if hashlib.sha256(rgba.tobytes()).hexdigest() != asset["image"]["output_straight_rgba_sha256"]:
            raise ValueError(f"Pillow pixels differ: {path}")
        rgba.thumbnail((cell_width - 10, cell_height - 25), Image.Resampling.NEAREST)
    left, top = (index % columns) * cell_width, (index // columns) * cell_height
    tile_size = 10
    for x in range(left, left + cell_width, tile_size):
        for y in range(top, top + cell_height - 20, tile_size):
            color = "#ffffff" if ((x - left) // tile_size + (y - top) // tile_size) % 2 else "#d9d9d9"
            draw.rectangle((x, y, x + tile_size - 1, y + tile_size - 1), fill=color)
    sheet.paste(rgba, (left + (cell_width - rgba.width) // 2, top + (cell_height - 25 - rgba.height) // 2), rgba)
    draw.text((left + 5, top + cell_height - 18), path.name, fill="black")
destination = root / "docs/assets-preview.png"
destination.parent.mkdir(parents=True, exist_ok=True)
sheet.save(destination)
print(f"Pillow independently verified all {len(images)} converted PNGs; preview: {destination}")
