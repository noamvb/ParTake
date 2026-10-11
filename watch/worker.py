"""Run one durable embedding and matching pass."""

import argparse
from datetime import datetime, timezone
import json
import sys

from watch import embed, fixup, match, segment, store
from watch.speaker import CallIndex


def main(argv=None):
    parser = argparse.ArgumentParser(description='Embed and match Parliament watch history')
    parser.add_argument('--data', default=store.DEFAULT_DATA)
    parser.add_argument('--ollama', default=embed.URL)
    parser.add_argument('--batch', type=int, default=32)
    parser.add_argument('--max-batches', type=int)
    args = parser.parse_args(argv)
    with store.connect(args.data) as db:
        now = datetime.now(timezone.utc)
        counts = {}
        for name, run in (
                ('segment', lambda: segment.segment_all(db, CallIndex(db.execute('SELECT * FROM members'), db.execute('SELECT * FROM ministries')))),
                ('fixup', lambda: fixup.fixup(db, now))):
            error = None
            try:
                counts[name] = run()
                db.commit()
            except Exception as exc:
                db.rollback()
                error = str(exc)
                counts[name] = None
            store.set_meta(db, 'source:' + name, json.dumps({'at': store.iso(now), 'ok': error is None, 'error': error}))
            db.commit()
        result = match.sync(db, lambda texts: embed.embed(texts, url=args.ollama),
                            batch=args.batch, max_batches=args.max_batches)
        result.update(counts)
        error = result.get('embed_error')
        store.set_meta(db, 'source:embed', json.dumps({
            'at': store.iso(datetime.now(timezone.utc)), 'ok': error is None, 'error': error}))
        db.commit()
    print(json.dumps(result), file=sys.stderr)
    return 1 if error is not None else 0


if __name__ == '__main__':
    sys.exit(main())
