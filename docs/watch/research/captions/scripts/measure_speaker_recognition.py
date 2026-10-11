#!/usr/bin/env python3
"""Measure how often the Speaker/Chair names members before they speak."""

import json
import re
import sys
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent))
from parse_event import parse_embedded

def normalize(text):
    return re.sub(r'\s+', ' ', text).strip().lower()

def extract_riding_and_role(speaker_str):
    m = re.search(r'\((.*?)\)', speaker_str)
    if not m:
        return None, None
    inside = m.group(1)
    parts = [p.strip() for p in inside.split(',')]
    riding_or_role = parts[0]
    if any(k in riding_or_role.lower() for k in ['minister', 'secretary', 'leader', 'prime minister']):
        role = riding_or_role
        riding = None
    else:
        riding = riding_or_role
        role = None
    return riding, role

def main():
    scratch = Path("/home/deck/.gemini/antigravity-cli/brain/b9fddf34-2543-4f71-9e57-15afe8bf834d/scratch")

    # Load all speeches
    speeches = []
    for page in ["speeches_page1.json", "speeches_page2.json", "speeches_page3.json"]:
        p = scratch / page
        if p.exists():
            data = json.loads(p.read_text())
            speeches.extend(data["objects"])
    print(f"Total speeches loaded: {len(speeches)}")

    # Load captions
    html_path = scratch / "event_45735_page.html.raw"
    if not html_path.exists():
        print("HTML file missing")
        return

    html = html_path.read_text(encoding="utf-8", errors="replace")
    cc = parse_embedded(html, "\tccItems:")
    if not cc or "en" not in cc:
        print("Captions missing")
        return
    captions = cc["en"]
    print(f"Total English caption lines: {len(captions)}")

    # Combine captions into continuous text stream
    # Each caption has Begin, End, Content
    # We clean whitespace and >> markers
    full_caption_text = " ".join(c["Content"] for c in captions)
    # Also create a normalized version
    full_norm = normalize(full_caption_text)

    # Filter out procedural statements by the Speaker / Chair
    # In Hansard, speeches attributed to "The Speaker", "The Deputy Speaker", etc.
    transitions = []
    prev_speaker = None
    for idx, sp in enumerate(speeches):
        curr_speaker = sp.get("attribution", {}).get("en", "")
        if any(term in curr_speaker.lower() for term in ["the speaker", "the deputy speaker", "the chair", "the acting speaker"]):
            continue
        if curr_speaker != prev_speaker:
            transitions.append((idx, sp, prev_speaker))
            prev_speaker = curr_speaker

    print(f"Total member-to-member speech transitions: {len(transitions)}")

    hits = 0
    misses = []
    hit_details = []

    for idx, sp, prev in transitions:
        speaker_name = sp.get("attribution", {}).get("en", "")
        riding, role = extract_riding_and_role(speaker_name)
        content = sp.get("content", {}).get("en", "")
        # clean HTML from speech opening
        clean_content = re.sub(r'<[^>]+>', ' ', content)
        clean_content = re.sub(r'&[a-z0-9#]+;', ' ', clean_content)
        words = clean_content.strip().split()

        # Locate the speech in the caption text
        pos = -1
        # Try matching consecutive word n-grams from speech start
        for n in [6, 5, 4, 3]:
            if len(words) >= n:
                target_str = normalize(" ".join(words[:n]))
                # avoid short common phrases like "madam speaker" alone
                if len(target_str) < 12 and n <= 3:
                    continue
                p = full_norm.find(target_str)
                if p != -1:
                    pos = p
                    break

        named = False
        matched_formula = None
        window = ""
        if pos != -1:
            # Look backwards up to 350 chars before the speech text in captions
            start_win = max(0, pos - 350)
            window = full_norm[start_win:pos]

            # Check if Speaker / Chair recognition formula appears in this preceding window
            # 1. By Riding
            if riding:
                r_clean = normalize(re.sub(r'—|-', ' ', riding))
                if r_clean in window or (len(r_clean.split()) > 1 and all(w in window for w in r_clean.split())):
                    named = True
                    matched_formula = f"Riding ({riding})"

            # 2. By Ministerial Portfolio / Role
            if not named and role:
                role_clean = normalize(role.replace("Hon. ", "").replace("The ", ""))
                if role_clean in window:
                    named = True
                    matched_formula = f"Role ({role})"
                else:
                    # check "minister of ..." or "leader of ..."
                    m_role = re.search(r'(minister|secretary|leader) of [a-z\s]+', role_clean)
                    if m_role and m_role.group(0).strip() in window:
                        named = True
                        matched_formula = f"Portfolio ({m_role.group(0)})"

            # 3. By Member Last Name
            if not named:
                # Name before parenthesis
                clean_name = speaker_name.split('(')[0].replace("Hon. ", "").replace("Right Hon. ", "").strip()
                name_parts = clean_name.split()
                if name_parts:
                    last_name = normalize(name_parts[-1])
                    if len(last_name) > 3 and f" {last_name}" in window:
                        # Ensure it's not accidental by checking if "mr.", "ms.", "mrs.", "member", or "minister" precedes
                        if re.search(rf'\b(mr\.|ms\.|mrs\.|dr\.|minister|member)\s+{last_name}\b', window):
                            named = True
                            matched_formula = f"Formal Name ({last_name})"

        if named:
            hits += 1
            hit_details.append({
                "speaker": speaker_name,
                "formula": matched_formula,
                "window": window[-120:],
            })
        else:
            misses.append({
                "speaker": speaker_name,
                "riding": riding,
                "role": role,
                "located": pos != -1,
                "preceding_window": window[-120:] if pos != -1 else None,
            })

    print(f"\nHits: {hits} / {len(transitions)} ({hits / len(transitions) * 100:.1f}%)")

    # Save results to a report summary file in scratch
    out_file = Path("docs/watch/research/captions/samples/speaker_identification_results.json")
    results = {
        "sitting": "HoC Sitting No. 149 (2026-10-09)",
        "total_hansard_speeches": len(speeches),
        "total_member_transitions": len(transitions),
        "identified_hits": hits,
        "hit_percentage": round(hits / len(transitions) * 100, 1),
        "sample_hits": hit_details[:15],
        "sample_misses": misses[:15],
    }
    out_file.write_text(json.dumps(results, indent=2))
    print(f"Saved results to {out_file}")

if __name__ == "__main__":
    main()
