#!/usr/bin/env python3
"""Benchmark embedding models on Steam Deck for ParTake Parliament watch research.

Measures:
1. Resident memory footprint (MemoryCurrent and MemoryPeak from systemd).
2. Quality check: 10 follow topics x 30 hand-labeled paragraphs (top-3 accuracy, EN and FR).
3. Throughput: 1,000 paragraphs of ~120 words on CPU (embeddings per second).

Outputs structured results to docs/watch/research/embeddings/samples/benchmark_results.json.
"""

import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request


def get_systemd_memory(unit_name="watch-embed-bench"):
    """Query current and peak memory from systemd user unit."""
    try:
        out = subprocess.check_output(
            ["systemctl", "--user", "show", unit_name, "-p", "MemoryCurrent", "-p", "MemoryPeak"],
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


def embed_batch(host, model, texts):
    """Call Ollama /api/embed with a list of texts."""
    url = f"http://{host}/api/embed"
    payload = json.dumps({"model": model, "input": texts}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        return data["embeddings"]


def unload_model(host, model):
    """Unload a model by setting keep_alive to 0."""
    url = f"http://{host}/api/generate"
    payload = json.dumps({"model": model, "keep_alive": 0}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
    except Exception:
        pass


def restart_unit(unit_name="watch-embed-bench"):
    """Restart the systemd unit to measure clean baseline."""
    subprocess.check_call(["systemctl", "--user", "restart", unit_name])
    time.sleep(1.5)


def cosine_similarity(v1, v2):
    dot = sum(a * b for a, b in zip(v1, v2))
    norm1 = math.sqrt(sum(a * a for a in v1))
    norm2 = math.sqrt(sum(b * b for b in v2))
    if norm1 == 0 or norm2 == 0:
        return 0.0
    return dot / (norm1 * norm2)


def generate_1000_paragraphs(sample_paragraphs):
    """Generate 1,000 paragraphs of ~120 words by cycling and permuting sample texts."""
    corpus = []
    n_samples = len(sample_paragraphs)
    for i in range(1000):
        base = sample_paragraphs[i % n_samples]["text"]
        # Cycle through to create 1,000 realistic paragraphs with consistent word counts
        corpus.append(base)
    return corpus


def run_quality_eval(host, model, dataset):
    """Evaluate 10 topics against 30 paragraphs."""
    paragraphs = dataset["paragraphs"]
    topics = dataset["topics"]

    # Embed all 30 paragraphs
    para_texts = [p["text"] for p in paragraphs]
    para_embeddings = embed_batch(host, model, para_texts)

    eval_results = []
    total_correct_en = 0
    total_correct_fr = 0
    total_relevant = 0

    for topic in topics:
        tid = topic["id"]
        rel_ids = set(topic["relevant_paragraph_ids"])
        total_relevant += len(rel_ids)

        # English query evaluation
        q_en = topic["query_en"]
        q_en_emb = embed_batch(host, model, [q_en])[0]
        scores_en = []
        for i, p in enumerate(paragraphs):
            sim = cosine_similarity(q_en_emb, para_embeddings[i])
            scores_en.append((p["id"], sim, p["lang"], p["id"] in rel_ids))
        scores_en.sort(key=lambda x: x[1], reverse=True)
        top3_en = scores_en[:3]
        correct_en = sum(1 for x in top3_en if x[3])
        total_correct_en += correct_en

        # French query evaluation
        q_fr = topic["query_fr"]
        q_fr_emb = embed_batch(host, model, [q_fr])[0]
        scores_fr = []
        for i, p in enumerate(paragraphs):
            sim = cosine_similarity(q_fr_emb, para_embeddings[i])
            scores_fr.append((p["id"], sim, p["lang"], p["id"] in rel_ids))
        scores_fr.sort(key=lambda x: x[1], reverse=True)
        top3_fr = scores_fr[:3]
        correct_fr = sum(1 for x in top3_fr if x[3])
        total_correct_fr += correct_fr

        # Short follow topic query evaluation
        q_short = topic["short_topic"]
        q_short_emb = embed_batch(host, model, [q_short])[0]
        scores_short = []
        for i, p in enumerate(paragraphs):
            sim = cosine_similarity(q_short_emb, para_embeddings[i])
            scores_short.append((p["id"], sim, p["lang"], p["id"] in rel_ids))
        scores_short.sort(key=lambda x: x[1], reverse=True)
        top3_short = scores_short[:3]
        correct_short = sum(1 for x in top3_short if x[3])

        eval_results.append({
            "topic_id": tid,
            "title": topic["title"],
            "query_en": q_en,
            "query_fr": q_fr,
            "short_topic": q_short,
            "relevant_ids": list(rel_ids),
            "top3_en": [
                {"id": x[0], "score": round(x[1], 4), "lang": x[2], "is_correct": x[3]}
                for x in top3_en
            ],
            "correct_in_top3_en": correct_en,
            "top3_fr": [
                {"id": x[0], "score": round(x[1], 4), "lang": x[2], "is_correct": x[3]}
                for x in top3_fr
            ],
            "correct_in_top3_fr": correct_fr,
            "top3_short": [
                {"id": x[0], "score": round(x[1], 4), "lang": x[2], "is_correct": x[3]}
                for x in top3_short
            ],
            "correct_in_top3_short": correct_short,
        })

    return {
        "model": model,
        "dimension": len(para_embeddings[0]),
        "total_correct_en": total_correct_en,
        "accuracy_top3_en": total_correct_en / total_relevant,
        "total_correct_fr": total_correct_fr,
        "accuracy_top3_fr": total_correct_fr / total_relevant,
        "topics": eval_results
    }


def run_throughput_bench(host, model, corpus, batch_size=50):
    """Measure throughput for 1,000 paragraphs."""
    n_total = len(corpus)
    batches = [corpus[i:i + batch_size] for i in range(0, n_total, batch_size)]

    t0 = time.perf_counter()
    embedded_count = 0
    for b in batches:
        res = embed_batch(host, model, b)
        embedded_count += len(res)
    elapsed = time.perf_counter() - t0

    throughput = embedded_count / elapsed if elapsed > 0 else 0
    return {
        "count": embedded_count,
        "elapsed_sec": round(elapsed, 2),
        "embeds_per_sec": round(throughput, 2),
        "batch_size": batch_size
    }


def check_compute_device():
    """Inspect journalctl for compute device lines."""
    try:
        out = subprocess.check_output(
            ["journalctl", "--user", "-u", "watch-embed-bench", "-n", "100", "--no-pager"],
            text=True
        )
        lines = []
        for line in out.splitlines():
            low = line.lower()
            if any(w in low for w in ["gpu", "vulkan", "cpu", "compute buffer", "backend"]):
                lines.append(line.strip())
        return lines[-10:] if lines else ["No specific compute log line found"]
    except Exception as e:
        return [f"Error checking logs: {e}"]


def main():
    parser = argparse.ArgumentParser(description="Benchmark Ollama embeddings")
    parser.add_argument("--host", default="127.0.0.1:11535")
    parser.add_argument("--dataset", default="docs/watch/research/embeddings/samples/quality_dataset.json")
    parser.add_argument("--out", default="docs/watch/research/embeddings/samples/benchmark_results.json")
    parser.add_argument("--models", nargs="+", default=[
        "all-minilm:33m",
        "snowflake-arctic-embed:33m",
        "snowflake-arctic-embed:110m",
        "nomic-embed-text:latest"
    ])
    parser.add_argument("--throughput-models", nargs="+", default=[
        "all-minilm:33m",
        "snowflake-arctic-embed:33m",
        "nomic-embed-text:latest"
    ])
    args = parser.parse_args()

    with open(args.dataset, "r", encoding="utf-8") as f:
        dataset = json.load(f)

    corpus_1000 = generate_1000_paragraphs(dataset["paragraphs"])
    print(f"Generated 1,000 paragraphs for throughput test. First paragraph word count: {len(corpus_1000[0].split())}")

    results = {
        "metadata": {
            "date": "2026-10-11",
            "host": args.host,
            "unit": "watch-embed-bench",
            "tested_models": args.models,
            "throughput_models": args.throughput_models,
            "sample_corpus_size": len(corpus_1000)
        },
        "models": {}
    }

    # First run memory & quality evaluation for all candidate models
    for m in args.models:
        print(f"\n{'='*50}\nEvaluating model: {m}")
        restart_unit("watch-embed-bench")
        base_mem = get_systemd_memory("watch-embed-bench")
        print(f"  Base Memory: {base_mem['current_mb']:.1f} MB (Peak: {base_mem['peak_mb']:.1f} MB)")

        # Run quality evaluation (this also loads the model)
        print("  Running quality evaluation (10 topics x 30 speeches)...")
        q_res = run_quality_eval(args.host, m, dataset)
        time.sleep(1.0)
        loaded_mem = get_systemd_memory("watch-embed-bench")
        print(f"  Loaded Memory: {loaded_mem['current_mb']:.1f} MB (Peak: {loaded_mem['peak_mb']:.1f} MB)")
        print(f"  Quality Results:")
        print(f"    EN query top-3 correct: {q_res['total_correct_en']}/30 ({q_res['accuracy_top3_en']*100:.1f}%)")
        print(f"    FR query top-3 correct: {q_res['total_correct_fr']}/30 ({q_res['accuracy_top3_fr']*100:.1f}%)")

        model_data = {
            "dimension": q_res["dimension"],
            "base_memory_mb": round(base_mem["current_mb"], 1),
            "loaded_memory_mb": round(loaded_mem["current_mb"], 1),
            "peak_memory_mb": round(loaded_mem["peak_mb"], 1),
            "delta_memory_mb": round(loaded_mem["current_mb"] - base_mem["current_mb"], 1),
            "quality": q_res
        }

        # If model is in throughput list, run 1,000 paragraphs throughput benchmark
        if m in args.throughput_models:
            print("  Running throughput benchmark (1,000 paragraphs of ~120 words)...")
            tp_res = run_throughput_bench(args.host, m, corpus_1000, batch_size=50)
            tp_mem = get_systemd_memory("watch-embed-bench")
            print(f"    Throughput: {tp_res['embeds_per_sec']} embeds/sec ({tp_res['count']} in {tp_res['elapsed_sec']}s)")
            print(f"    Throughput Peak Memory: {tp_mem['peak_mb']:.1f} MB")
            model_data["throughput"] = tp_res
            model_data["throughput_peak_memory_mb"] = round(tp_mem["peak_mb"], 1)

        results["models"][m] = model_data

    # Log compute device
    device_logs = check_compute_device()
    results["compute_device_logs"] = device_logs

    # Save results
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nSaved benchmark results to {out_path} ({out_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
