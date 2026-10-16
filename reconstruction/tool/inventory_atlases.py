#!/usr/bin/env python3
"""Create inspection grids and bitmap-font inventory; no inferred animations."""
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'assets/manifest.json').read_text())
image_entries = [a for a in manifest['assets'] if 'image' in a]
font_entries = [a for a in manifest['assets'] if 'font' in a]
selected = [a for a in image_entries if max(a['image']['width'], a['image']['height']) >= 512 and min(a['image']['width'], a['image']['height']) >= 256]
output_dir = root / 'docs/atlas-inspection'
output_dir.mkdir(parents=True, exist_ok=True)
entries = []
for asset in selected:
    path = root / asset['output']
    rgba = Image.open(path).convert('RGBA')
    checker = Image.new('RGB', rgba.size, 'white')
    draw = ImageDraw.Draw(checker)
    for y in range(0, rgba.height, 16):
        for x in range(0, rgba.width, 16):
            if ((x//16) + (y//16)) % 2:
                draw.rectangle((x,y,x+15,y+15), fill='#dddddd')
    checker.paste(rgba, (0,0), rgba)
    grid = ImageDraw.Draw(checker)
    kitten = path.name in ('classic_atlas.png', 'grey_kitten.png', 'red_kitten.png', 'siam_kitten.png')
    cell_w, cell_h = (85,80) if kitten else (64,64)
    for x in range(0, rgba.width, cell_w):
        grid.line((x,0,x,rgba.height), fill='#ff0080', width=1)
        grid.text((x+2,1), str(x), fill='#800040', stroke_width=1, stroke_fill='white')
    for y in range(0, rgba.height, cell_h):
        grid.line((0,y,rgba.width,y), fill='#ff0080', width=1)
        grid.text((1,y+12), str(y), fill='#800040', stroke_width=1, stroke_fill='white')
    output = output_dir / path.name
    checker.save(output)
    item = {'image': asset['output'], 'width': rgba.width, 'height': rgba.height,
            'inspection_grid': str(output.relative_to(root)),
            'grid_cell_width': cell_w, 'grid_cell_height': cell_h,
            'grid_kind': 'native setupWithImage cell dimensions' if kitten else 'coordinate reference only; not sprite metadata'}
    if kitten:
        count = 61 if path.name == 'classic_atlas.png' else 73
        item['frame_rect_evidence'] = 'Native setupWithImage evidence reported by renderer analysis; x=85*(index%12), y=80*(index//12). Indices are not timing metadata.'
        item['frames'] = [{'index': i, 'rect': [85*(i%12),80*(i//12),85,80]} for i in range(count)]
    entries.append(item)
fonts = []
for asset in font_entries:
    text = (root / asset['output']).read_text()
    chars = []
    for line in text.splitlines():
        if line.startswith('char '):
            chars.append({key:int(value) for key,value in re.findall(r'(\w+)=(-?\d+)',line)})
    fonts.append({'metadata':asset['output'], 'info':text.splitlines()[0],
                  'common':text.splitlines()[1],
                  'atlas': 'assets/images/' + re.search(r'page .*file="([^"]+)"',text).group(1),
                  'glyphs':chars})
result = {'notice':'All inspection coordinates are top-left PNG pixels. Only 85x80 kitten cells have compiled-native evidence; generic grid lines must not be treated as sprite boundaries or animation frames.',
          'atlases': entries, 'bitmap_fonts':fonts}
(root/'docs/atlas-inventory.json').write_text(json.dumps(result,indent=2)+'\n')
print(f'Created {len(entries)} atlas inspection grids and inventory for {len(fonts)} bitmap fonts.')
