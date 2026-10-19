#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Wrap a kernel ELF the way the Cisco WLCNG boot loader (AIR-CT2504) expects
# an "RTOS" image: a legacy uImage header (Linux/MIPS, type "flat_dt",
# gzip) around a gzip stream whose original file name is "bzImage".
#
# mkimage can't be used as it refuses to emit type flat_dt for non-FDT data.

import gzip
import struct
import sys
import zlib

IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_MIPS = 5
IH_TYPE_FLATDT = 8
IH_COMP_GZIP = 1


def main(infile, outfile, name):
    with open(infile, "rb") as f:
        payload = f.read()

    data = gzip.compress(payload, 9, mtime=0)
    # Re-wrap with an FNAME field: the vendor update tool checks for
    # "bzImage" at offset 10 of the gzip stream (offset 74 of the image).
    data = (data[:3] + bytes([data[3] | 0x08]) + data[4:10] +
            b"bzImage\0" + data[10:])

    hdr = struct.pack(">IIIIIIIBBBB32s", IH_MAGIC, 0, 0, len(data), 0, 0,
                      zlib.crc32(data), IH_OS_LINUX, IH_ARCH_MIPS,
                      IH_TYPE_FLATDT, IH_COMP_GZIP, name.encode()[:31])
    hdr = hdr[:4] + struct.pack(">I", zlib.crc32(hdr)) + hdr[8:]

    with open(outfile, "wb") as f:
        f.write(hdr + data)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: %s <in> <out> <name>" % sys.argv[0])
    main(*sys.argv[1:])
