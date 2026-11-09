from PIL import Image, ImageFilter

import sys
# usage: python make_glow.py <game>/reframework/images/mhw
d = sys.argv[1] if len(sys.argv) > 1 else 'reframework/images/mhw'
src = Image.open(d + r'\gw_bar_white.png').convert('RGBA')   # 73x32, blade art at x4-68 y9-18

pad = 14
canvas = Image.new('RGBA', (src.width + pad * 2, src.height + pad * 2), (0, 0, 0, 0))

# blurred alpha of the blade -> soft halo
alpha = src.split()[3]
halo = alpha.filter(ImageFilter.GaussianBlur(radius=5))
halo = halo.point(lambda v: min(255, int(v * 1.15)))

white = Image.new('RGBA', src.size, (255, 255, 255, 0))
white.putalpha(halo)
canvas.alpha_composite(white, (pad, pad))

out = d + r'\gw_blade_glow.png'
canvas.save(out)
print('saved', out, canvas.size, 'pad', pad)

# quick visual check on a dark background
bg = Image.new('RGBA', canvas.size, (25, 25, 28, 255))
bg.alpha_composite(canvas)
bg.alpha_composite(Image.open(d + r'\gw_bar_white.png').convert('RGBA'), (pad, pad))
bg.resize((canvas.width * 4, canvas.height * 4), Image.NEAREST).save(
    'glow_preview.png')
print('preview written')
