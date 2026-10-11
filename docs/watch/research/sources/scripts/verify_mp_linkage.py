#!/usr/bin/env python3
"""Demonstrate cross-source MP identifier linkage for three MPs."""

import json
import time
import urllib.request
import xml.etree.ElementTree as ET

USER_AGENT = "ParTake-research/0.1 (personal project)"

MPS_TO_CHECK = [
    {
        "last_name": "Carney",
        "op_slug": "mark-carney",
        "expected_riding": "Nepean",
        "caption_portfolio": "the Prime Minister",
        "caption_riding": "the member for Nepean"
    },
    {
        "last_name": "Michel",
        "op_slug": "marjorie-michel",
        "expected_riding": "Papineau",
        "caption_portfolio": "the Minister of Health",
        "caption_riding": "the member for Papineau"
    },
    {
        "last_name": "Morin",
        "op_slug": "billy-morin",
        "expected_riding": "Edmonton Northwest",
        "caption_portfolio": None,
        "caption_riding": "the member for Edmonton Northwest"
    }
]

def main():
    # 1. Fetch ourcommons members list
    print("1. Fetching ourcommons.ca member list (/Members/en/search/XML)...")
    req = urllib.request.Request("https://www.ourcommons.ca/Members/en/search/XML", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        members_tree = ET.fromstring(resp.read())
    time.sleep(1)

    # 2. Fetch ourcommons ministries list
    print("2. Fetching ourcommons.ca ministries list (/Members/en/ministries/XML)...")
    req = urllib.request.Request("https://www.ourcommons.ca/Members/en/ministries/XML", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        ministries_tree = ET.fromstring(resp.read())
    time.sleep(1)

    # 3. Fetch ourcommons vote 178
    print("3. Fetching ourcommons.ca vote 178 (/Members/en/votes/45/1/178/xml)...")
    req = urllib.request.Request("https://www.ourcommons.ca/Members/en/votes/45/1/178/xml", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        vote_tree = ET.fromstring(resp.read())
    time.sleep(1)

    # Build maps
    members_by_pid = {}
    for m in members_tree.findall("MemberOfParliament"):
        pid = m.findtext("PersonId")
        members_by_pid[pid] = {
            "first": m.findtext("PersonOfficialFirstName"),
            "last": m.findtext("PersonOfficialLastName"),
            "honorific": m.findtext("PersonShortHonorific"),
            "riding": m.findtext("ConstituencyName"),
            "caucus": m.findtext("CaucusShortName"),
        }

    ministers_by_pid = {}
    for m in ministries_tree.findall("Minister"):
        pid = m.findtext("PersonId")
        ministers_by_pid[pid] = m.findtext("Title")

    votes_by_pid = {}
    for p in vote_tree.findall("VoteParticipant"):
        pid = p.findtext("PersonId")
        votes_by_pid[pid] = p.findtext("VoteValueName")

    print("\nCross-Source Linkage Results:")
    print("=" * 80)

    for item in MPS_TO_CHECK:
        slug = item["op_slug"]
        print(f"\n--- MP: {item['last_name']} (openparliament slug: {slug}) ---")

        # Query openparliament API for this politician
        op_url = f"https://api.openparliament.ca/politicians/{slug}/?format=json"
        req = urllib.request.Request(op_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req) as resp:
            op_data = json.loads(resp.read().decode("utf-8"))
        time.sleep(1)

        parl_mp_ids = op_data.get("other_info", {}).get("parl_mp_id", [])
        parl_affil_ids = op_data.get("other_info", {}).get("parl_affil_id", [])
        name = op_data.get("name")
        print(f"  openparliament Name: {name}")
        print(f"  openparliament URL: {op_data.get('url')}")
        print(f"  openparliament other_info.parl_mp_id: {parl_mp_ids}")
        print(f"  openparliament other_info.parl_affil_id: {parl_affil_ids}")

        pid = parl_mp_ids[0] if parl_mp_ids else None
        if pid and pid in members_by_pid:
            m = members_by_pid[pid]
            print(f"  ourcommons PersonId: {pid}")
            print(f"  ourcommons Official Name: {m['honorific']} {m['first']} {m['last']}")
            print(f"  ourcommons Riding: {m['riding']}")
            print(f"  ourcommons Caucus: {m['caucus']}")
        else:
            print(f"  ourcommons PersonId: NOT FOUND")

        ministerial_role = ministers_by_pid.get(pid, "None (not in cabinet)")
        print(f"  ourcommons Ministerial Role: {ministerial_role}")

        vote_val = votes_by_pid.get(pid, "Not recorded")
        print(f"  ourcommons Division 178 Vote: {vote_val}")

        print(f"  Captions Portfolio Form: \"{item['caption_portfolio']}\"")
        print(f"  Captions Riding Form: \"{item['caption_riding']}\"")

if __name__ == "__main__":
    main()
