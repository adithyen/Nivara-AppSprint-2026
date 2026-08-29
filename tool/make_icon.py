"""Generate the Nivara launcher icon with loading screen gradient effect.

Design: The signature Nivara map-pin mark with verification check in the head,
infused with the loading screen's glowing emerald-to-cyan gradient:
- Start color: #00E676 (Emerald Green)
- End color:   #00B0FF (Vivid Cyan Blue)
- Background:  #0A0F18 (Cyber-Civic Dark Canvas) with soft radial ambient glow.
- Verification Check: #0A0F18 (Dark) for crisp, high-contrast readability.

Outputs:
  assets/icon/nivara_icon.png            full square icon (dark bg + glowing gradient pin)
  assets/icon/nivara_icon_foreground.png adaptive foreground (gradient pin with transparent bg)
"""
import math
from PIL import Image, ImageDraw, ImageFilter

GREEN = (0, 230, 118, 255)    # #00E676 (Loading screen emerald)
CYAN = (0, 176, 255, 255)     # #00B0FF (Loading screen vivid cyan)
BG_DARK = (10, 15, 24, 255)   # #0A0F18 (Deep dark canvas)
CHECK_DARK = (10, 15, 24, 255)# #0A0F18

SS = 4          # supersample factor
OUT = 1024      # final size
S = OUT * SS


def create_gradient_image(width, height, c1, c2):
    """Creates a diagonal linear gradient from top-left (c1) to bottom-right (c2)."""
    img = Image.new("RGBA", (width, height))
    pixels = img.load()
    max_dist = math.sqrt(width**2 + height**2)
    for y in range(height):
        for x in range(width):
            t = (x + y) / (width + height)
            r = int(c1[0] + (c2[0] - c1[0]) * t)
            g = int(c1[1] + (c2[1] - c1[1]) * t)
            b = int(c1[2] + (c2[2] - c1[2]) * t)
            a = int(c1[3] + (c2[3] - c1[3]) * t)
            pixels[x, y] = (r, g, b, a)
    return img


def draw_pin_mask(size, cx, cy_head, R, tip_y):
    """Generates an 8-bit mask of the teardrop pin shape."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    # Head circle
    draw.ellipse([cx - R, cy_head - R, cx + R, cy_head + R], fill=255)
    # Teardrop body
    a = math.radians(38)
    px = R * math.cos(a)
    py = R * math.sin(a)
    draw.polygon(
        [(cx - px, cy_head + py), (cx + px, cy_head + py), (cx, tip_y)],
        fill=255,
    )
    return mask


def draw_check(draw, cx, cy_head, R, check_color, check_ratio=1.0):
    """Draws the verification checkmark inside the pin head."""
    w = int(R * 0.22 * check_ratio)
    scale = R * 0.62
    p1 = (cx - scale * 0.55, cy_head + scale * 0.05)
    p2 = (cx - scale * 0.12, cy_head + scale * 0.5)
    p3 = (cx + scale * 0.62, cy_head - scale * 0.42)
    draw.line([p1, p2, p3], fill=check_color, width=w, joint="curve")
    for p in (p1, p2, p3):
        draw.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2],
                     fill=check_color)


def full_icon():
    # 1. Dark canvas with subtle diagonal gradient & radial glow
    img = Image.new("RGBA", (S, S), BG_DARK)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    cx = S // 2
    cy_head = int(S * 0.40)
    tip_y = int(S * 0.80)
    R = int(S * 0.235)

    # Ambient neon radial glow behind the pin
    glow_R = int(R * 2.2)
    glow_draw.ellipse(
        [cx - glow_R, cy_head - glow_R // 2, cx + glow_R, cy_head + int(glow_R * 1.5)],
        fill=(0, 230, 118, 45),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=int(S * 0.06)))
    img = Image.alpha_composite(img, glow)

    # 2. Render Gradient Pin
    grad = create_gradient_image(S, S, GREEN, CYAN)
    pin_mask = draw_pin_mask(S, cx, cy_head, R, tip_y)

    # Add soft outer drop shadow for depth
    shadow_mask = pin_mask.filter(ImageFilter.GaussianBlur(radius=int(S * 0.02)))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 120))
    img.paste(shadow, (0, int(S * 0.015)), shadow_mask)

    # Paste gradient using pin mask
    img.paste(grad, (0, 0), pin_mask)

    # 3. Draw verification check inside the head
    draw = ImageDraw.Draw(img)
    draw_check(draw, cx, cy_head, R, CHECK_DARK)

    # Downsample with Lanczos antialiasing
    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save("assets/icon/nivara_icon.png")


def foreground():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = S // 2
    cy_head = int(S * 0.44)
    tip_y = int(S * 0.70)
    R = int(S * 0.185)

    # Gradient pin for adaptive icon
    grad = create_gradient_image(S, S, GREEN, CYAN)
    pin_mask = draw_pin_mask(S, cx, cy_head, R, tip_y)

    # Subtle drop shadow
    shadow_mask = pin_mask.filter(ImageFilter.GaussianBlur(radius=int(S * 0.015)))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 100))
    img.paste(shadow, (0, int(S * 0.01)), shadow_mask)

    img.paste(grad, (0, 0), pin_mask)

    draw = ImageDraw.Draw(img)
    draw_check(draw, cx, cy_head, R, CHECK_DARK)

    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save("assets/icon/nivara_icon_foreground.png")


if __name__ == "__main__":
    full_icon()
    foreground()
    print("Nivara gradient launcher icons generated successfully.")
