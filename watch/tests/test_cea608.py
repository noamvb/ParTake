"""The Python decoder must reproduce the shared Dart decoder fixture."""

import json
from pathlib import Path
import unittest

from watch.cea608 import Decoder, decode, extract_cc_pairs


FIXTURES = Path(__file__).parent / "fixtures"


class DecoderTests(unittest.TestCase):
    def test_shared_decoder_oracle(self):
        decoder = Decoder()
        changes = []
        for number in (27, 28):
            changes.extend(decode((FIXTURES / f"hls-45735-media_{number}.ts").read_bytes(), decoder))
        oracle = json.loads((FIXTURES / "cea608-oracle-45735-27-28.json").read_text())
        self.assertEqual([list(change) for change in changes], oracle)

    def test_extract_pairs(self):
        pairs = extract_cc_pairs((FIXTURES / "hls-45735-media_27.ts").read_bytes())
        self.assertTrue(pairs)
        self.assertTrue(all(isinstance(pair[0], int) for pair in pairs))
        self.assertEqual([pair[0] for pair in pairs], sorted(pair[0] for pair in pairs))

    def test_fresh_segment(self):
        body = (FIXTURES / "hls-45735-media_28.ts").read_bytes()
        first_pts = extract_cc_pairs(body)[0][0]
        changes = decode(body)
        self.assertTrue(changes)
        self.assertTrue(all(pts >= first_pts for pts, text in changes))
