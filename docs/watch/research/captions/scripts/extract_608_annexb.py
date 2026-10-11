#!/usr/bin/env python3
"""Lightweight CEA-608 extractor for Annex B H.264 or MPEG-TS."""

import sys

def parse_t35(data):
    if len(data) < 10:
        return []
    if data[0] != 0xB5 or data[1] != 0 or data[2] != 0x31:
        return []
    if data[3:7] != b'GA94':
        return []
    if data[7] != 3:
        return []
    flags = data[8]
    if not (flags & 0x40):
        return []
    count = flags & 0x1F
    pairs = []
    idx = 10
    for _ in range(count):
        if idx + 3 > len(data):
            break
        hdr = data[idx]
        if hdr & 4:
            cc_type = hdr & 3
            if cc_type <= 1:
                pairs.append((cc_type, data[idx+1], data[idx+2]))
        idx += 3
    return pairs

def parse_sei(payload):
    # Unescape emulation prevention 00 00 03 -> 00 00
    rbsp = bytearray()
    i = 0
    while i < len(payload):
        if i + 2 < len(payload) and payload[i] == 0 and payload[i+1] == 0 and payload[i+2] == 3:
            rbsp.extend([0, 0])
            i += 3
        else:
            rbsp.append(payload[i])
            i += 1
    i = 0
    pairs = []
    while i < len(rbsp):
        ptype = 0
        while i < len(rbsp) and rbsp[i] == 0xFF:
            ptype += 255
            i += 1
        if i >= len(rbsp):
            break
        ptype += rbsp[i]
        i += 1

        psize = 0
        while i < len(rbsp) and rbsp[i] == 0xFF:
            psize += 255
            i += 1
        if i >= len(rbsp):
            break
        psize += rbsp[i]
        i += 1

        if i + psize > len(rbsp):
            break
        if ptype == 4:
            pairs.extend(parse_t35(rbsp[i:i+psize]))
        i += psize
    return pairs

class Cea608TextDecoder:
    """Minimal CEA-608 roll-up / pop-on text collector."""
    def __init__(self):
        self.rows = [list(' ' * 32) for _ in range(15)]
        self.non_disp = [list(' ' * 32) for _ in range(15)]
        self.row = 14
        self.col = 0
        self.mode = 'pop'
        self.roll_rows = 0
        self.last_text = ""

    def push(self, b1, b2):
        b1 &= 0x7F
        b2 &= 0x7F
        if b1 == 0 and b2 == 0:
            return None
        # Control commands
        if (b1 in (0x14, 0x15)) and b2 >= 0x20:
            if b2 == 0x20:  # RCL
                self.mode = 'pop'
            elif b2 in (0x25, 0x26, 0x27):  # RU2, RU3, RU4
                self.mode = 'roll'
                self.roll_rows = b2 - 0x23
            elif b2 == 0x2C:  # EDM
                self.rows = [list(' ' * 32) for _ in range(15)]
            elif b2 == 0x2D:  # CR
                if self.mode == 'roll' and self.roll_rows > 0:
                    first = max(0, self.row - self.roll_rows + 1)
                    for r in range(first, self.row):
                        self.rows[r] = list(self.rows[r+1])
                    self.rows[self.row] = list(' ' * 32)
                    self.col = 0
            elif b2 == 0x2F:  # EOC
                self.rows, self.non_disp = self.non_disp, self.rows
                self.mode = 'pop'
        elif b1 >= 0x10 and b1 <= 0x17 and b2 >= 0x40 and b2 <= 0x7F:
            # PAC
            pac_rows = [0, 11, 1, 2, 3, 4, 12, 13, 14, 15, 5, 6, 7, 8, 9, 10]
            idx = (b1 - 0x10) * 2 + (0 if (b2 & 0x20) == 0 else 1)
            if idx < len(pac_rows):
                self.row = max(0, pac_rows[idx] - 1)
            self.col = ((b2 & 0x0E) >> 1) * 4 if (b2 & 0x10) else 0
        elif 0x20 <= b1 <= 0x7F or 0x20 <= b2 <= 0x7F:
            grid = self.non_disp if self.mode == 'pop' else self.rows
            for b in (b1, b2):
                if 0x20 <= b <= 0x7F:
                    if self.col < 32:
                        grid[self.row][self.col] = chr(b)
                        self.col += 1
        lines = [''.join(r).rstrip() for r in self.rows]
        text = ' '.join(l for l in lines if l).strip()
        if text and text != self.last_text:
            self.last_text = text
            return text
        return None

def main():
    import subprocess
    # Read Annex B H.264 from stdin
    buf = bytearray()
    decoder = Cea608TextDecoder()
    stdin_fd = sys.stdin.buffer
    while True:
        chunk = stdin_fd.read(65536)
        if not chunk:
            break
        buf.extend(chunk)
        # Find start codes 00 00 01
        pos = 0
        while True:
            # find next 00 00 01
            idx = buf.find(b'\x00\x00\x01', pos)
            if idx < 0:
                # Keep last 3 bytes in case start code is split
                buf = buf[-3:]
                break
            # Find following start code
            next_idx = buf.find(b'\x00\x00\x01', idx + 3)
            if next_idx < 0:
                buf = buf[idx:]
                break
            nal = buf[idx+3:next_idx]
            if nal.endswith(b'\x00'):
                nal = nal[:-1]
            if nal:
                nal_type = nal[0] & 0x1F
                if nal_type == 6:  # SEI
                    pairs = parse_sei(nal[1:])
                    for cc_type, b1, b2 in pairs:
                        if cc_type == 0:  # Field 1 (CC1)
                            t = decoder.push(b1, b2)
                            if t:
                                print(t, flush=True)
            pos = next_idx

if __name__ == '__main__':
    main()
