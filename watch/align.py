"""Match official intervention openings to caption lines, without interpolation."""

from bisect import bisect_left, bisect_right
from datetime import datetime
import re


TOKENS = re.compile(r"[a-z0-9']+")
REMOVE = re.compile(r'voice of interpreter|voice of interpretor|speaking in french|speaking in english')


def _normalise(text):
    return TOKENS.findall(REMOVE.sub(' ', text.lower()))


def align(interventions, lines):
    words, times, begins = [], [], []
    for line in lines:
        tokens = _normalise(line['text'])
        words.extend(tokens)
        times.extend([datetime.fromisoformat(line['begin']).timestamp()] * len(tokens))
        begins.extend([line['begin']] * len(tokens))
    result, last_match = {}, None
    for intervention in interventions:
        result[intervention['id']] = None
        tokens = _normalise(intervention['text'])
        if len(tokens) < 8:
            continue
        key = tokens[:8]
        at = datetime.fromisoformat(intervention['at']).timestamp()
        lower = max(at - 60, last_match) if last_match is not None else at - 60
        start, end = bisect_left(times, lower), bisect_right(times, at + 420)
        best_score, best = -1, None
        for position in range(start, end):
            score = sum(a == b for a, b in zip(key, words[position:position + 8]))
            if score > best_score:
                best_score, best = score, position
        if best_score >= 5:
            result[intervention['id']] = begins[best]
            last_match = times[best]
    return result
