"""CEA-608 extraction and CC1 decoding, ported from parlvu's Dart decoder."""


def _section(data):
    if len(data) < 3:
        return None
    total = 3 + ((data[1] & 0x0f) << 8 | data[2])
    return data[:total] if len(data) >= total else None


def extract_cc_pairs(ts: bytes) -> list[tuple[int, int, int, int]]:
    """Return (PTS, byte 1, byte 2, field), stably ordered by PTS."""
    tables = {}
    pes_by_pid = {}
    found = []
    video_pid = -1
    for offset in range(0, len(ts) - 187, 188):
        if ts[offset] != 0x47:
            continue
        b1, b2, b3 = ts[offset + 1:offset + 4]
        if b1 & 0x80 or not ((b3 >> 4) & 1):
            continue
        pid = (b1 & 0x1f) << 8 | b2
        start = bool(b1 & 0x40)
        adaptation_control = (b3 >> 4) & 3
        cursor = offset + 4
        if adaptation_control in (2, 3):
            cursor += 1 + ts[cursor]
        if adaptation_control == 2 or cursor >= offset + 188:
            continue
        payload = ts[cursor:offset + 188]
        if pid == 0 or (video_pid < 0 and pid != 0x1fff):
            if start:
                section_offset = 1 + (payload[0] if payload else 0)
                if section_offset < len(payload):
                    tables[pid] = bytearray(payload[section_offset:])
            else:
                tables.setdefault(pid, bytearray()).extend(payload)
            if pid == 0:
                pat = _section(tables[pid])
                if pat is not None and len(pat) >= 12 and pat[0] == 0:
                    for i in range(8, len(pat) - 7, 4):
                        program = pat[i] << 8 | pat[i + 1]
                        if program:
                            pmt_pid = (pat[i + 2] & 0x1f) << 8 | pat[i + 3]
                            tables.setdefault(pmt_pid, bytearray())
            for data in list(tables.values()):
                section = _section(data)
                if section is None or not section or section[0] != 2:
                    continue
                info_length = (section[10] & 0x0f) << 8 | section[11]
                i = 12 + info_length
                while i + 5 <= len(section) - 4:
                    stream_type = section[i]
                    elementary_pid = (section[i + 1] & 0x1f) << 8 | section[i + 2]
                    es_info_length = (section[i + 3] & 0x0f) << 8 | section[i + 4]
                    if stream_type == 0x1b:
                        video_pid = elementary_pid
                    i += 5 + es_info_length
        if pid != video_pid:
            continue
        if start:
            previous = pes_by_pid.pop(pid, None)
            if previous is not None:
                _read_pes(previous, found)
            pes_by_pid[pid] = bytearray(payload)
        else:
            pes_by_pid.setdefault(pid, bytearray()).extend(payload)
    for pes in pes_by_pid.values():
        _read_pes(pes, found)
    found.sort(key=lambda pair: pair[0])
    return found


def _annex_b_nals(data):
    starts = []
    i = 0
    while i + 3 <= len(data):
        if data[i:i + 3] == b'\x00\x00\x01':
            starts.append((i, 3))
            i += 3
        elif i + 4 <= len(data) and data[i:i + 4] == b'\x00\x00\x00\x01':
            starts.append((i, 4))
            i += 4
        else:
            i += 1
    return [data[start + size:starts[n + 1][0] if n + 1 < len(starts) else len(data)]
            for n, (start, size) in enumerate(starts)]


def _read_pes(data, found):
    if len(data) < 9 or data[:3] != b'\x00\x00\x01':
        return
    flags = (data[7] >> 6) & 3
    pts = 0
    if flags & 2 and len(data) >= 14:
        pts = ((data[9] & 0x0e) << 29 | data[10] << 22 |
               (data[11] & 0xfe) << 14 | data[12] << 7 | (data[13] & 0xfe) >> 1)
    payload_start = 9 + data[8]
    if payload_start >= len(data):
        return
    for nal in _annex_b_nals(data[payload_start:]):
        if not nal or nal[0] & 0x1f != 6:
            continue
        rbsp = bytearray()
        i = 1
        while i < len(nal):
            if i + 2 < len(nal) and nal[i:i + 3] == b'\x00\x00\x03':
                rbsp.extend(b'\x00\x00')
                i += 3
            else:
                rbsp.append(nal[i])
                i += 1
        i = 0
        while i < len(rbsp):
            payload_type = 0
            while i < len(rbsp) and rbsp[i] == 0xff:
                payload_type += 255
                i += 1
            if i >= len(rbsp):
                break
            payload_type += rbsp[i]
            i += 1
            size = 0
            while i < len(rbsp) and rbsp[i] == 0xff:
                size += 255
                i += 1
            if i >= len(rbsp):
                break
            size += rbsp[i]
            i += 1
            if i + size > len(rbsp):
                break
            if payload_type == 4:
                _read_t35(rbsp[i:i + size], pts, found)
            i += size
            if payload_type == 0x80:
                break


def _read_t35(data, pts, found):
    if len(data) < 10 or data[:8] != b'\xb5\x00\x31GA94\x03':
        return
    flags = data[8]
    if not flags & 0x40:
        return
    for index in range(10, min(10 + (flags & 0x1f) * 3, len(data) - 2), 3):
        header = data[index]
        field = header & 3
        if header & 4 and field <= 1:
            found.append((pts, data[index + 1], data[index + 2], field))


def _grid():
    return [[' '] * 32 for _ in range(15)]


