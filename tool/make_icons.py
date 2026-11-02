"""Draws Snooze's launcher icons and Play Store art.

Needs Pillow (`pip install pillow`) and the Flutter SDK's bundled fonts:
the Material Icons glyph "snooze" (an alarm clock with a z) and Roboto,
both Apache-2.0. Run from the project root:

    python3 tool/make_icons.py /path/to/flutter

Writes android/app/src/main/res/mipmap-*/ic_launcher*.png and
store/icon-512.png and store/feature-graphic.png.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FLUTTER = sys.argv[1] if len(sys.argv) > 1 else '/opt/homebrew/share/flutter'
FONTS = os.path.join(FLUTTER, 'bin/cache/artifacts/material_fonts')
ICONS = os.path.join(FONTS, 'MaterialIcons-Regular.otf')
GLYPH = chr(0xF01A1)  # Icons.snooze_rounded
BRAND = (0xF5, 0x79, 0x1A)  # AppColors.brand
DEEP = (0xB0, 0x51, 0x08)  # AppColors.primary
WHITE = (255, 255, 255)
RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def glyph(size_px, box_px, color=WHITE):
    """The glyph, centred in a transparent square of box_px."""
    img = Image.new('RGBA', (box_px, box_px), (0, 0, 0, 0))
    font = ImageFont.truetype(ICONS, size_px)
    left, top, right, bottom = font.getbbox(GLYPH)
    x = (box_px - (right - left)) / 2 - left
    y = (box_px - (bottom - top)) / 2 - top
    ImageDraw.Draw(img).text((x, y), GLYPH, font=font, fill=color)
    return img


def rounded_square(size, radius, color):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=color)
    return img


def write(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print('wrote', path, img.size)


# Adaptive icon (Android 8+): 108dp layers; keep the glyph in the 66dp
# safe zone so every mask shape (circle, squircle) shows all of it.
for name, scale in DENSITIES.items():
    layer = round(108 * scale)
    fg = glyph(round(layer * 0.50), layer)
    write(fg, f'{RES}/mipmap-{name}/ic_launcher_foreground.png')

# Legacy icon (Android 7): the whole 48dp icon, drawn as a rounded square.
for name, scale in DENSITIES.items():
    size = round(48 * scale)
    supersample = 4
    big = rounded_square(size * supersample, size * supersample * 0.22, BRAND)
    mark = glyph(round(size * supersample * 0.62), size * supersample)
    big.alpha_composite(mark)
    write(big.resize((size, size), Image.LANCZOS),
          f'{RES}/mipmap-{name}/ic_launcher.png')

# Play Store icon: 512x512, full bleed (Play applies its own mask).
icon = Image.new('RGBA', (512, 512), BRAND + (255,))
icon.alpha_composite(glyph(300, 512))
write(icon, 'store/icon-512.png')

# Feature graphic: 1024x500, no alpha. Text kept clear of the edges.
fg_w, fg_h = 1024, 500
art = Image.new('RGB', (fg_w, fg_h), BRAND)
draw = ImageDraw.Draw(art)
for x in range(fg_w):  # brand orange to the deeper text orange
    t = x / (fg_w - 1)
    c = tuple(round(BRAND[i] + (DEEP[i] - BRAND[i]) * t) for i in range(3))
    draw.line([(x, 0), (x, fg_h)], fill=c)
disc = 300
draw.ellipse((90, (fg_h - disc) // 2, 90 + disc, (fg_h + disc) // 2),
             fill=(255, 255, 255))
mark = glyph(190, disc, color=DEEP + (255,))
art.paste(mark, (90, (fg_h - disc) // 2), mark)
bold = ImageFont.truetype(os.path.join(FONTS, 'Roboto-Bold.ttf'), 112)
regular = ImageFont.truetype(os.path.join(FONTS, 'Roboto-Regular.ttf'), 40)
draw.text((450, 140), 'Snooze', font=bold, fill=WHITE)
draw.text((454, 285), 'Reminders that ring like an', font=regular, fill=WHITE)
draw.text((454, 335), 'alarm until you answer them.', font=regular,
          fill=WHITE)
write(art, 'store/feature-graphic.png')
