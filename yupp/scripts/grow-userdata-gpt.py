#!/usr/bin/env python3
"""Writes the GPT of Radxa's image for a whole SD: userdata, the last
partition, grows to the end of the disk, and the backup GPT moves to the
disk's last sectors. Radxa's first boot runs recovery (misc holds
"recovery --wipe_all") to do this, but that recovery carries the Rock Pi's
tree and never gets there on the mirror.

usage: grow-userdata-gpt.py IMAGE DISK_BYTES PRIMARY_OUT BACKUP_OUT
  PRIMARY_OUT: sectors 0-33 (protective MBR, header, entries)
  BACKUP_OUT:  the disk's last 33 sectors (entries, then the header)
"""
import struct
import sys
import zlib

image, disk_bytes, primary_out, backup_out = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
SECTOR = 512
last_lba = disk_bytes // SECTOR - 1

d = open(image, 'rb').read(34 * SECTOR)
mbr, hdr, entries = bytearray(d[:SECTOR]), bytearray(d[SECTOR:2 * SECTOR]), bytearray(d[2 * SECTOR:34 * SECTOR])
assert hdr[:8] == b'EFI PART'
hsize = struct.unpack('<I', hdr[12:16])[0]
n, esize = struct.unpack('<II', hdr[80:88])
assert n * esize == len(entries), 'entries do not fit in 32 sectors'

first_usable = struct.unpack('<Q', hdr[40:48])[0]
last_usable = last_lba - 33
names = []
for i in range(n):
    e = entries[i * esize:(i + 1) * esize]
    if not any(e[:16]):
        continue
    names.append((i, e[56:128].decode('utf-16-le').rstrip('\0'), struct.unpack('<QQ', e[32:48])))
idx, name, (first, last) = max(names, key=lambda x: x[2][0])
assert name == 'userdata', 'last partition is %s' % name
struct.pack_into('<Q', entries, idx * esize + 40, last_usable)
print('userdata: sectors %d-%d (%.1f GiB), was %d-%d' % (first, last_usable, (last_usable - first + 1) * SECTOR / 2**30, first, last))

entries_crc = zlib.crc32(entries) & 0xffffffff

def header(my_lba, alt_lba, entries_lba):
    h = bytearray(hdr[:hsize])
    struct.pack_into('<QQ', h, 24, my_lba, alt_lba)
    struct.pack_into('<QQ', h, 40, first_usable, last_usable)
    struct.pack_into('<Q', h, 72, entries_lba)
    struct.pack_into('<I', h, 88, entries_crc)
    struct.pack_into('<I', h, 16, 0)
    struct.pack_into('<I', h, 16, zlib.crc32(h) & 0xffffffff)
    return bytes(h) + b'\0' * (SECTOR - hsize)

# The protective MBR's partition covers the whole disk.
struct.pack_into('<I', mbr, 446 + 12, min(last_lba, 0xffffffff))
open(primary_out, 'wb').write(bytes(mbr) + header(1, last_lba, 2) + bytes(entries))
open(backup_out, 'wb').write(bytes(entries) + header(last_lba, 1, last_lba - 32))
print('primary %s, backup %s (at sector %d)' % (primary_out, backup_out, last_lba - 32))
