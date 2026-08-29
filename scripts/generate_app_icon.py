import math
from PIL import Image, ImageDraw, ImageFilter

def create_gradient_circle(size=(1024, 1024), is_adaptive_foreground=False):
    # Base image
    img = Image.new("RGBA", size, (0, 0, 0, 0) if is_adaptive_foreground else (10, 15, 24, 255))
    draw = ImageDraw.Draw(img)
    
    w, h = size
    cx, cy = w // 2, h // 2
    
    # Radius for circle (Safe zone is 66% of adaptive icon, so diameter ~ 520px for 1024x1024)
    r = int(w * 0.28) if is_adaptive_foreground else int(w * 0.38)
    
    # Outer Glow layer (for full icon)
    if not is_adaptive_foreground:
        glow = Image.new("RGBA", size, (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        glow_r = int(r * 1.25)
        for gr in range(glow_r, r, -2):
            alpha = int(45 * (1.0 - (gr - r) / (glow_r - r)))
            glow_draw.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=(0, 230, 118, alpha))
        glow = glow.filter(ImageFilter.GaussianBlur(18))
        img = Image.alpha_composite(img, glow)
        draw = ImageDraw.Draw(img)
    
    # Create linear gradient mask
    gradient_img = Image.new("RGBA", (r * 2, r * 2))
    # Diagonal gradient from top-left (0, 230, 118) to bottom-right (0, 176, 255)
    c1 = (0, 230, 118)
    c2 = (0, 176, 255)
    
    for y in range(r * 2):
        for x in range(r * 2):
            dx = x - r
            dy = y - r
            if dx*dx + dy*dy <= r*r:
                # Diagonal factor [0..1]
                t = (x + y) / (4.0 * r)
                t = max(0.0, min(1.0, t))
                red = int(c1[0] * (1 - t) + c2[0] * t)
                green = int(c1[1] * (1 - t) + c2[1] * t)
                blue = int(c1[2] * (1 - t) + c2[2] * t)
                gradient_img.putpixel((x, y), (red, green, blue, 255))
    
    # Paste circular gradient badge onto base image
    img.paste(gradient_img, (cx - r, cy - r), gradient_img)
    
    # Draw Location City Emblem in Center (solid black #080C14 with smooth curves)
    emblem = Image.new("RGBA", size, (0, 0, 0, 0))
    edraw = ImageDraw.Draw(emblem)
    
    eb_color = (8, 12, 20, 255) # Deep black
    window_color = (0, 230, 118, 255) # Subtle glowing window accents
    
    # Scale emblem relative to r
    ew = r * 1.15
    eh = r * 1.15
    
    # Left building
    lb_w = ew * 0.30
    lb_h = eh * 0.65
    lb_x = cx - ew * 0.46
    lb_y = cy + eh * 0.40 - lb_h
    edraw.rounded_rectangle([lb_x, lb_y, lb_x + lb_w, cy + eh * 0.40], radius=int(lb_w*0.22), fill=eb_color)
    
    # Center tallest tower
    cb_w = ew * 0.36
    cb_h = eh * 0.90
    cb_x = cx - cb_w / 2
    cb_y = cy + eh * 0.40 - cb_h
    edraw.rounded_rectangle([cb_x, cb_y, cb_x + cb_w, cy + eh * 0.40], radius=int(cb_w*0.20), fill=eb_color)
    
    # Right building
    rb_w = ew * 0.30
    rb_h = eh * 0.50
    rb_x = cx + ew * 0.16
    rb_y = cy + eh * 0.40 - rb_h
    edraw.rounded_rectangle([rb_x, rb_y, rb_x + rb_w, cy + eh * 0.40], radius=int(rb_w*0.22), fill=eb_color)
    
    # Windows in Center Tower
    win_w = cb_w * 0.22
    win_h = win_w * 0.9
    for row in range(3):
        wy = cb_y + cb_h * 0.18 + row * (win_h * 2.1)
        # 2 windows per row
        edraw.rounded_rectangle([cx - win_w * 1.35, wy, cx - win_w * 0.35, wy + win_h], radius=int(win_w*0.25), fill=(0, 200, 180, 255))
        edraw.rounded_rectangle([cx + win_w * 0.35, wy, cx + win_w * 1.35, wy + win_h], radius=int(win_w*0.25), fill=(0, 200, 180, 255))
    
    # Windows in Left Tower
    l_win_w = lb_w * 0.28
    l_win_h = l_win_w * 0.9
    for row in range(2):
        wy = lb_y + lb_h * 0.22 + row * (l_win_h * 2.2)
        edraw.rounded_rectangle([lb_x + lb_w*0.20, wy, lb_x + lb_w*0.20 + l_win_w, wy + l_win_h], radius=int(l_win_w*0.25), fill=(0, 230, 118, 255))
        edraw.rounded_rectangle([lb_x + lb_w*0.55, wy, lb_x + lb_w*0.55 + l_win_w, wy + l_win_h], radius=int(l_win_w*0.25), fill=(0, 230, 118, 255))

    # Windows in Right Tower
    r_win_w = rb_w * 0.28
    r_win_h = r_win_w * 0.9
    wy = rb_y + rb_h * 0.28
    edraw.rounded_rectangle([rb_x + rb_w*0.20, wy, rb_x + rb_w*0.20 + r_win_w, wy + r_win_h], radius=int(r_win_w*0.25), fill=(0, 176, 255, 255))
    edraw.rounded_rectangle([rb_x + rb_w*0.55, wy, rb_x + rb_w*0.55 + r_win_w, wy + r_win_h], radius=int(r_win_w*0.25), fill=(0, 176, 255, 255))

    # Ground base bar
    base_h = eh * 0.08
    edraw.rounded_rectangle([cx - ew * 0.50, cy + eh * 0.38 - base_h, cx + ew * 0.50, cy + eh * 0.38 + base_h], radius=int(base_h), fill=eb_color)
    
    # Composite emblem onto image
    img = Image.alpha_composite(img, emblem)
    return img

if __name__ == '__main__':
    full_icon = create_gradient_circle(size=(1024, 1024), is_adaptive_foreground=False)
    full_icon.save("assets/icon/nivara_icon.png")
    
    fg_icon = create_gradient_circle(size=(1024, 1024), is_adaptive_foreground=True)
    fg_icon.save("assets/icon/nivara_icon_foreground.png")
    print("Successfully generated assets/icon/nivara_icon.png and assets/icon/nivara_icon_foreground.png")