_EXTENDED_12 = "ÁÉÓÚÜü'¡*'—©℠•“”ÀÂÇÈÊËëÎÏïÔÙùÛ«»"
_EXTENDED_13 = "ÃãÍÌìÒòÕõ{}\\^_|~ÄäÖöß¥¤│ÅåØø┌┐└┘"
_SPECIAL = "®°½¿™¢£♪à èâêîôû"
_STANDARD = {0x2a: 'á', 0x5c: 'é', 0x5e: 'í', 0x5f: 'ó', 0x60: 'ú',
             0x7b: 'ç', 0x7c: '÷', 0x7d: 'Ñ', 0x7e: 'ñ', 0x7f: '█'}


class Decoder:
    """Stateful CEA-608 decoder for CC1, with displayed and pop-on grids."""

    def __init__(self):
        self._displayed = _grid()
        self._non_displayed = _grid()
        self._row = 14
        self._column = 0
        self._roll_rows = 0
        self._mode = 'pop'
        self._channel2 = False
        self._text_mode = False
        self._last_control = None

    def push(self, pts, b1, b2):
        b1 &= 0x7f
        b2 &= 0x7f
        if b1 == 0 and b2 == 0:
            return None
        if b1 in (0x12, 0x13) and 0x20 <= b2 <= 0x3f:
            self._last_control = None
            before = self._visible_text()
            if not self._channel2 and not self._text_mode:
                self._backspace()
                self._put((_EXTENDED_12 if b1 == 0x12 else _EXTENDED_13)[b2 - 0x20])
            return self._change(pts, before)
        control = 0x10 <= b1 <= 0x1f and 0x20 <= b2 <= 0x7f
        if control:
            if self._last_control == (b1, b2):
                self._last_control = None
                return None
            self._last_control = (b1, b2)
        else:
            self._last_control = None
        before = self._visible_text()
        if 0x18 <= b1 <= 0x1f:
            self._channel2 = True
            return None
        if 0x10 <= b1 <= 0x17 and 0x20 <= b2 <= 0x2f:
            self._channel2 = False
            if b1 in (0x14, 0x15):
                self._command(b2)
            if b1 == 0x17 and 0x21 <= b2 <= 0x23:
                self._column = min(31, max(0, self._column + b2 - 0x20))
            return self._change(pts, before)
        if 0x10 <= b1 <= 0x17 and 0x40 <= b2 <= 0x7f:
            self._channel2 = False
            self._set_pac(b1, b2)
            return None
        if self._channel2:
            return None
        if b1 == 0x11 and 0x20 <= b2 <= 0x2f:
            if not self._text_mode:
                self._put(' ')
            return self._change(pts, before)
        if b1 == 0x11 and 0x30 <= b2 <= 0x3f:
            if not self._text_mode:
                self._put(_SPECIAL[b2 - 0x30])
            return self._change(pts, before)
        if 0x20 <= b1 <= 0x7f or 0x20 <= b2 <= 0x7f:
            if not self._text_mode:
                for code in (b1, b2):
                    if 0x20 <= code <= 0x7f:
                        self._put(_STANDARD.get(code, chr(code)))
            return self._change(pts, before)
        return None

    def _command(self, command):
        if command == 0x20:
            self._mode, self._roll_rows, self._text_mode = 'pop', 0, False
        elif command == 0x21:
            self._backspace()
        elif command == 0x24:
            for c in range(self._column, 32):
                self._active()[self._row][c] = ' '
        elif command in (0x25, 0x26, 0x27):
            self._mode, self._roll_rows, self._text_mode = 'roll', command - 0x23, False
        elif command == 0x29:
            self._mode, self._roll_rows, self._text_mode = 'paint', 0, False
        elif command in (0x2a, 0x2b):
            self._text_mode = True
        elif command == 0x2c:
            self._displayed = _grid()
        elif command == 0x2d:
            self._carriage_return()
        elif command == 0x2e:
            self._non_displayed = _grid()
        elif command == 0x2f:
            self._displayed, self._non_displayed = self._non_displayed, self._displayed
            self._mode, self._roll_rows, self._text_mode = 'pop', 0, False

    def _set_pac(self, b1, b2):
        rows = [0, 11, 1, 2, 3, 4, 12, 13, 14, 15, 5, 6, 7, 8, 9, 10]
        index = (b1 - 0x10) * 2 + (1 if b2 & 0x20 else 0)
        if 0 <= index < len(rows):
            self._row = rows[index] - 1
        self._column = ((b2 & 0x0e) >> 1) * 4 if b2 & 0x10 else 0

    def _carriage_return(self):
        if self._mode != 'roll' or self._roll_rows == 0:
            return
        first = min(14, max(0, self._row - self._roll_rows + 1))
        for r in range(first, self._row):
            self._displayed[r] = self._displayed[r + 1].copy()
        self._displayed[self._row] = [' '] * 32
        self._column = 0

    def _active(self):
        return self._non_displayed if self._mode == 'pop' else self._displayed

    def _put(self, char):
        if self._column < 32:
            self._active()[self._row][self._column] = char
            self._column += 1

    def _backspace(self):
        if self._column > 0:
            self._column -= 1
            self._active()[self._row][self._column] = ' '

    def _visible_text(self):
        lines = [''.join(row).rstrip() for row in self._displayed]
        return '\n'.join(line for line in lines if line) or None

    def _change(self, pts, before):
        after = self._visible_text()
        return None if before == after else (pts, after)


def decode(ts, decoder=None):
    """Decode field 0 only; passing a Decoder retains state across segments."""
    active = decoder if decoder is not None else Decoder()
    changes = []
    for pts, b1, b2, field in extract_cc_pairs(ts):
        if field != 0:
            continue
        change = active.push(pts, b1, b2)
        if change is not None:
            changes.append(change)
    return changes
