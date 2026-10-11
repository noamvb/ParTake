#!/usr/bin/env python3
"""Measure Hansard sitting publication timestamps and latency."""

import re
import time
import urllib.request

USER_AGENT = "ParTake-research/0.1 (personal project)"
SITTINGS = [145, 146, 147, 148, 149]

def main():
    print(f"{'Sitting':<8} | {'Sitting Date':<24} | {'Meeting Time':<20} | {'Last-Modified (HTTP)':<30} | {'XML Size':<10}")
    print("-" * 105)
    for num in SITTINGS:
        url = f"https://www.ourcommons.ca/Content/House/451/Debates/{num}/HAN{num}-E.XML"
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req) as resp:
            last_mod = resp.headers.get("Last-Modified", "Unknown")
            length = resp.headers.get("Content-Length", "Unknown")
            xml_head = resp.read(2000).decode("utf-8", errors="replace")
            date_m = re.search(r"<ExtractedItem Name=\"Date\">(.*?)</ExtractedItem>", xml_head)
            creation_m = re.search(r"<ExtractedItem Name=\"MetaCreationTime\">(.*?)</ExtractedItem>", xml_head)
            sitting_date = date_m.group(1) if date_m else "Unknown"
            creation_time = creation_m.group(1) if creation_m else "Unknown"
            print(f"{num:<8} | {sitting_date:<24} | {creation_time:<20} | {last_mod:<30} | {length:<10}")
        time.sleep(1)

if __name__ == "__main__":
    main()
