#!/usr/bin/env python3
"""Fetch ParlVU player JS files and grep for API calls."""

import os
import re
import time
import urllib.request

JS_FILES = [
    "/Harmony/javascript/FEB9C08FF32668663BB3090916FA1BDA__5d4195.js",
    "/Harmony/javascript/9AF41513B9F8E8BCEC09051270AB9D58__1255b23.js",
    "/Harmony/javascript/552417ADE9C438E56FE333B463BE9D6A__b9783e.js",
    "/Harmony/en/api/LocalizationJS/PowerBrowserV2",
    "/Harmony/javascript/F30BCCA1EE0A7021F9CF4314BB80E550__b97832.js",
    "/Harmony/javascript/DDB0E9B70F89D094071F5867745BD7BE__b9783e.js",
    "/Harmony/javascript/E926926CE218AAD5579A4C89DD9FA8BB__1ce2d26.js",
    "/Harmony/javascript/B3F896C92BDFB918E89D73E13C0AC26E__b97832.js",
    "/Harmony/javascript/47CE0AE1FF5D05189622353CFBE7DE11__1136dd2.js",
    "/Harmony/javascript/310E9D5D5F7EC5782E64F28B5CB81D08__18079c1.js",
    "/Harmony/javascript/B6D24B68259C915A9025FB09A406B232__11478ca.js",
]

BASE = "https://parlvu.parl.gc.ca"
OUT_DIR = "/home/deck/.gemini/antigravity-cli/brain/b9fddf34-2543-4f71-9e57-15afe8bf834d/scratch/js"

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    headers = {"User-Agent": "ParTake-research/0.1 (personal project)"}

    downloaded = []
    for path in JS_FILES:
        url = BASE + path
        name = os.path.basename(path)
        dest = os.path.join(OUT_DIR, name)
        print(f"Fetching {url}...")
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                status = resp.status
                content = resp.read()
                with open(dest, "wb") as f:
                    f.write(content)
                print(f" -> {status}, {len(content)} bytes")
                downloaded.append((name, url, status, dest))
        except Exception as e:
            print(f" -> ERROR: {e}")
        time.sleep(1.1)

    print("\n=== SEARCHING FOR API PATHS ===")
    api_patterns = [
        re.compile(r'["\'](/Harmony/[^"\']+)["\']'),
        re.compile(r'["\'](/api/[^"\']+)["\']'),
        re.compile(r'\b(Get[A-Za-z0-9_]+)\b'),
        re.compile(r'\b(Speaker[A-Za-z0-9_]*)\b', re.IGNORECASE),
        re.compile(r'\b(Intervention[A-Za-z0-9_]*)\b', re.IGNORECASE),
    ]

    all_harmony_paths = set()
    speaker_mentions = []

    for name, url, status, dest in downloaded:
        if not os.path.exists(dest):
            continue
        with open(dest, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()

        paths = re.findall(r'["\'](/Harmony/[A-Za-z0-9_/\.\?=-]+)["\']', text)
        for p in paths:
            if not p.endswith(('.css', '.png', '.jpg', '.gif', '.js')):
                all_harmony_paths.add(p)

        # Search for speaker-related logic
        for m in re.finditer(r'([^\n;]{0,60}Speaker[^\n;]{0,60})', text, re.IGNORECASE):
            speaker_mentions.append((name, m.group(1).strip()))

    print("\nDistinct /Harmony/ API / page endpoints found in JS bundles:")
    for p in sorted(all_harmony_paths):
        print(f"  {p}")

    print(f"\nSpeaker mentions found in JS ({len(speaker_mentions)} total):")
    for fname, snippet in speaker_mentions[:25]:
        print(f"  [{fname}] {snippet}")

if __name__ == "__main__":
    main()
