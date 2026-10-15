"""PMO article body extraction and itinerary parsing."""

from html.parser import HTMLParser
import re


class _Body(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.depth = 0
        self.parts = []
        self.found = False

    def handle_starttag(self, tag, attrs):
        if tag == 'div':
            if self.depth:
                self.depth += 1
            elif dict(attrs).get('property') == 'schema:text':
                self.depth = 1
                self.found = True
                return
        if self.depth:
            self.parts.append(self.get_starttag_text())

    def handle_endtag(self, tag):
        if tag == 'div' and self.depth:
            self.depth -= 1
            if not self.depth:
                return
        if self.depth:
            self.parts.append('</%s>' % tag)

    def handle_data(self, data):
        if self.depth:
            self.parts.append(data)

    def handle_entityref(self, name):
        self.handle_data('&%s;' % name)

    def handle_charref(self, name):
        self.handle_data('&#%s;' % name)


def article_body(html):
    parser = _Body()
    parser.feed(html)
    if parser.found:
        return ''.join(parser.parts)
    if re.search(r'<(?:html|article)\b', html, re.I):
        raise ValueError('PMO article body not found')
    return html


class _Blocks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.blocks = []

    def handle_starttag(self, tag, attrs):
        if tag in ('h2', 'p', 'li'):
            for frame in self.stack:
                frame['child'] = True
            self.stack.append(dict(tag=tag, text=[], child=False))
        elif tag == 'br':
            self.handle_data(', ')

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1]['tag'] == tag:
            frame = self.stack.pop()
            if not frame['child']:
                text = ' '.join(''.join(frame['text']).split())
                if text:
                    self.blocks.append((tag, text))

    def handle_data(self, data):
        for frame in self.stack:
            frame['text'].append(data)


TIME = re.compile(r'^(?:(\d{1,2}):(\d{2})\s*([ap])\.?m\.?|noon)\s*', re.I)


def parse_itinerary(html: str) -> dict:
    parser = _Blocks()
    parser.feed(article_body(html))
    notes, events = [], []
    place, event, media_notes = '', None, False
    for tag, text in parser.blocks:
        if text.lower().startswith('note: all times local'):
            continue
        if tag == 'h2':
            place, event, media_notes = text, None, False
            continue
        match = TIME.match(text) if tag == 'p' else None
        if match:
            hour = int(match[1]) % 12 + (12 if match[3].lower() == 'p' else 0) if match[1] else 12
            minute = int(match[2]) if match[2] else 0
            event = dict(local_time='%02d:%02d' % (hour, minute), place=place,
                         text=text[match.end():].strip(), venue=None, media=None)
            events.append(event)
            media_notes = False
            continue
        lower = text.lower()
        media = ('pool' if re.search(r'\bpool(?:ed)?\b', lower) else
                 'closed' if 'closed to media' in lower else
                 'open' if 'open to media' in lower or 'open coverage' in lower else None)
        if event and media:
            event['media'] = media
            media_notes = True
        elif event and re.match(r'notes? for media', lower):
            media_notes = True
        elif event and not media_notes:
            event['venue'] = ', '.join(filter(None, (event['venue'], text)))
        elif not event:
            notes.append(text)
    return dict(notes=notes, events=events)
