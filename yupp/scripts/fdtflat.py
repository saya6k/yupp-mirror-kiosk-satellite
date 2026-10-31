#!/usr/bin/env python3
"""Flattens a DTB into "path:prop = value" lines, phandles shown as the
path they point at, so two boards' trees can be diffed."""
import struct, sys

def parse(data):
    magic, total, off_struct, off_strings = struct.unpack('>IIII', data[:16])
    assert magic == 0xd00dfeed
    strings = data[off_strings:]
    p = off_struct; path = []; nodes = {}; cur = None
    def s(o): return strings[o:strings.index(b'\0', o)].decode()
    while True:
        tok = struct.unpack('>I', data[p:p+4])[0]; p += 4
        if tok == 1:
            e = data.index(b'\0', p); name = data[p:e].decode(); p = (e + 4) & ~3
            path.append(name); cur = '/' + '/'.join(x for x in path if x); nodes[cur] = {}
        elif tok == 2:
            path.pop(); cur = '/' + '/'.join(x for x in path if x)
        elif tok == 3:
            ln, no = struct.unpack('>II', data[p:p+8]); p += 8
            nodes[cur][s(no)] = data[p:p+ln]; p = (p + ln + 3) & ~3
        elif tok == 4: continue
        elif tok == 9: break
    return nodes

PH = ('phandle', 'linux,phandle')
REFS = {'clocks', 'resets', 'pinctrl-0', 'pinctrl-1', 'pinctrl-2', 'power-domains', 'interrupt-parent',
        'remote-endpoint', 'backlight', 'pwms', 'iommus', 'phys', 'dmas', 'rockchip,grf', 'cpu', 'sound-dai',
        'vcc-supply', 'vmmc-supply', 'vqmmc-supply', 'rockchip,cpu', 'rockchip,codec', 'mmc-pwrseq',
        'operating-points-v2', 'cooling-device', 'thermal-sensors', 'trip', 'nvmem-cells', 'ports',
        'connect', 'logo-memory-region', 'memory-region', 'clocks', 'assigned-clock-parents', 'assigned-clocks'}

def fmt(nodes, name, v, ph):
    if all(32 <= c < 127 or c == 0 for c in v) and v.endswith(b'\0') and len(v) > 1 and v[0]:
        return ' '.join('"%s"' % x.decode() for x in v[:-1].split(b'\0'))
    if len(v) % 4 == 0 and v:
        cells = struct.unpack('>%dI' % (len(v) // 4), v)
        if name in REFS or name.endswith('-supply') or name.endswith('-gpios') or name.endswith('gpio') or name == 'gpios':
            return '<' + ' '.join(ph.get(c, hex(c)) for c in cells) + '>'
        return '<' + ' '.join(hex(c) for c in cells) + '>'
    return '[' + v.hex() + ']'

def flat(fn):
    nodes = parse(open(fn, 'rb').read())
    ph = {}
    for path, props in nodes.items():
        for k in PH:
            if k in props: ph[struct.unpack('>I', props[k])[0]] = '&' + path
    out = []
    for path, props in nodes.items():
        out.append(path + '/')
        for k, v in props.items():
            if k in PH: continue
            out.append('%s:%s = %s' % (path, k, fmt(nodes, k, v, ph)))
    return out

if __name__ == '__main__':
    print('\n'.join(sorted(flat(sys.argv[1]))))
