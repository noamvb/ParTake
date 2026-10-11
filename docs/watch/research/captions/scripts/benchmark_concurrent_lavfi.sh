#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="/home/deck/.gemini/antigravity-cli/brain/b9fddf34-2543-4f71-9e57-15afe8bf834d/scratch"
mkdir -p "$SCRATCH"

URL1="movie='https\://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4\:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng'[out0+subcc]"
URL2="movie='https\://parlvuvod01.azureedge.net/pvvodhoc-fr/_definst_/mp4\:azrhoc02/archives/PV750/2026/2026-10-09/45735_HoC%20Sitting%20No.%20149_10-00-34_VL.mp4/playlist.m3u8?audioindex=0&wowzalanguage=fra'[out0+subcc]"
URL3="movie='https\://parlvuvod01.azureedge.net/pvvodhoc-en/_definst_/mp4\:azrhoc02/archives/PV750/2026/2026-10-08/45870_FINA%20Meeting%20No.%2053_10-00-19_VL.mp4/playlist.m3u8?audioindex=1&wowzalanguage=eng'[out0+subcc]"

DURATION=120

echo "=== Running 3 concurrent streams with Method 1 (ffmpeg lavfi) ==="
ffmpeg -f lavfi -i "$URL1" -t "$DURATION" -map 0:1 -c:s srt "$SCRATCH/out1.srt" -y &
P1=$!
ffmpeg -f lavfi -i "$URL2" -t "$DURATION" -map 0:1 -c:s srt "$SCRATCH/out2.srt" -y &
P2=$!
ffmpeg -f lavfi -i "$URL3" -t "$DURATION" -map 0:1 -c:s srt "$SCRATCH/out3.srt" -y &
P3=$!

wait "$P1"
wait "$P2"
wait "$P3"
echo "Method 1 complete."
