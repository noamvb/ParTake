#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="/home/deck/.gemini/antigravity-cli/brain/b9fddf34-2543-4f71-9e57-15afe8bf834d/scratch"
mkdir -p "$SCRATCH"

URL1="https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng"
URL2="https://parlvuvod01.azureedge.net/pvvodhoc-fr/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=0&wowzalanguage=fra"
URL3="https://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4:azrhoc02/archives/PV750/2026/2026-10-08/45870_FINA%20Meeting%20No.%2053_10-00-19_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng"

DURATION=120

echo "=== Running 3 concurrent streams with Method 2 (-c copy + Annex B extractor) ==="
ffmpeg -v error -i "$URL1" -t "$DURATION" -map 0:v -c:v copy -f h264 - | python3 "$DIR/extract_608_annexb.py" > "$SCRATCH/out1.txt" &
P1=$!
ffmpeg -v error -i "$URL2" -t "$DURATION" -map 0:v -c:v copy -f h264 - | python3 "$DIR/extract_608_annexb.py" > "$SCRATCH/out2.txt" &
P2=$!
ffmpeg -v error -i "$URL3" -t "$DURATION" -map 0:v -c:v copy -f h264 - | python3 "$DIR/extract_608_annexb.py" > "$SCRATCH/out3.txt" &
P3=$!

wait "$P1"
wait "$P2"
wait "$P3"
echo "Method 2 complete."
