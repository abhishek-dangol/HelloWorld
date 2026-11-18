#!/usr/bin/env python3
"""Annotates an `otool -tV` listing with the text of each Objective-C string it loads.

otool prints "bad cfstring ref" for binaries that use chained fixups; this reads the
string straight from the (thin, arm64) Mach-O file instead.
usage: resolve_cfstrings.py <thin-macho> <otool-listing.txt>   (prints annotated lines)
"""
import re, struct, subprocess, sys

binary, listing = sys.argv[1], sys.argv[2]
data = open(binary, 'rb').read()

# segment table: (vmaddr, vmsize, fileoff)
segs = []
out = subprocess.run(['xcrun', 'otool', '-l', binary], capture_output=True, text=True).stdout
cur = {}
for line in out.splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[0] in ('vmaddr', 'vmsize', 'fileoff', 'segname', 'cmd'):
        if parts[0] == 'cmd':
            cur = {'cmd': parts[1]}
        else:
            cur[parts[0]] = parts[1]
        if cur.get('cmd') == 'LC_SEGMENT_64' and all(k in cur for k in ('vmaddr', 'vmsize', 'fileoff')):
            segs.append((int(cur['vmaddr'], 16), int(cur['vmsize'], 16), int(cur['fileoff'])))
            cur = {}

def fileoff(vm):
    for a, s, f in segs:
        if a <= vm < a + s:
            return f + (vm - a)
    return None

def cstr(vm):
    off = fileoff(vm)
    if off is None:
        return None
    end = data.find(b'\0', off)
    return data[off:end].decode('utf-8', 'replace')

def cfstring(vm):
    off = fileoff(vm)
    if off is None:
        return None
    raw = struct.unpack_from('<Q', data, off + 16)[0]
    return cstr(raw & 0xFFFFFFFFF)  # chained fixup: low 36 bits are the target

adrp = {}
for line in open(listing):
    line = line.rstrip('\n')
    m = re.search(r'adrp\s+(x\d+), \d+ ; (0x[0-9a-f]+)', line)
    if m:
        adrp[m.group(1)] = int(m.group(2), 16)
    m = re.search(r'add\s+(x\d+), (x\d+), #(0x[0-9a-f]+) ; Objc cfstring ref', line)
    if m and m.group(2) in adrp:
        text = cfstring(adrp[m.group(2)] + int(m.group(3), 16))
        line = line.split(';')[0] + '; @"%s"' % text
    print(line)
