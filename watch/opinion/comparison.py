"""338Canada's own seat projection, read from the front page for comparison with ours."""

import re


MAIN_PARTIES = ("LPC", "CPC", "NDP", "GPC", "BQ")
SEATS_TOTAL = 343
BLOCK = re.compile(r"window\.indexseats_DATA = \{(.*?)\n\};", re.S)
DATES = re.compile(r"projDates:\s*\[([^\]]*)\]")
PARTY = re.compile(r"key:\s*'([A-Z]+)'")
VALUES = re.compile(r"values:\s*\[([^\]]*)\]")


def _last_value(chunk):
    match = VALUES.search(chunk)
    if match is None:
        return None
    values = [item.strip() for item in match.group(1).split(",") if item.strip()]
    return int(values[-1]) if values else None  # ValueError on a non-integer count


def parse_338_seats(html):
    """The last seat projection in 338Canada's index chart, PPC folded into OTH; None if the page does not have it."""
    text = html.decode("utf-8") if isinstance(html, bytes) else html
    block = BLOCK.search(text)
    if block is None:
        return None
    body = block.group(1)
    dates = DATES.search(body)
    if dates is None:
        return None
    days = re.findall(r"'(\d{4}-\d{2}-\d{2})'", dates.group(1))
    if not days:
        return None
    keys = list(PARTY.finditer(body))
    counts = {}
    for found, following in zip(keys, keys[1:] + [None]):
        end = following.start() if following else len(body)
        try:
            value = _last_value(body[found.end():end])
        except ValueError:
            return None
        if value is None:
            continue
        party = found.group(1)
        if party == "PPC":
            party = "OTH"
        if party in MAIN_PARTIES or party == "OTH":
            counts[party] = counts.get(party, 0) + value
    if any(party not in counts for party in MAIN_PARTIES):
        return None
    counts.setdefault("OTH", 0)
    if sum(counts.values()) != SEATS_TOTAL:
        return None
    ordered = {party: counts[party] for party in MAIN_PARTIES + ("OTH",)}
    return {"as_of": days[-1], "seats": ordered}
