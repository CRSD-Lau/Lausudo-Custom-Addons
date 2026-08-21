"""Create a 1024x128 transparent TGA atlas from the included OFL font."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "packages" / "addons" / "CrispFCT" / "fonts" / "PTSansNarrow-Bold.ttf"
OUTPUT = ROOT / "packages" / "addons" / "CrispFCT" / "media" / "CrispFCTGlyphs.tga"
GLYPHS = "0123456789.KMB!-"
CELL_WIDTH, HEIGHT = 64, 128

image = Image.new("RGBA", (1024, HEIGHT), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
font = ImageFont.truetype(str(FONT), 82)
for index, glyph in enumerate(GLYPHS):
    left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font, stroke_width=1)
    width, height = right - left, bottom - top
    x = index * CELL_WIDTH + (CELL_WIDTH - width) // 2 - left
    y = (HEIGHT - height) // 2 - top - 2
    draw.text((x, y), glyph, font=font, fill=(255, 255, 255, 255), stroke_width=1, stroke_fill=(0, 0, 0, 255))

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUTPUT)
print(OUTPUT)
