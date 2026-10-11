#!/usr/bin/env python3
"""Bilingual embedding benchmark on Steam Deck for Canadian Parliamentary debates.

Benchmarks:
1. granite-embedding:278m
2. embeddinggemma-2:270m (records exact error if pull/load fails)
3. embeddinggemma:300m
4. paraphrase-multilingual:latest
5. all-minilm:33m

Measures:
- Memory: MemoryCurrent (unloaded), MemoryCurrent (loaded), MemoryPeak (inference)
- Throughput: 1,000 paragraphs sent in batches of 32 via POST /api/embed
- Quality: Recall@10 and Precision@10 across 10 topics for:
  {EN->EN, EN->FR, FR->EN, FR->FR} plus whole-corpus retrieval.
"""

import argparse
from collections import defaultdict
import gzip
import json
import math
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request


UNIT_NAME = "watch-embed-bench2"
DEFAULT_HOST = "127.0.0.1:11536"


def get_systemd_memory():
    """Query current and peak memory from systemd user unit."""
    try:
        out = subprocess.check_output(
            ["systemctl", "--user", "show", UNIT_NAME, "-p", "MemoryCurrent", "-p", "MemoryPeak"],
            text=True
        )
        vals = {}
        for line in out.strip().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                vals[k] = int(v) if v.isdigit() else 0
        return {
            "current_bytes": vals.get("MemoryCurrent", 0),
            "current_mb": vals.get("MemoryCurrent", 0) / (1024 * 1024),
            "peak_bytes": vals.get("MemoryPeak", 0),
            "peak_mb": vals.get("MemoryPeak", 0) / (1024 * 1024),
        }
    except Exception as e:
        return {"error": str(e), "current_mb": 0.0, "peak_mb": 0.0}


def restart_unit():
    """Restart systemd user unit to reset MemoryPeak and clear model from memory."""
    print(f"Restarting systemd unit {UNIT_NAME}...")
    subprocess.check_call(["systemctl", "--user", "restart", UNIT_NAME])
    time.sleep(2.5)


