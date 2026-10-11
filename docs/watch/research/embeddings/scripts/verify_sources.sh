#!/usr/bin/env bash
# Verify all source URLs return HTTP 2xx/3xx
set -euo pipefail

urls=(
  "https://ollama.com/search?c=embedding"
  "https://ollama.com/library/all-minilm"
  "https://ollama.com/library/bge-large"
  "https://ollama.com/library/bge-m3"
  "https://ollama.com/library/embeddinggemma-2"
  "https://ollama.com/library/embeddinggemma"
  "https://ollama.com/library/granite-embedding"
  "https://ollama.com/library/mxbai-embed-large"
  "https://ollama.com/library/nomic-embed-text"
  "https://ollama.com/library/nomic-embed-text-v2-moe"
  "https://ollama.com/library/paraphrase-multilingual"
  "https://ollama.com/library/qwen3-embedding"
  "https://ollama.com/library/snowflake-arctic-embed2"
  "https://ollama.com/library/snowflake-arctic-embed"
)

failed=0
for u in "${urls[@]}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -A "ParTake-research/0.1 (personal project)" "$u")
  echo "[$code] $u"
  if [[ ! "$code" =~ ^[23] ]]; then
    echo "FAIL: $u returned $code"
    failed=1
  fi
  sleep 1.1
done

if [[ "$failed" -eq 1 ]]; then
  echo "Some URLs failed."
  exit 1
fi
echo "All URLs OK (2xx/3xx)."
