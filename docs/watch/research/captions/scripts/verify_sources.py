#!/usr/bin/env python3
"""Verify that every URL in REPORT.md Sources table returns HTTP 2xx/3xx."""

import re
import subprocess
import sys
import time
from pathlib import Path

def main():
    report_path = Path(__file__).resolve().parent.parent / "REPORT.md"
    text = report_path.read_text(encoding="utf-8")
    urls = re.findall(r'\|\s*`(https?://[^`]+)`\s*\|\s*(\d+)\s*\|', text)
    print(f"Extracted {len(urls)} URLs from REPORT.md Sources table.")
    if not urls:
        print("ERROR: No URLs found in Sources table.")
        sys.exit(1)

    failed = []
    for idx, (url, expected) in enumerate(urls, 1):
        cmd = [
            "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "-A", "ParTake-research/0.1 (personal project)", url
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        code = res.stdout.strip()
        if code.startswith(("2", "3")):
            print(f"[{idx}/{len(urls)}] {code} OK: {url}")
        else:
            print(f"[{idx}/{len(urls)}] FAIL ({code}): {url}")
            failed.append((url, code))
        time.sleep(1.05)

    if failed:
        print(f"\nFAILED URLS ({len(failed)}):")
        for u, c in failed:
            print(f"  {c}: {u}")
        sys.exit(1)

    print("\nSUCCESS: All URLs verified 2xx/3xx.")

if __name__ == "__main__":
    main()
