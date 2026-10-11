#!/usr/bin/env python3
"""Fetch, format, and save all reference samples for research report."""

import gzip
import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

USER_AGENT = "ParTake-research/0.1 (personal project)"
SAMPLES_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "samples")

def get(url):
    print(f"Fetching {url} ...")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        data = resp.read()
    time.sleep(1)
    return data

def save_text(rel_path, text):
    path = os.path.join(SAMPLES_DIR, rel_path)
    # Ensure unix newlines and no trailing whitespace on any line
    lines = [line.rstrip() for line in text.splitlines()]
    clean_text = "\n".join(lines) + "\n"
    with open(path, "w", encoding="utf-8") as f:
        f.write(clean_text)
    size = os.path.getsize(path)
    print(f"  Saved {rel_path} ({size} bytes)")
    if size > 200 * 1024:
        raise ValueError(f"File {rel_path} exceeds 200 KB limit ({size} bytes)")

def save_gz(rel_path, raw_bytes):
    path = os.path.join(SAMPLES_DIR, rel_path)
    with gzip.open(path, "wb") as f:
        f.write(raw_bytes)
    size = os.path.getsize(path)
    print(f"  Saved {rel_path} ({size} bytes gzipped)")
    if size > 200 * 1024:
        raise ValueError(f"File {rel_path} exceeds 200 KB limit ({size} bytes)")

