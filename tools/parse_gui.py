import struct, sys, re

if len(sys.argv) < 2:
    print('usage: python parse_gui.py <path to hud_gauge.gui>')
    raise SystemExit(1)
p = sys.argv[1]
d = open(p, 'rb').read()

def u32(o): return struct.unpack_from('<I', d, o)[0]
def u64(o): return struct.unpack_from('<Q', d, o)[0]
def s32(o): return struct.unpack_from('<i', d, o)[0]

H = {
    'objectNum': u32(48), 'initParamNum': u32(56),
    'objectOffset': u64(184), 'initParamOffset': u64(200),
    'stringOffset': u64(360), 'kv32': u64(384), 'kv128': u64(392),
}

def cstr(off):
    end = d.index(b'\x00', off)
    return d[off:end].decode('utf-8', 'ignore')

def vec4(off):
    return struct.unpack_from('<4f', d, off)

# init params
params = []
for i in range(H['initParamNum']):
    o = H['initParamOffset'] + i * 32
    if o + 32 > len(d): break
    t = d[o]
    name = cstr(H['stringOffset'] + u32(o + 16))
    voff = u32(o + 24)
    val = None
    if t == 4:
        val = vec4(H['kv128'] + voff)
    elif t in (2, 15):
        val = struct.unpack_from('<f', d, H['kv32'] + voff)[0]
    params.append((t, name, val))

# objects
objs = []
for i in range(H['objectNum']):
    o = H['objectOffset'] + i * 56
    if o + 56 > len(d): break
    name = cstr(H['stringOffset'] + u32(o + 16))
    num = d[o + 4]
    idx = u32(o + 32)
    objs.append((name, idx, num))

print('objects', len(objs), 'init params', len(params))
target = [o for o in objs if re.search(r'sharp', o[0], re.I)]
print('\n== objects matching sharp ==')
for name, idx, num in target:
    print('OBJ %-28s params %d..%d' % (name, idx, idx + num))
    for k in range(idx, min(idx + num, len(params))):
        t, pname, val = params[k]
        if val is None: sval = ''
        elif isinstance(val, tuple): sval = '(%s)' % ', '.join(('%.4f' % v) for v in val)
        else: sval = '%.4f' % val
        print('     %-22s type %-3d %s' % (pname, t, sval))

# ---- extra: texture table + all sharpness objects ----
texNum = u32(112); texOff = u64(304)
texs = []
for i in range(texNum):
    o = texOff + i*24
    if o+24 > len(d): break
    try:
        nm = cstr(H['stringOffset'] + u32(o+16))
    except Exception:
        nm = '?'
    texs.append(nm)
print('\n== textures ==')
for i,t in enumerate(texs): print('  [%d] %s' % (i,t))

print('\n== all tex_sharp* / poly_sharp* objects ==')
for name, idx, num in objs:
    if re.search(r'sharp', name, re.I):
        vals = {}
        for k in range(idx, min(idx+num, len(params))):
            t,pn,pv = params[k]
            if pn in ('mTextureRect','VertexColor','Size','Texture','SclX','SclY','PosX','PosY'):
                vals[pn] = pv
        print('OBJ %-24s %s' % (name, vals))
