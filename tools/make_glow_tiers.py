from PIL import Image

d = r'C:\Program Files (x86)\Steam\steamapps\common\MonsterHunterWilds\reframework\images\mhw'
glow = Image.open(d + r'\gw_blade_glow.png').convert('RGBA')
tiers = ["red", "orange", "yellow", "green", "blue", "white"]

for name in tiers:
    bar = Image.open(d + rf'\gw_bar_{name}.png').convert('RGBA')
    # tier tint = average colour of the blade sprite's opaque pixels
    px = [p for p in bar.getdata() if p[3] > 200]
    r = sum(p[0] for p in px) / len(px)
    g = sum(p[1] for p in px) / len(px)
    b = sum(p[2] for p in px) / len(px)
    out = Image.new('RGBA', glow.size)
    gp = glow.load()
    op = out.load()
    for y in range(glow.height):
        for x in range(glow.width):
            gr, gg, gb, ga = gp[x, y]
            op[x, y] = (int(r), int(g), int(b), ga)
    path = d + rf'\gw_glow_{name}.png'
    out.save(path)
    print('%-7s tint=(%d,%d,%d) -> %s' % (name, r, g, b, path))
