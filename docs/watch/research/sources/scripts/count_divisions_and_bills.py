#!/usr/bin/env python3
"""Count divisions and bills in the 45th Parliament across sources."""

import json
import time
import urllib.request
import xml.etree.ElementTree as ET

USER_AGENT = "ParTake-research/0.1 (personal project)"

def main():
    # 1. ourcommons votes
    print("1. Querying ourcommons.ca /Members/en/votes/xml ...")
    req = urllib.request.Request("https://www.ourcommons.ca/Members/en/votes/xml", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        tree = ET.fromstring(resp.read())
    ourcommons_votes = tree.findall("Vote")
    div_nums = [int(v.findtext("DecisionDivisionNumber")) for v in ourcommons_votes if v.findtext("DecisionDivisionNumber")]
    print(f"   ourcommons 45-1 divisions: count={len(ourcommons_votes)}, min={min(div_nums)}, max={max(div_nums)}")

    time.sleep(1)

    # 2. openparliament votes
    print("2. Querying api.openparliament.ca /votes/?session=45-1 ...")
    req = urllib.request.Request("https://api.openparliament.ca/votes/?session=45-1&format=json&limit=500", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    op_votes = data.get("objects", [])
    op_nums = [v["number"] for v in op_votes]
    print(f"   openparliament 45-1 divisions: count={len(op_votes)}, min={min(op_nums)}, max={max(op_nums)}")

    time.sleep(1)

    # 3. LEGISinfo bills
    print("3. Querying LEGISinfo at parl.ca /legisinfo/en/bills/json ...")
    req = urllib.request.Request("https://www.parl.ca/legisinfo/en/bills/json", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        legis_bills = json.loads(resp.read().decode("utf-8"))
    print(f"   LEGISinfo 45-1 bills: count={len(legis_bills)}")

    time.sleep(1)

    # 4. openparliament bills
    print("4. Querying api.openparliament.ca /bills/?session=45-1 ...")
    req = urllib.request.Request("https://api.openparliament.ca/bills/?session=45-1&format=json&limit=500", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    op_bills = data.get("objects", [])
    print(f"   openparliament 45-1 bills: count={len(op_bills)}")

if __name__ == "__main__":
    main()