def main():
    os.makedirs(SAMPLES_DIR, exist_ok=True)

    # 1. ourcommons House Sitting 001 (Full, May 26, 2025 opening)
    data = get("https://www.ourcommons.ca/Content/House/451/Debates/001/HAN001-E.XML")
    save_gz("ourcommons-hansard-sitting-001.xml.gz", data)

    # 2. ourcommons House Sitting 149 (Truncated, Oct 9, 2026 latest)
    data = get("https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-E.XML")
    text = data.decode("utf-8", errors="replace")
    # Truncate after first ~10 interventions (around line 250 or 50KB)
    cutoff = text.find("</Intervention>\r\n          <Timestamp Hr=\"10\" Mn=\"35\">")
    if cutoff == -1:
        cutoff = text.find("</Intervention>\n          <Timestamp Hr=\"10\" Mn=\"35\">")
    if cutoff == -1:
        # Fallback to after 5 interventions
        matches = [m.end() for m in re.finditer(r"</Intervention>", text)]
        cutoff = matches[5] if len(matches) > 5 else 30000
    truncated_xml = text[:cutoff] + "</Intervention>\n        </SubjectOfBusinessContent>\n      </SubjectOfBusiness>\n    </OrderOfBusiness>\n  </HansardBody>\n</Hansard>\n"
    save_gz("ourcommons-hansard-sitting-149-truncated.xml.gz", truncated_xml.encode("utf-8"))
    save_text("ourcommons-hansard-sitting-149-truncated.xml.note.txt",
              f"Original sitting 149 XML (HAN149-E.XML) was {len(data)} bytes (>200 KB limit).\n"
              "Truncated after the initial second-reading debate on Bill C-37 (First Nations Clean Water Act)\n"
              "and cleanly closed with </HansardBody></Hansard>.\n"
              "Original URL: https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-E.XML")

    # 3. openparliament House Sitting 149 debate metadata
    data = get("https://api.openparliament.ca/debates/2026/10/9/?format=json")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-debate-sitting-149.json", json.dumps(obj, indent=2))

    # 4. openparliament House Sitting 149 speeches (first 20)
    data = get("https://api.openparliament.ca/speeches/?document=%2Fdebates%2F2026%2F10%2F9%2F&format=json&limit=20")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-speeches-sitting-149-truncated.json", json.dumps(obj, indent=2))
    save_text("openparliament-speeches-sitting-149-truncated.json.note.txt",
              "Speeches list truncated to first 20 speeches via limit=20 query parameter to keep payload under 200 KB.\n"
              "Follow pagination.next_url for subsequent pages.\n"
              "Original URL: https://api.openparliament.ca/speeches/?document=/debates/2026/10/9/&format=json&limit=20")

    # 5. ourcommons Committee Evidence INDU Meeting 50
    data = get("https://www.ourcommons.ca/Content/Committee/451/INDU/Evidence/EV14246706/INDUEV50-E.XML")
    save_gz("ourcommons-evidence-indu-meeting-50.xml.gz", data)

    # 6. openparliament Committee Meeting INDU 50 metadata
    data = get("https://api.openparliament.ca/committees/industry-and-technology/45-1/50/?format=json")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-evidence-indu-meeting-50.json", json.dumps(obj, indent=2))

    # 7. openparliament Committee Meeting INDU 50 speeches (first 20)
    data = get("https://api.openparliament.ca/speeches/?document=%2Fcommittees%2Findustry-and-technology%2F45-1%2F50%2F&format=json&limit=20")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-evidence-speeches-indu-meeting-50-truncated.json", json.dumps(obj, indent=2))
    save_text("openparliament-evidence-speeches-indu-meeting-50-truncated.json.note.txt",
              "Committee evidence speeches truncated to first 20 speeches via limit=20 query parameter to keep payload under 200 KB.\n"
              "Follow pagination.next_url for subsequent pages.\n"
              "Original URL: https://api.openparliament.ca/speeches/?document=/committees/industry-and-technology/45-1/50/&format=json&limit=20")

    # 8. ourcommons Division 178 (truncated to 20 participants)
    data = get("https://www.ourcommons.ca/Members/en/votes/45/1/178/xml")
    text = data.decode("utf-8", errors="replace")
    tree = ET.fromstring(data)
    participants = tree.findall("VoteParticipant")
    total_participants = len(participants)
    # keep first 20 participants
    new_root = ET.Element("ArrayOfVoteParticipant")
    for p in participants[:20]:
        new_root.append(p)
    truncated_xml = ET.tostring(new_root, encoding="utf-8", xml_declaration=True)
    save_gz("ourcommons-vote-178-truncated.xml.gz", truncated_xml)
    save_text("ourcommons-vote-178-truncated.xml.note.txt",
              f"Original division 178 XML contained {total_participants} VoteParticipant records ({len(data)} bytes, >200 KB limit).\n"
              "Truncated to first 20 VoteParticipant elements and cleanly closed with </ArrayOfVoteParticipant>.\n"
              "Original URL: https://www.ourcommons.ca/Members/en/votes/45/1/178/xml")

    # 9. openparliament Division 178 metadata
    data = get("https://api.openparliament.ca/votes/45-1/178/?format=json")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-vote-178.json", json.dumps(obj, indent=2))

    # 10. openparliament Division 178 ballots (first 20)
    data = get("https://api.openparliament.ca/votes/ballots/?vote=%2Fvotes%2F45-1%2F178%2F&format=json&limit=20")
    obj = json.loads(data.decode("utf-8"))
    save_text("openparliament-ballots-vote-178-truncated.json", json.dumps(obj, indent=2))
    save_text("openparliament-ballots-vote-178-truncated.json.note.txt",
              "Per-MP ballots truncated to first 20 ballots via limit=20 query parameter to keep payload under 200 KB.\n"
              "Original URL: https://api.openparliament.ca/votes/ballots/?vote=/votes/45-1/178/&format=json&limit=20")

    # 11. LEGISinfo Bill C-37 JSON
    data = get("https://www.parl.ca/legisinfo/en/bill/45-1/c-37/json")
    obj = json.loads(data.decode("utf-8"))
    save_text("legisinfo-bill-c37.json", json.dumps(obj, indent=2))

    # 12. LEGISinfo Bill C-37 XML
    data = get("https://www.parl.ca/legisinfo/en/bill/45-1/c-37/xml")
    save_gz("legisinfo-bill-c37.xml.gz", data)

    # 13. ourcommons Member List (Full 338 MPs)
    data = get("https://www.ourcommons.ca/Members/en/search/XML")
    save_gz("ourcommons-members-list.xml.gz", data)
    save_text("ourcommons-members-list.note.txt",
              f"Complete machine-readable XML list of all 338 current Members of Parliament ({len(data)} bytes uncompressed).\n"
              "Contains PersonId, PersonOfficialFirstName, PersonOfficialLastName, PersonShortHonorific,\n"
              "ConstituencyName, ConstituencyProvinceTerritoryName, CaucusShortName, FromDateTime.\n"
              "Original URL: https://www.ourcommons.ca/Members/en/search/XML")

    # 14. ourcommons Ministries List (Full 38 Ministers)
    data = get("https://www.ourcommons.ca/Members/en/ministries/XML")
    save_gz("ourcommons-ministries-list.xml.gz", data)
    save_text("ourcommons-ministries-list.note.txt",
              f"Complete machine-readable XML list of all 38 Ministers and Secretaries of State ({len(data)} bytes uncompressed).\n"
              "Contains PersonId, PersonOfficialFirstName, PersonOfficialLastName, PersonShortHonorific, Title (portfolio),\n"
              "OrderOfPrecedence, ProvinceTerritoryName, FromDateTime, ToDateTime.\n"
              "Original URL: https://www.ourcommons.ca/Members/en/ministries/XML")

    print("\nAll samples successfully fetched and saved!")

if __name__ == "__main__":
    main()
