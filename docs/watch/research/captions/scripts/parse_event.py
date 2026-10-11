#!/usr/bin/env python3
"""Inspect streams and ccItems in ParlVU event HTML."""

import json
import re
import sys

def parse_embedded(html, marker):
    pos = html.find(marker)
    if pos < 0:
        return None
    start = pos + len(marker)
    while start < len(html) and html[start] in ' \t\r\n':
        start += 1
    if start >= len(html) or html[start] not in '{[':
        return None
    opener = html[start]
    closer = '}' if opener == '{' else ']'
    depth = 0
    quoted = False
    escaped = False
    for i in range(start, len(html)):
        c = html[i]
        if quoted:
            if escaped:
                escaped = False
            elif c == '\\':
                escaped = True
            elif c == '"':
                quoted = False
            continue
        if c == '"':
            quoted = True
            continue
        if c == opener:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                raw = html[start:i+1]
                return json.loads(raw)
    return None

def main():
    if len(sys.argv) < 2:
        print("Usage: parse_event.py <html-file>")
        sys.exit(1)
    with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
        html = f.read()

    streams = parse_embedded(html, "var availableStreams = ")
    event_info = parse_embedded(html, "\tEventInfo:")

    result = {
        "availableStreams": streams,
        "EventInfo": event_info,
    }
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
