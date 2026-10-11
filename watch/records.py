"""Pure bilingual transcript, speaker and legislative record parsers."""

from datetime import datetime, timezone
import json
import re
import unicodedata
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo


SESSION = "45-1"
OTTAWA = ZoneInfo("America/Toronto")


def _text(element):
    return " ".join("".join(element.itertext()).split()) if element is not None else ""


def _utc(value):
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_transcript(en, fr, *, source, number, committee=None):
    root, french = ET.fromstring(en), ET.fromstring(fr)
    metadata = {e.get("Name"): _text(e) for e in root.iter("ExtractedItem")}
    date = "{:04d}-{:02d}-{:02d}".format(*(int(metadata["MetaDateNum" + key]) for key in ("Year", "Month", "Day")))
    evidence = source == "evidence"
    document_id = f"evidence/{SESSION}/{committee}/{number}" if evidence else f"hansard/{SESSION}/{number}"
    path = f"{committee}/meeting-{number}/evidence" if evidence else f"house/sitting-{number}/hansard"
    document = dict(id=document_id, source=source, session=SESSION, number=int(number),
                    committee=committee, date=date, url=f"https://www.ourcommons.ca/DocumentViewer/en/{SESSION}/{path}")
    translations = {e.get("id"): _text(e) for e in french.iter("ParaText")}
    owners = {p: intervention for intervention in root.iter("Intervention") for p in intervention.iter("ParaText")}
    timestamp = next(root.iter("Timestamp"), None)
    lang, order, subject = "en", "", ""
    paragraphs = []
    for element in root.iter():
        if element.tag == "Timestamp":
            timestamp = element
        elif element.tag == "FloorLanguage":
            lang = element.get("language", "en").lower()
        elif element.tag == "OrderOfBusinessTitle":
            order, subject = _text(element), ""
        elif element.tag == "SubjectOfBusinessTitle":
            subject = _text(element)
        elif element.tag == "ParaText" and element in owners:
            intervention = owners[element]
            affiliation = intervention.find("PersonSpeaking/Affiliation")
            hour, minute = (timestamp.get("Hr"), timestamp.get("Mn")) if timestamp is not None else ("0", "0")
            at = datetime.fromisoformat(date).replace(hour=int(hour), minute=int(minute), tzinfo=OTTAWA)
            paragraphs.append(dict(id=("e" if evidence else "h") + element.get("id"),
                                   document=document_id, intervention=intervention.get("id"), position=len(paragraphs),
                                   text_en=_text(element), text_fr=translations.get(element.get("id"), ""),
                                   lang=lang, at=_utc(at), title=f"{committee}, meeting {number}" if evidence else order + (" - " + subject if subject else ""),
                                   speaker=_text(affiliation).rstrip(": ") or None,
                                   db_id=affiliation.get("DbId") if affiliation is not None else None,
                                   source=source, person_id=None))
    return document, paragraphs


def _normal(value):
    return " ".join("".join(c for c in unicodedata.normalize("NFKD", value.casefold())
                            if not unicodedata.combining(c)).split())


HONORIFIC = re.compile(r"^(?:The\s+)?(?:Right Hon\.|Hon\.|Mr\.|Mrs\.|Ms\.|Miss|Dr\.)\s+", re.I)


class SpeakerIndex:
    def __init__(self, members_rows, ministries_rows):
        self.ridings, self.names, self.lasts, self.titles = {}, {}, {}, {}
        for row in members_rows:
            for index, value in ((self.ridings, row[3]), (self.names, row[5] + " " + row[6]), (self.lasts, row[6])):
                index.setdefault(_normal(value), set()).add(row[0])
        for person, title, precedence in ministries_rows:
            self.titles.setdefault(_normal(title), set()).add(person)

    def resolve(self, speaker_text, db_id, cache):
        if db_id is not None and db_id in cache:
            return cache[db_id]
        text, groups, outer, stack = speaker_text or "", [], [], []
        for position, char in enumerate(text):
            if char == "(":
                stack.append(position)
            elif char == ")" and stack:
                groups.append(text[stack.pop() + 1:position])
            elif not stack:
                outer.append(char)
        outer = "".join(outer).strip()

        def unique(index, value):
            values = index.get(_normal(value), set())
            return next(iter(values)) if len(values) == 1 else None

        person = None
        for group in groups:
            if "," in group:
                person = unique(self.ridings, group.rsplit(",", 1)[0])
                if person:
                    break
        if person is None:
            for value in [outer] + groups:
                value = HONORIFIC.sub("", value.strip(), count=1)
                person = unique(self.names, value) or unique(self.titles, value)
                if person:
                    break
        if person is None and HONORIFIC.match(outer):
            person = unique(self.lasts, HONORIFIC.sub("", outer, count=1))
        if person is not None and db_id is not None:
            cache[db_id] = person
        return person


def parse_divisions(body):
    rows = []
    for vote in ET.fromstring(body).findall("Vote"):
        number = int(vote.findtext("DecisionDivisionNumber"))
        result = vote.findtext("DecisionResultName")
        bill = vote.findtext("BillNumberCode")
        rows.append(dict(id=f"{SESSION}/{number}", number=number,
                         at=_utc(datetime.fromisoformat(vote.findtext("DecisionEventDateTime")).replace(tzinfo=OTTAWA)),
                         bill=f"{SESSION}/{bill}" if bill else None,
                         description=vote.findtext("DecisionDivisionSubject"),
                         result={"Agreed To": "agreed", "Negatived": "negatived", "Tie": "tie"}.get(result, result.lower()),
                         **{key: int(vote.findtext("DecisionDivisionNumberOf" + label))
                            for key, label in (("yeas", "Yeas"), ("nays", "Nays"), ("paired", "Paired"))}))
    return rows


def parse_ballots(body):
    return [dict(person_id=row.findtext("PersonId"), party=row.findtext("CaucusShortName"),
                 vote=row.findtext("VoteValueName").lower())
            for row in ET.fromstring(body).findall("VoteParticipant")]


def _stage_time(value):
    if not value or value.startswith("0001-01-01"):
        return None
    at = datetime.fromisoformat(value)
    # LEGISinfo's list encodes a UTC wall reading with an Ottawa offset.
    if at.tzinfo is not None:
        at = at.astimezone(timezone.utc).replace(tzinfo=None)
    return _utc(at.replace(tzinfo=OTTAWA))


def parse_bill_stages(body):
    rows = []
    fields = [("Passed" + chamber.title() + ordinal + "ReadingDateTime", ordinal + " reading", chamber)
              for chamber in ("house", "senate") for ordinal in ("First", "Second", "Third")]
    fields.append(("ReceivedRoyalAssentDateTime", "Royal assent", "senate"))
    for bill in json.loads(body):
        bill_id = f'{bill["ParliamentNumber"]}-{bill["SessionNumber"]}/{bill["NumberCode"]}'
        seen = set()
        for field, stage, chamber in fields:
            at = _stage_time(bill.get(field))
            if at:
                rows.append(dict(bill=bill_id, stage=stage, chamber=chamber, at=at))
                seen.add((stage, chamber))
        at = _stage_time(bill.get("LatestCompletedBillStageDateTime"))
        stage = bill.get("LatestCompletedBillStageNameEn")
        chamber = {"House of Commons": "house", "Senate": "senate"}.get(bill.get("LatestCompletedBillStageChamberNameEn"))
        if at and stage and chamber and (stage, chamber) not in seen:
            rows.append(dict(bill=bill_id, stage=stage, chamber=chamber, at=at))
    return rows
