#!/usr/bin/env python3
"""Play Store asset generator (PIL-only).

Outputs (store_assets/):
  icon.png           512x512  — downscaled from the app's master icon
  feature_graphic.png 1024x500 — gradient bg + big icon left + wordmark right

Design per chplay.md §3: gradient #1E3A5F → #2C5282, white "ShiftEase"
wordmark, tagline "Work Shift Calendar & Income Estimator", faint
calendar-cell motifs bottom-right. No "Install now" text (store rule).
"""
from PIL import Image, ImageDraw, ImageFont
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, 'store_assets')
os.makedirs(OUT, exist_ok=True)

TOP = (30, 58, 95)      # #1E3A5F
BOT = (44, 82, 130)     # #2C5282
WHITE = (255, 255, 255)


def vgrad(w: int, h: int, top, bot) -> Image.Image:
    im = Image.new('RGB', (w, h))
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return im


def find_font(size: int):
    for p in (
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
        '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
    ):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# ---- 1. icon.png: 512x512 straight downscale of the master icon ----------
src = Image.open(os.path.join(ROOT, 'assets/icon/shiftease_icon.png')).convert('RGBA')
icon512 = src.resize((512, 512), Image.LANCZOS)
icon512.save(os.path.join(OUT, 'icon.png'), optimize=True)
print('icon.png', icon512.size)

# ---- 2. feature_graphic.png 1024x500 --------------------------------------
W, H = 1024, 500
fg = vgrad(W, H, TOP, BOT).convert('RGBA')

# faint calendar-cell motif bottom-right (7x3 grid of rounded cells)
cell = Image.new('RGBA', (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(cell)
cw, ch, gap = 64, 44, 10
x0 = W - 7 * (cw + gap) - 40
y0 = H - 3 * (ch + gap) - 34
for row in range(3):
    for col in range(7):
        x = x0 + col * (cw + gap)
        y = y0 + row * (ch + gap)
        cd.rounded_rectangle([x, y, x + cw, y + ch], radius=8,
                             outline=(255, 255, 255, 38), width=2)
        if row == 0 and col in (1, 4):
            cd.rounded_rectangle([x + 14, y + 12, x + cw - 14, y + ch - 12],
                                 radius=5, fill=(255, 255, 255, 34))
fg.alpha_composite(cell)

# app icon, large, left side (drop shadow for separation)
big = src.resize((300, 300), Image.LANCZOS)
shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([52, 122, 52 + 300 + 18, 122 + 300 + 18], radius=44,
                     fill=(0, 0, 0, 90))
shadow = shadow.filter(__import__('PIL.ImageFilter', fromlist=['GaussianBlur'])
                       .GaussianBlur(14))
fg.alpha_composite(shadow)
fg.alpha_composite(big, (62, 100))

# wordmark + tagline, right side
d = ImageDraw.Draw(fg)
f_title = find_font(96)
f_tag = find_font(30)
tx = 408
d.text((tx, 168), 'ShiftEase', font=f_title, fill=WHITE)
tw = d.textlength('ShiftEase', font=f_title)
d.rounded_rectangle([tx, 288, tx + tw, 296], radius=4, fill=(255, 255, 255, 200))
d.text((tx, 316), 'Work Shift Calendar & Income Estimator',
       font=f_tag, fill=(255, 255, 255, 230))
fg.convert('RGB').save(os.path.join(OUT, 'feature_graphic.png'), optimize=True)
print('feature_graphic.png', fg.size)
