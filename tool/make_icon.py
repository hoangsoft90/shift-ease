#!/usr/bin/env python3
"""ShiftEase app icon generator (PIL-only, no ImageMagick needed).

Design: deep-blue rounded-rect background with a subtle radial glow, a white
calendar card, and a "shift turn" arrow (S-curve arrow through the card) that
says "shift rotation" at a glance. Also emits a foreground-only PNG for the
Android adaptive icon (safe-zone padding) and 1024px iOS AppIcon source.

Outputs (1024x1024):
  shiftease_icon.png            — full-bleed icon (launcher + iOS source)
  shiftease_icon_foreground.png — transparent-bg foreground for adaptive icon
"""
import math

from PIL import Image, ImageDraw

S = 1024
FG_MARGIN = 120  # adaptive foreground safe zone: content within ~76% center

BG_TOP = (33, 66, 111)      # #21426F deep blue
BG_BOT = (30, 58, 95)       # #1E3A5F
GLOW = (58, 110, 175)       # radial highlight center
CARD = (255, 255, 255)
CARD_SHADOW = (16, 32, 56)
HEADER = (214, 84, 72)       # shift "day" accent
ARROW = (33, 66, 111)        # arrow drawn in bg blue on the white card
DOTS = (176, 190, 210)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def radial_gradient(size, inner, outer, cx, cy, r_inner=0.0, r_outer=None):
    """Return an RGB image of a radial gradient (elliptical, stretched 1.25x)."""
    if r_outer is None:
        r_outer = size * 0.75
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            dx = (x - cx) / 1.25
            dy = y - cy
            d = math.hypot(dx, dy)
            if d <= r_inner:
                t = 0.0
            elif d >= r_outer:
                t = 1.0
            else:
                t = (d - r_inner) / (r_outer - r_inner)
            t = t * t * (3 - 2 * t)  # smoothstep
            px[x, y] = lerp(inner, outer, t)
    return img


def rotated(draw, img, center, angle, op):
    tmp = Image.new("RGBA", img.size, (0, 0, 0, 0))
    op(tmp)
    tmp = tmp.rotate(angle, resample=Image.BICUBIC, center=(img.width / 2, img.height / 2))
    draw._image.paste(tmp, center, tmp)  # noqa: SLF001


def s_curve_arrow(img, box, color, width):
    """S-curve (shift-turn) arrow with a triangular head, drawn on RGBA img."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    d = ImageDraw.Draw(img)
    pts = []
    steps = 160
    for i in range(steps + 1):
        t = i / steps
        # Vertical S: two half-waves; horizontal drift toward the right side
        x = x0 + w * (0.62 + 0.32 * math.sin(t * math.pi))
        y = y0 + h * t
        pts.append((x, y))
    d.line(pts, fill=color, width=width, joint="curve")
    # Arrowhead at the bottom, pointing down-left along the curve end tangent
    hx, hy = pts[-1]
    tx, ty = pts[-1][0] - pts[-8][0], pts[-1][1] - pts[-8][1]
    n = math.hypot(tx, ty)
    ux, uy = tx / n, ty / n
    size = width * 2.6
    p1 = (hx + ux * size, hy + uy * size)
    p2 = (hx - uy * size * 0.62, hy + ux * size * 0.62)
    p3 = (hx + uy * size * 0.62, hy - ux * size * 0.62)
    d.polygon([p1, p2, p3], fill=color)


def draw_foreground(size):
    """Calendar card + shift-turn arrow, centered in `size`x`size` transparent."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / S

    # Card shadow
    sh = 26 * s
    d.rounded_rectangle(
        [250 * s + sh, 214 * s + sh, 774 * s + sh, 810 * s + sh],
        radius=64 * s, fill=CARD_SHADOW + (110,),
    )
    # White calendar card
    d.rounded_rectangle([250 * s, 214 * s, 774 * s, 810 * s], radius=64 * s, fill=CARD)
    # Header band (rounded top corners only — overlay a square bottom half)
    d.rounded_rectangle([250 * s, 214 * s, 774 * s, 384 * s], radius=64 * s, fill=HEADER)
    d.rectangle([250 * s, 324 * s, 774 * s, 384 * s], fill=HEADER)
    # Binder rings
    for rx in (352 * s, 672 * s):
        d.rounded_rectangle([rx - 18 * s, 160 * s, rx + 18 * s, 252 * s], radius=18 * s, fill=CARD_SHADOW + (200,))

    # Shift-turn arrow (the S-curve) inside the card body
    s_curve_arrow(img, (370 * s, 430 * s, 480 * s, 740 * s), ARROW, int(58 * s))

    # Week dots on the right of the arrow
    for i, dy in enumerate((-70, 0, 70)):
        filled = i == 1
        col = ARROW if filled else DOTS
        r = 30 * s if filled else 24 * s
        cx, cy = 640 * s, 585 * s + dy * s
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    return img


def main():
    # 1) Full-bleed launcher/iOS icon: gradient bg + foreground
    bg = radial_gradient(S, GLOW, BG_BOT, S * 0.38, S * 0.30, 0, S * 0.95)
    d = ImageDraw.Draw(bg)
    d.rounded_rectangle([0, 0, S - 1, S - 1], radius=0)
    fg = draw_foreground(S)
    full = bg.convert("RGBA")
    full.alpha_composite(fg)
    # Rounded-square mask (classic launcher look pre-adaptive)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S, S], radius=int(S * 0.18), fill=255)
    rgba = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rgba.paste(full, (0, 0), mask)
    rgba.save("assets/icon/shiftease_icon.png")

    # 2) Adaptive foreground: same art, more margin
    fgpad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner = draw_foreground(S - 2 * FG_MARGIN)
    fgpad.paste(inner, (FG_MARGIN, FG_MARGIN), inner)
    fgpad.save("assets/icon/shiftease_icon_foreground.png")

    print("wrote assets/icon/shiftease_icon.png + shiftease_icon_foreground.png")


if __name__ == "__main__":
    main()
