"""Generate the Nivara launcher icon.

Design: a civic-blue field with a white map-pin (place) whose head carries a
blue verification check (proof). "Your City. Your Proof." in one mark. Renders
at 4x then downsamples for clean antialiased edges.

Outputs:
  nivara_icon.png            full square icon (blue bg + white pin + blue check)
  nivara_icon_foreground.png adaptive foreground (white pin only, transparent),
                             sized to sit inside the adaptive safe zone over the
                             blue adaptive background.
"""
import math
from PIL import Image, ImageDraw

BLUE = (27, 108, 168, 255)      # #1B6CA8 civic blue
BLUE_DARK = (18, 77, 119, 255)  # #124D77 gradient foot
WHITE = (255, 255, 255, 255)
AMBER = (245, 166, 35, 255)     # #F5A623 accent

SS = 4          # supersample factor
OUT = 1024      # final size
S = OUT * SS


def draw_pin(draw, cx, cy_head, R, tip_y, fill, check_color, check_ratio=1.0):
    """Draw a teardrop pin with a check in its head."""
    # Head circle.
    draw.ellipse([cx - R, cy_head - R, cx + R, cy_head + R], fill=fill)
    # Lower triangle down to the tip (tangent-ish for a smooth teardrop).
    a = math.radians(38)
    px = R * math.cos(a)
    py = R * math.sin(a)
    draw.polygon(
        [(cx - px, cy_head + py), (cx + px, cy_head + py), (cx, tip_y)],
        fill=fill,
    )

    # Verification check inside the head.
    w = int(R * 0.22 * check_ratio)
    scale = R * 0.62
    p1 = (cx - scale * 0.55, cy_head + scale * 0.05)
    p2 = (cx - scale * 0.12, cy_head + scale * 0.5)
    p3 = (cx + scale * 0.62, cy_head - scale * 0.42)
    draw.line([p1, p2, p3], fill=check_color, width=w, joint="curve")
    # Round the check's end caps.
    for p in (p1, p2, p3):
        draw.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2],
                     fill=check_color)


def full_icon():
    img = Image.new("RGBA", (S, S), BLUE)
    # Subtle vertical gradient toward a darker foot.
    top = BLUE
    bot = BLUE_DARK
    grad = Image.new("RGBA", (1, S))
    gd = grad.load()
    for y in range(S):
        t = y / (S - 1)
        gd[0, y] = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(4))
    img = grad.resize((S, S))

    draw = ImageDraw.Draw(img)
    R = int(S * 0.235)
    cx = S // 2
    cy_head = int(S * 0.40)
    tip_y = int(S * 0.80)
    # White pin with an amber ring behind the head for a touch of brand warmth.
    draw.ellipse([cx - R * 1.14, cy_head - R * 1.14,
                  cx + R * 1.14, cy_head + R * 1.14], fill=None)
    draw_pin(draw, cx, cy_head, R, tip_y, WHITE, BLUE)
    # Small amber dot at the tip base for polish.
    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save("assets/icon/nivara_icon.png")


def foreground():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Keep the pin inside the adaptive safe zone (~center 66%).
    R = int(S * 0.185)
    cx = S // 2
    cy_head = int(S * 0.44)
    tip_y = int(S * 0.70)
    draw_pin(draw, cx, cy_head, R, tip_y, WHITE, BLUE)
    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save("assets/icon/nivara_icon_foreground.png")


if __name__ == "__main__":
    full_icon()
    foreground()
    print("icons written")
