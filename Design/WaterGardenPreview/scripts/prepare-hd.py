"""Encode Real-ESRGAN outputs and make honest, unscaled detail crops.

AI inference is external Real-ESRGAN, not this script. No interpolation upscale.
Run: python scripts/prepare-hd.py /path/to/realesrgan-output-directory
"""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('input', type=Path)
args = parser.parse_args()
assets = ROOT / 'dist/assets'
review = ROOT / 'review/hd'
review.mkdir(parents=True, exist_ok=True)
manifest = {'method': 'image_gen detail restoration, then Real-ESRGAN realesrgan-x4plus 4x', 'layers': {}}
for name in ['far', 'midground', 'foreground']:
    source = args.input / f'{name}-4x.png'
    with Image.open(source) as image:
        assert image.size == (6144, 4096), (name, image.size)
        assert name == 'far' or image.mode == 'RGBA', (name, image.mode)
        target = assets / f'{name}-hd.webp'
        # High quality RGB; WebP alpha is lossless. No extra sharpen or artificial grain.
        image.save(target, 'WEBP', quality=94, method=6, exact=True)
        with Image.open(ROOT / f'art/hd-source/{name}.png') as preview:
            preview.save(assets / f'{name}-preview.webp', 'WEBP', quality=86, method=6, exact=True)
        manifest['layers'][name] = {'width': image.width, 'height': image.height,
            'bytes': target.stat().st_size, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'alpha': 'A' in image.getbands()}
        if name == 'midground':
            # Exactly 768x768 source pixels. View at 100%, never resize this QA crop.
            image.crop((2850, 2330, 3618, 3098)).save(review / 'midground-detail-1to1.png')
        if name == 'foreground':
            image.crop((400, 250, 1168, 1018)).save(review / 'leaf-detail-1to1.png')
(review / 'assets.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(manifest, ensure_ascii=False, indent=2))