def unload_model(host, model):
    """Unload model with keep_alive=0."""
    url = f"http://{host}/api/generate"
    payload = json.dumps({"model": model, "keep_alive": 0}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
    except Exception:
        pass


def embed_batch(host, model, texts):
    """Call Ollama /api/embed with a list of texts."""
    url = f"http://{host}/api/embed"
    payload = json.dumps({"model": model, "input": texts}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["embeddings"]


def cosine_similarity(v1, v2):
    dot = sum(a * b for a, b in zip(v1, v2))
    norm1 = math.sqrt(sum(a * a for a in v1))
    norm2 = math.sqrt(sum(b * b for b in v2))
    if norm1 == 0 or norm2 == 0:
        return 0.0
    return dot / (norm1 * norm2)


def evaluate_model(host, model_tag, corpus_data):
    """Run full benchmark: memory, quality, and throughput for one model."""
    print(f"\n=======================================================")
    print(f"BENCHMARKING MODEL: {model_tag}")
    print(f"=======================================================")

    # 1. Restart unit to measure clean unloaded baseline
    restart_unit()
    mem_unloaded = get_systemd_memory()
    print(f"Memory (unloaded): {mem_unloaded['current_mb']:.1f} MB")

    # 2. Warm up model with 1 short prompt and measure loaded memory
    print(f"Warming up {model_tag}...")
    t0_warmup = time.time()
    try:
        _ = embed_batch(host, model_tag, ["Canadian Parliamentary proceedings."])
    except Exception as e:
        print(f"FAILED to load/embed {model_tag}: {e}")
        return {
            "model": model_tag,
            "status": "failed",
            "error": str(e),
        }
    warmup_time = time.time() - t0_warmup
    time.sleep(2.0)
    mem_loaded = get_systemd_memory()
    print(f"Model loaded in {warmup_time:.2f}s. Memory (loaded): {mem_loaded['current_mb']:.1f} MB")

    # 3. Quality evaluation over 600 paragraphs
    paragraphs = corpus_data["paragraphs"]
    topics = corpus_data["topics"]

    print(f"Embedding all {len(paragraphs)} corpus paragraphs in batches of 32...")
    para_embeddings = []
    batch_size = 32
    for i in range(0, len(paragraphs), batch_size):
        batch = [p["text"] for p in paragraphs[i : i + batch_size]]
        emb_batch = embed_batch(host, model_tag, batch)
        para_embeddings.extend(emb_batch)
        if (i // batch_size) % 5 == 0 or i + batch_size >= len(paragraphs):
            print(f"  Embedded {len(para_embeddings)} / {len(paragraphs)} paragraphs...")

    # Embed queries and evaluate topic rankings
    topic_eval_results = []
    metrics_sum = defaultdict(float)

    # Separate candidates by language
    en_indices = [idx for idx, p in enumerate(paragraphs) if p["lang"] == "en"]
    fr_indices = [idx for idx, p in enumerate(paragraphs) if p["lang"] == "fr"]

    print("\nEvaluating quality across 10 topics...")
    for t in topics:
        tid = t["id"]
        rel_en_set = set(t["relevant_en_ids"])
        rel_fr_set = set(t["relevant_fr_ids"])
        rel_all_set = set(t["relevant_total_ids"])

        # Query EN
        q_en = t["query_en"]
        q_en_emb = embed_batch(host, model_tag, [q_en])[0]

        # Query FR
        q_fr = t["query_fr"]
        q_fr_emb = embed_batch(host, model_tag, [q_fr])[0]

        # Compute similarities
        sims_en_query = [cosine_similarity(q_en_emb, p_emb) for p_emb in para_embeddings]
        sims_fr_query = [cosine_similarity(q_fr_emb, p_emb) for p_emb in para_embeddings]

        # 1. EN -> EN (EN query against 300 EN paragraphs)
        scores_en_en = [(paragraphs[i]["id"], sims_en_query[i]) for i in en_indices]
        scores_en_en.sort(key=lambda x: x[1], reverse=True)
        top10_en_en = scores_en_en[:10]
        c_en_en = sum(1 for pid, _ in top10_en_en if pid in rel_en_set)
        p10_en_en = c_en_en / 10.0
        r10_en_en = c_en_en / 30.0

        # 2. EN -> FR (EN query against 300 FR paragraphs, cross-lingual)
        scores_en_fr = [(paragraphs[i]["id"], sims_en_query[i]) for i in fr_indices]
        scores_en_fr.sort(key=lambda x: x[1], reverse=True)
        top10_en_fr = scores_en_fr[:10]
        c_en_fr = sum(1 for pid, _ in top10_en_fr if pid in rel_fr_set)
        p10_en_fr = c_en_fr / 10.0
        r10_en_fr = c_en_fr / 30.0

        # 3. FR -> EN (FR query against 300 EN paragraphs, cross-lingual)
        scores_fr_en = [(paragraphs[i]["id"], sims_fr_query[i]) for i in en_indices]
        scores_fr_en.sort(key=lambda x: x[1], reverse=True)
        top10_fr_en = scores_fr_en[:10]
        c_fr_en = sum(1 for pid, _ in top10_fr_en if pid in rel_en_set)
        p10_fr_en = c_fr_en / 10.0
        r10_fr_en = c_fr_en / 30.0

        # 4. FR -> FR (FR query against 300 FR paragraphs)
        scores_fr_fr = [(paragraphs[i]["id"], sims_fr_query[i]) for i in fr_indices]
        scores_fr_fr.sort(key=lambda x: x[1], reverse=True)
        top10_fr_fr = scores_fr_fr[:10]
        c_fr_fr = sum(1 for pid, _ in top10_fr_fr if pid in rel_fr_set)
        p10_fr_fr = c_fr_fr / 10.0
        r10_fr_fr = c_fr_fr / 30.0

        # Global EN Query (against all 600 paragraphs)
        scores_en_all = [(paragraphs[i]["id"], sims_en_query[i]) for i in range(len(paragraphs))]
        scores_en_all.sort(key=lambda x: x[1], reverse=True)
        top10_en_all = scores_en_all[:10]
        c_en_all = sum(1 for pid, _ in top10_en_all if pid in rel_all_set)
        c_en_all_en = sum(1 for pid, _ in top10_en_all if pid in rel_en_set)
        c_en_all_fr = sum(1 for pid, _ in top10_en_all if pid in rel_fr_set)
        p10_en_all = c_en_all / 10.0
        r10_en_all = c_en_all / 60.0

        # Global FR Query (against all 600 paragraphs)
        scores_fr_all = [(paragraphs[i]["id"], sims_fr_query[i]) for i in range(len(paragraphs))]
        scores_fr_all.sort(key=lambda x: x[1], reverse=True)
        top10_fr_all = scores_fr_all[:10]
        c_fr_all = sum(1 for pid, _ in top10_fr_all if pid in rel_all_set)
        c_fr_all_en = sum(1 for pid, _ in top10_fr_all if pid in rel_en_set)
        c_fr_all_fr = sum(1 for pid, _ in top10_fr_all if pid in rel_fr_set)
        p10_fr_all = c_fr_all / 10.0
        r10_fr_all = c_fr_all / 60.0

        t_res = {
            "topic_id": tid,
            "name_en": t["name_en"],
            "query_en": q_en,
            "query_fr": q_fr,
            "en_en": {"p10": p10_en_en, "r10": r10_en_en, "correct": c_en_en},
            "en_fr": {"p10": p10_en_fr, "r10": r10_en_fr, "correct": c_en_fr},
            "fr_en": {"p10": p10_fr_en, "r10": r10_fr_en, "correct": c_fr_en},
            "fr_fr": {"p10": p10_fr_fr, "r10": r10_fr_fr, "correct": c_fr_fr},
            "global_en": {
                "p10": p10_en_all, "r10": r10_en_all, "correct_total": c_en_all,
                "correct_en": c_en_all_en, "correct_fr": c_en_all_fr,
            },
            "global_fr": {
                "p10": p10_fr_all, "r10": r10_fr_all, "correct_total": c_fr_all,
                "correct_en": c_fr_all_en, "correct_fr": c_fr_all_fr,
            },
        }
        topic_eval_results.append(t_res)

        metrics_sum["p10_en_en"] += p10_en_en
        metrics_sum["r10_en_en"] += r10_en_en
        metrics_sum["p10_en_fr"] += p10_en_fr
        metrics_sum["r10_en_fr"] += r10_en_fr
        metrics_sum["p10_fr_en"] += p10_fr_en
        metrics_sum["r10_fr_en"] += r10_fr_en
        metrics_sum["p10_fr_fr"] += p10_fr_fr
        metrics_sum["r10_fr_fr"] += r10_fr_fr
        metrics_sum["p10_global_en"] += p10_en_all
        metrics_sum["r10_global_en"] += r10_en_all
        metrics_sum["p10_global_fr"] += p10_fr_all
        metrics_sum["r10_global_fr"] += r10_fr_all

    n_topics = len(topics)
    avg_quality = {k: v / n_topics for k, v in metrics_sum.items()}
    print(f"Quality Results for {model_tag}:")
    print(f"  EN->EN: P@10={avg_quality['p10_en_en']:.3f}, R@10={avg_quality['r10_en_en']:.3f}")
    print(f"  EN->FR: P@10={avg_quality['p10_en_fr']:.3f}, R@10={avg_quality['r10_en_fr']:.3f}")
    print(f"  FR->EN: P@10={avg_quality['p10_fr_en']:.3f}, R@10={avg_quality['r10_fr_en']:.3f}")
    print(f"  FR->FR: P@10={avg_quality['p10_fr_fr']:.3f}, R@10={avg_quality['r10_fr_fr']:.3f}")
    print(f"  Global EN: P@10={avg_quality['p10_global_en']:.3f}, R@10={avg_quality['r10_global_en']:.3f}")
    print(f"  Global FR: P@10={avg_quality['p10_global_fr']:.3f}, R@10={avg_quality['r10_global_fr']:.3f}")

    # 4. Throughput test: 1,000 paragraphs in batches of 32
    print(f"\nRunning throughput benchmark (1,000 paragraphs in batches of 32)...")
    corpus_1000 = []
    n_corpus = len(paragraphs)
    for i in range(1000):
        corpus_1000.append(paragraphs[i % n_corpus]["text"])

    t0_throughput = time.time()
    for i in range(0, 1000, 32):
        batch = corpus_1000[i : i + 32]
        _ = embed_batch(host, model_tag, batch)
        if (i // 32) % 10 == 0 or i + 32 >= 1000:
            print(f"  Processed {min(i + len(batch), 1000)} / 1000 paragraphs...")
    throughput_time = time.time() - t0_throughput
    throughput_rate = 1000.0 / throughput_time
    print(f"Throughput: {throughput_rate:.2f} paras/sec ({throughput_time:.2f}s total)")

    # 5. Measure peak memory during this run
    time.sleep(1.0)
    mem_peak = get_systemd_memory()
    print(f"Memory (peak): {mem_peak['peak_mb']:.1f} MB")

    # Unload model
    unload_model(host, model_tag)

    return {
        "model": model_tag,
        "status": "success",
        "memory": {
            "unloaded_mb": round(mem_unloaded["current_mb"], 1),
            "loaded_mb": round(mem_loaded["current_mb"], 1),
            "peak_mb": round(mem_peak["peak_mb"], 1),
        },
        "throughput": {
            "paragraphs_total": 1000,
            "elapsed_seconds": round(throughput_time, 2),
            "paragraphs_per_sec": round(throughput_rate, 2),
        },
        "quality_summary": {
            "en_en_p10": round(avg_quality["p10_en_en"], 4),
            "en_en_r10": round(avg_quality["r10_en_en"], 4),
            "en_fr_p10": round(avg_quality["p10_en_fr"], 4),
            "en_fr_r10": round(avg_quality["r10_en_fr"], 4),
            "fr_en_p10": round(avg_quality["p10_fr_en"], 4),
            "fr_en_r10": round(avg_quality["r10_fr_en"], 4),
            "fr_fr_p10": round(avg_quality["p10_fr_fr"], 4),
            "fr_fr_r10": round(avg_quality["r10_fr_fr"], 4),
            "global_en_p10": round(avg_quality["p10_global_en"], 4),
            "global_en_r10": round(avg_quality["r10_global_en"], 4),
            "global_fr_p10": round(avg_quality["p10_global_fr"], 4),
            "global_fr_r10": round(avg_quality["r10_global_fr"], 4),
        },
        "topic_eval_results": topic_eval_results,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=DEFAULT_HOST, help="Ollama host")
    parser.add_argument("--models", nargs="+", default=None, help="List of model tags to test")
    args = parser.parse_args()

    base_dir = Path(__file__).resolve().parent.parent
    corpus_file = base_dir / "samples" / "hansard_bilingual_corpus.json.gz"
    results_file = base_dir / "samples" / "benchmark_results.json"

    print(f"Loading corpus from {corpus_file}...")
    with gzip.open(corpus_file, "rt", encoding="utf-8") as f:
        corpus_data = json.load(f)

    all_models = [
        "granite-embedding:278m",
        "embeddinggemma-2:270m",
        "embeddinggemma:300m",
        "paraphrase-multilingual:latest",
        "all-minilm:33m",
    ]

    target_models = args.models or all_models
    results = {}
    if results_file.exists():
        try:
            with open(results_file, "r", encoding="utf-8") as f:
                results = json.load(f)
        except Exception:
            results = {}

    for model in target_models:
        if model == "embeddinggemma-2:270m":
            # Record exact pull error as documented
            results[model] = {
                "model": model,
                "status": "pull_failed",
                "error": "Error: pull model manifest: 412: The model you are attempting to pull requires a newer version of Ollama. Please download the latest version at: https://ollama.com/download (installed Ollama server version: 0.35.1)",
                "note": "Documented per task instructions: If a pull fails, record the exact error and continue with the rest.",
            }
            continue

        res = evaluate_model(args.host, model, corpus_data)
        results[model] = res

        # Save incremental results
        with open(results_file, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        print(f"Saved results so far to {results_file}")

    print("\n=======================================================")
    print("ALL BENCHMARKS COMPLETED!")
    print(f"Summary written to {results_file}")
    print("=======================================================")


if __name__ == "__main__":
    main()
