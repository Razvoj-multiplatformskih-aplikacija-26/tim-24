"""Draw Hedrion's code-native geometric H mark for the platform runners."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]

def mark(size: int) -> Image.Image:
    scale = 4
    image = Image.new('RGBA', (size * scale, size * scale), '#0c101b')
    draw = ImageDraw.Draw(image)
    def polygon(points, color):
        draw.polygon([(round(x * size * scale), round(y * size * scale)) for x, y in points], fill=color)
    polygon([(.23,.24),(.40,.17),(.40,.43),(.60,.35),(.60,.23),(.77,.16),(.77,.73),(.60,.81),(.60,.56),(.40,.64),(.40,.78),(.23,.85)], '#b39bff')
    polygon([(.40,.43),(.60,.35),(.60,.56),(.40,.64)], '#6d9bff')
    return image.resize((size, size), Image.Resampling.LANCZOS)

for app in ('mobile', 'backoffice'):
    web = ROOT / 'apps' / app / 'web'
    mark(32).save(web / 'favicon.png')
    for size in (192,512):
        for suffix in ('', '-maskable'):
            mark(size).save(web / 'icons' / f'Icon{suffix}-{size}.png')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    mark(size).save(ROOT / 'apps/mobile/android/app/src/main/res' / f'mipmap-{density}' / 'ic_launcher.png')
mark(256).save(ROOT / 'apps/backoffice/windows/runner/resources/app_icon.ico', sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
