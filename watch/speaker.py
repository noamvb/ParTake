"""Conservative speaker labels and calls from English live captions."""

from difflib import SequenceMatcher
import re

from watch.records import _normal


PRESIDING = ('The Speaker', 'The Chair', 'The Deputy Speaker',
             'The Assistant Deputy Speaker', 'The Acting Speaker', 'The Clerk', 'The Vice-Chair')
INTERPRETERS = ('Interpreter', 'Voice of Interpreter')
LABEL = re.compile(r'^\s*(?:>>\s*)?[\[(]?\s*([^:()\[\]]+?)\s*[\])]?\s*:', re.I)


def label(speech_text):
    match = LABEL.match(speech_text)
    if match:
        for name in PRESIDING + INTERPRETERS:
            if _normal(match[1]) == _normal(name):
                return name
    return None


def _call_normal(text):
    text = re.sub(r'[^\w\s]', ' ', _normal(text))
    return ' '.join({'st': 'saint', 'ste': 'sainte'}.get(word, word) for word in text.split())


class CallIndex:
    def __init__(self, members_rows, ministries_rows):
        self.members, self.ridings, self.lasts, self.titles = {}, {}, {}, {}
        for person, name, party, riding, province, first, last in members_rows:
            self.members[person] = name
            self.ridings.setdefault(_call_normal(riding), set()).add(person)
            self.lasts.setdefault(_call_normal(last), set()).add(person)
        for person, title, precedence in ministries_rows:
            self.titles.setdefault(_call_normal(title), set()).add(person)

    def call(self, text, committee=False):
        # Keep sentence boundaries for fuzzy riding calls, but not the dot in St.
        text = re.sub(r'\b(st|ste)\.', r'\1', _normal(text))
        calls = []
        for match in re.finditer(r'\bmember\s+for\s+', text):
            tail = re.split(r'[.!?]|\bmember\s+for\b', text[match.end():], maxsplit=1)[0]
            tail = re.sub(r'\[[^\]]*\]|\([^)]*\)', ' ', tail)
            tail = re.split(r',\s*go ahead\b|\bwith\s+(?:\d+|one|two|three|four|five)\b', tail, maxsplit=1)[0]
            query = _call_normal(tail)
            exact = [(len(riding), persons) for riding, persons in self.ridings.items()
                     if query == riding or query.startswith(riding + ' ')]
            if exact:
                persons = max(exact, key=lambda item: item[0])[1]
                result = (next(iter(persons)), 0.9, 'riding') if len(persons) == 1 else None
            else:
                scores = sorted(((SequenceMatcher(None, query, riding).ratio(), persons)
                                 for riding, persons in self.ridings.items()), key=lambda item: item[0], reverse=True)
                result = None
                if scores and scores[0][0] >= 0.85 and (len(scores) < 2 or scores[0][0] - scores[1][0] >= 0.05):
                    persons = scores[0][1]
                    if len(persons) == 1:
                        result = (next(iter(persons)), 0.75, 'riding')
            calls.append((match.start(), result))
        normal = _call_normal(text)
        # Positions below are in the same punctuation-free text for all call types.
        calls = [(len(_call_normal(text[:position]).split()), result) for position, result in calls]
        for match in re.finditer(r'\b(?:minister (?:of|for) |prime minister\b)', normal):
            tail = normal[match.start():]
            tail = re.sub(r'^minister for ', 'minister of ', tail)
            exact = [(len(title), persons) for title, persons in self.titles.items()
                     if tail == title or tail.startswith(title + ' ')]
            result = None
            if exact:
                persons = max(exact, key=lambda item: item[0])[1]
                if len(persons) == 1:
                    result = (next(iter(persons)), 0.85, 'portfolio')
            calls.append((len(normal[:match.start()].split()), result))
        if committee:
            for match in re.finditer(r'\b(?:mr|mrs|ms|madam|madame|monsieur|dr)\s+', normal):
                tail = normal[match.end():]
                exact = [(len(last), persons) for last, persons in self.lasts.items()
                         if tail == last or tail.startswith(last + ' ')]
                result = None
                if exact:
                    persons = max(exact, key=lambda item: item[0])[1]
                    if len(persons) == 1:
                        result = (next(iter(persons)), 0.6, 'surname')
                calls.append((len(normal[:match.start()].split()), result))
        return max(calls, key=lambda item: item[0])[1] if calls else None
