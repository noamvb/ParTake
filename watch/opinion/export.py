"""Export the running polls API to a public, static JSON snapshot."""

import argparse
import json
from pathlib import Path
import shutil
import tempfile
from urllib.parse import quote
from urllib.request import urlopen


def _fetch(url):
    with urlopen(url, timeout=30) as response:
        return response.read()


def export(api_base: str, out_dir: Path, fetch=None) -> int:
    """Replace out_dir only after every API response has been fetched and parsed."""
    fetch = fetch or _fetch
    api_base = api_base.rstrip("/")
    out_dir = Path(out_dir)
    out_dir.parent.mkdir(parents=True, exist_ok=True)

    def get(path):
        return json.loads(fetch(api_base + "/api/polls/" + path))

    with tempfile.TemporaryDirectory(prefix=out_dir.name + "-", dir=out_dir.parent) as temp:
        snapshot = Path(temp) / "snapshot"
        snapshot.mkdir()
        written = 0

        def write(path, data):
            nonlocal written
            target = snapshot / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                              encoding="utf-8")
            written += 1

        write("summary.json", get("summary"))
        write("leaders.json", get("leaders"))
        list_path = "list?region=CAN&limit=200"
        first = get(list_path)
        cursor = first["next"]
        while cursor is not None:
            page = get(list_path + "&before=" + quote(cursor, safe=""))
            first["polls"].extend(page["polls"])
            cursor = page["next"]
        first["next"] = None
        write("list.json", first)
        ridings = get("ridings")
        write("ridings.json", ridings)
        (snapshot / "ridings").mkdir(exist_ok=True)
        for riding in ridings["ridings"]:
            riding_id = riding["id"]
            write("ridings/" + riding_id + ".json",
                  get("ridings/" + quote(riding_id, safe="")))
        if out_dir.exists():
            shutil.rmtree(out_dir)
        snapshot.rename(out_dir)
        return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api", required=True)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    count = export(args.api, args.out)
    print(f"wrote {count} files to {args.out}")


if __name__ == "__main__":
    main()
