"""Local Ollama embeddings and compact, normalized vector storage."""

import json
import math
import struct
from urllib.request import Request, urlopen


MODEL = 'paraphrase-multilingual'
URL = 'http://127.0.0.1:11436'


class EmbedError(Exception):
    pass


def embed(texts, url=URL, model=MODEL, timeout=120):
    request = Request(url.rstrip('/') + '/api/embed',
                      json.dumps({'model': model, 'input': texts}).encode(),
                      {'Content-Type': 'application/json'})
    try:
        with urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                raise EmbedError('embedding HTTP %s' % response.status)
            vectors = json.loads(response.read())['embeddings']
        if len(vectors) != len(texts):
            raise EmbedError('embedding count mismatch')
        return vectors
    except EmbedError:
        raise
    except Exception as exc:
        raise EmbedError(str(exc)) from exc


def pack(vec):
    length = math.sqrt(sum(x*x for x in vec))
    return struct.pack('<%de' % len(vec), *(x/length if length else 0.0 for x in vec))


def unpack(blob):
    return struct.unpack('<%de' % (len(blob)//2), blob)


def dot(a, b):
    return math.sumprod(a, b)


def loaded(url, model=MODEL, timeout=0.5):
    try:
        with urlopen(url.rstrip('/') + '/api/ps', timeout=timeout) as response:
            return any(str(row.get(key, '')).startswith(model)
                       for row in json.loads(response.read())['models'] for key in ('name', 'model'))
    except Exception:
        return False
