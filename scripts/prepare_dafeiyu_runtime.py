"""Mechanically resize approved originals for the existing 86 x 129 UI.

No artwork generation, retouching, background removal or original overwrite.
The app already decoded originals at width 256; ship that size directly.
"""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'mobile/assets/dafeiyu'
TARGET = SOURCE / 'runtime'
TARGET.mkdir(exist_ok=True)
records = []
for source in sorted(SOURCE.glob('*.png')):
    with Image.open(source) as original:
        image = original.convert('RGBA')
        height = round(image.height * 256 / image.width)
        image = image.resize((256, height), Image.Resampling.LANCZOS)
        destination = TARGET / source.name
        image.save(destination, optimize=True)
        records.append({'file': source.name, 'originalBytes': source.stat().st_size,
                        'runtimeBytes': destination.stat().st_size,
                        'width': 256, 'height': height})
assert len(records) == 8
print(json.dumps(records, ensure_ascii=False, indent=2))
