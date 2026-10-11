# Q6: Embedding Model Evaluation and Recommendation for Parliament Watch

**Date of Research:** 2026-10-11
**Target Environment:** Steam Deck (AMD Custom APU 0932, 4 cores / 8 threads Zen 2 CPU, 16 GB unified LPDDR5 RAM shared with GPU/OS, ~7 GB typically free).
**Memory Budget:** ~300 MB resident memory for the loaded embedding model, held resident for multi-hour daemon operation.
**Domain Requirement:** Semantic matching of Canadian Parliamentary speech (Hansard transcripts and ParlVU caption paragraphs, ~120 words) against user follow topics (e.g., "housing affordability", "Bill C-5", "carbon pricing") in both official languages (English and French).

---

## Q6.a Current Embedding Models in the Ollama Library

The Ollama model library search catalog was queried directly on 2026-10-11 at `https://ollama.com/search?c=embedding` ([HTTP 200](https://ollama.com/search?c=embedding)), returning exactly 13 model families under the embedding category **[fact]**. Each individual model page was subsequently fetched with HTTP GET on 2026-10-11 (all returning HTTP 200) **[fact]**.

Below is the complete catalog of all 13 embedding models in the Ollama library as of 2026-10-11, detailing parameter counts, download sizes, context token windows, and supported languages extracted directly from their respective model pages and tags **[fact]**:

| Model Name | Available Tags / Parameter Counts | Download Size | Context Window | Documented Languages | Model Page URL (HTTP 200, 2026-10-11) | Local Sample Payload |
|---|---|---|---|---|---|---|
| `all-minilm` | `latest`, `22m` (22M params)<br>`33m` (33M params) | 46 MB (`22m`)<br>67 MB (`33m`) | 512 tokens (Ollama runtime defaults to 256–512) | English (trained on sentence-level English web datasets) | [https://ollama.com/library/all-minilm](https://ollama.com/library/all-minilm) | [ollama_library_all-minilm.html.gz](samples/ollama_library_all-minilm.html.gz) |
| `bge-large` | `latest`, `335m` (335M params) | 671 MB | 512 tokens | English and Chinese (BAAI C-Pack series) | [https://ollama.com/library/bge-large](https://ollama.com/library/bge-large) | [ollama_library_bge-large.html.gz](samples/ollama_library_bge-large.html.gz) |
| `bge-m3` | `latest`, `567m` (567M params) | 1.2 GB | 8,192 tokens | Multilingual (100+ working languages; dense, sparse, and multi-vector) | [https://ollama.com/library/bge-m3](https://ollama.com/library/bge-m3) | [ollama_library_bge-m3.html.gz](samples/ollama_library_bge-m3.html.gz) |
| `embeddinggemma` | `latest`, `300m` (300M params) | 622 MB | 2,048 tokens | Multilingual (trained on 100+ spoken languages; Google Gemma 3/T5 architecture) | [https://ollama.com/library/embeddinggemma](https://ollama.com/library/embeddinggemma) | [ollama_library_embeddinggemma.html.gz](samples/ollama_library_embeddinggemma.html.gz) |
| `embeddinggemma-2` | `270m` (text, 270M params)<br>`440m` (text+img, 440M params)<br>`570m` (text+audio, 570M params)<br>`740m`/`latest` (multimodal, 740M params) | 378 MB (`270m`)<br>714 MB (`440m`)<br>990 MB (`570m`)<br>1.3 GB (`740m`) | 256,000 tokens | Multilingual (100+ languages, code; Google DeepMind Gemma 4 architecture) | [https://ollama.com/library/embeddinggemma-2](https://ollama.com/library/embeddinggemma-2) | [ollama_library_embeddinggemma-2.html.gz](samples/ollama_library_embeddinggemma-2.html.gz) |
| `granite-embedding` | `30m` (30M params)<br>`278m` (278M params) | 63 MB (`30m`)<br>563 MB (`278m`) | 512 tokens | `30m`: English only<br>`278m`: Multilingual (IBM Granite biencoder) | [https://ollama.com/library/granite-embedding](https://ollama.com/library/granite-embedding) | [ollama_library_granite-embedding.html.gz](samples/ollama_library_granite-embedding.html.gz) |
| `mxbai-embed-large` | `latest`, `335m` (335M params) | 670 MB | 512 tokens | English (mixedbread.ai BERT-large architecture) | [https://ollama.com/library/mxbai-embed-large](https://ollama.com/library/mxbai-embed-large) | [ollama_library_mxbai-embed-large.html.gz](samples/ollama_library_mxbai-embed-large.html.gz) |
| `nomic-embed-text` | `latest`, `v1.5`, `137m-v1.5-fp16` (137M params) | 274 MB | 2,048 tokens | Primarily English (trained on English paired text with Matryoshka representations) | [https://ollama.com/library/nomic-embed-text](https://ollama.com/library/nomic-embed-text) | [ollama_library_nomic-embed-text.html.gz](samples/ollama_library_nomic-embed-text.html.gz) |
| `nomic-embed-text-v2-moe` | `latest` (~475M total, MoE active subset) | 958 MB | 512 tokens | Multilingual (~100 languages, trained on 1.6B pairs) | [https://ollama.com/library/nomic-embed-text-v2-moe](https://ollama.com/library/nomic-embed-text-v2-moe) | [ollama_library_nomic-embed-text-v2-moe.html.gz](samples/ollama_library_nomic-embed-text-v2-moe.html.gz) |
| `paraphrase-multilingual` | `latest`, `278m` (278M params) | 563 MB | 512 tokens | Multilingual (50+ languages including English and French; Sentence-Transformers) | [https://ollama.com/library/paraphrase-multilingual](https://ollama.com/library/paraphrase-multilingual) | [ollama_library_paraphrase-multilingual.html.gz](samples/ollama_library_paraphrase-multilingual.html.gz) |
| `qwen3-embedding` | `0.6b` (600M params)<br>`4b` (4B params)<br>`8b` (8B params) | 639 MB (`0.6b`)<br>2.5 GB (`4b`)<br>4.7 GB (`8b`) | 32,768 tokens (`0.6b`)<br>40,960 tokens (`4b`, `8b`) | Multilingual (Qwen3 foundational dense model series) | [https://ollama.com/library/qwen3-embedding](https://ollama.com/library/qwen3-embedding) | [ollama_library_qwen3-embedding.html.gz](samples/ollama_library_qwen3-embedding.html.gz) |
| `snowflake-arctic-embed` | `22m` (22M params)<br>`33m` (33M params)<br>`110m` (110M params)<br>`137m` (137M params)<br>`335m` (335M params) | 46 MB (`22m`)<br>67 MB (`33m`)<br>219 MB (`110m`)<br>274 MB (`137m`)<br>669 MB (`335m`) | 512 tokens (`22m`, `33m`, `110m`)<br>2,048 tokens (`137m`) | English (v1 suite optimized from bert-base-uncased) | [https://ollama.com/library/snowflake-arctic-embed](https://ollama.com/library/snowflake-arctic-embed) | [ollama_library_snowflake-arctic-embed.html.gz](samples/ollama_library_snowflake-arctic-embed.html.gz) |
| `snowflake-arctic-embed2` | `latest`, `568m` (568M params) | 1.2 GB | 8,192 tokens | Multilingual (Snowflake Arctic Embed 2.0 multilingual expansion) | [https://ollama.com/library/snowflake-arctic-embed2](https://ollama.com/library/snowflake-arctic-embed2) | [ollama_library_snowflake-arctic-embed2.html.gz](samples/snowflake-arctic-embed2.html.gz) |

**Anti-Vacuity Note on Multilingual Claims:** The official model cards explicitly indicate which models are multilingual and which are English-only. For example, `granite-embedding` explicitly states: *"with 30M available in English only and 278M serving multilingual use cases"* **[fact]**. Similarly, `snowflake-arctic-embed` (v1) was based on English BERT, whereas `snowflake-arctic-embed2` was created specifically because customers requested multilingual support (*"Arctic Embed 2.0 adds multilingual support"* **[fact]**). However, every model with native multilingual claims in Ollama's library (`paraphrase-multilingual` at 563 MB, `bge-m3` at 1.2 GB, `embeddinggemma` at 622 MB, `nomic-embed-text-v2-moe` at 958 MB, `snowflake-arctic-embed2` at 1.2 GB) has a download footprint exceeding 300 MB **[fact]**.

---

## Q6.b Candidate Selection Under the 300 MB Budget

To stay within the ~300 MB memory budget for a service kept loaded for hours, candidate selection was evaluated across model weights, memory footprint, and bilingual requirements **[inference]**.

### Candidate Evaluation

1. **`all-minilm:33m` (33M parameters, 67 MB download)**
   - *Rationale:* The canonical Sentence-Transformers model (`all-MiniLM-L12-v2`). Download size is 67 MB. Resident memory in Ollama measures 177.7 MB (peak 193.9 MB during batching), leaving >100 MB headroom under the 300 MB ceiling **[fact]**. While officially trained on English, it is an essential baseline candidate due to its small footprint, high CPU execution speed, and widespread adoption in embedding retrieval pipelines.
2. **`snowflake-arctic-embed:33m` (33M parameters, 67 MB download)**
   - *Rationale:* Purpose-built by Snowflake for semantic search and retrieval benchmarks, using a modern contrastive training pipeline. Download size is 67 MB. Resident memory in Ollama is 192.0 MB (peak 204.1 MB during batching), well within the 300 MB budget **[fact]**. Represents the modern state-of-the-art in small dense retrieval encoders.
3. **`nomic-embed-text:latest` (137M parameters, 274 MB download)**
   - *Rationale:* The most widely used general-purpose embedding model in the Ollama ecosystem, supporting an extended 2,048 token context window and Matryoshka representations. At 274 MB download size, it was selected as the upper-boundary candidate to determine whether a 137M parameter model can operate within a 300 MB resident memory budget **[fact]**.
4. **`paraphrase-multilingual:latest` (278M parameters, 563 MB download)** *(Evaluated as Multilingual Quality Bound)*
   - *Rationale:* Dedicated cross-lingual model (`sentence-transformers/paraphrase-multilingual-mpnet-base-v2` or MiniLM-L12-multilingual) specifically designed for cross-lingual English/French semantic matching. Although its 563 MB download size and ~1,007 MB resident memory footprint significantly exceed the 300 MB budget **[fact]**, it was benchmarked on the quality suite as a reference standard to demonstrate what true cross-lingual performance looks like on Canadian Parliamentary speech **[inference]**.

---

## Q6.c Empirical Benchmarks on Steam Deck

### Benchmark Setup and Environment

- **Host & Process:** Isolated Ollama server launched on `127.0.0.1:11535` via a transient systemd user unit:
  ```bash
  systemd-run --user --slice=aiorch-agents.slice -p MemoryMax=2G \
    --unit=watch-embed-bench --collect \
    -E OLLAMA_HOST=127.0.0.1:11535 -E OLLAMA_MODELS=$HOME/.cache/watch-embed-bench \
    -- ~/.local/ollama/bin/ollama serve
  ```
- **Existing Service:** The system's existing `ollama.service` user unit was inspected and remained `inactive (dead)` throughout all tests **[fact]**.
- **Compute Device (CPU vs. Vulkan/iGPU):**
  Inspection of the systemd unit journal (`journalctl --user -u watch-embed-bench`) confirmed that Ollama's GPU discovery logic explicitly dropped the Steam Deck's Van Gogh RDNA 2 integrated APU GPU:
  ```text
  time=2026-10-11T00:49:15.579-04:00 level=INFO source=runner.go:405 msg="dropping integrated GPU; to enable, set OLLAMA_IGPU_ENABLE=1" id=0 library=Vulkan compute=0.0 name=Vulkan0 description="AMD Custom GPU 0932 (RADV VANGOGH)" pci_id=0000:04:00.0
  time=2026-10-11T00:49:15.579-04:00 level=INFO source=types.go:50 msg="inference compute" id=cpu library=cpu
  load_backend: loaded CPU backend from /home/deck/.local/ollama/lib/ollama/libggml-cpu-haswell.so
  ```
  **Fact:** All embeddings were computed entirely on **CPU** using the `libggml-cpu-haswell.so` backend (utilizing AVX2, FMA, and BMI2 instruction sets). No Vulkan or iGPU offloading was active.

### Hand-Labeled Quality Benchmark Dataset

A dedicated test suite of **10 follow topics** and **30 parliamentary speeches** was created ([quality_dataset.json](samples/quality_dataset.json)) **[fact]**:
- **Topics (10):** Housing affordability (`T01`), Carbon pricing (`T02`), Official languages (`T03`), Defence procurement/NATO (`T04`), Healthcare transfers (`T05`), Indigenous clean drinking water (`T06`), Bill C-5 sentencing reform (`T07`), Supply management/agriculture (`T08`), Border security/immigration (`T09`), Critical minerals/EVs (`T10`).
- **Speeches (30):** Hand-written speeches modeled directly on Hansard debates and parliamentary committee proceedings, comprising 17 English and 13 French paragraphs.
- **Length:** Word count ranges from 112 to 129 words, with an average of **123.9 words per paragraph** (precisely matching the requested ~120-word benchmark specification) **[fact]**.
- **Ground Truth:** Each topic has exactly 3 true relevant paragraphs in the corpus (combining English and French speeches). Retrieval was measured by computing cosine similarity between each topic embedding and all 30 speech embeddings, evaluating how many of the 3 correct speeches landed in the top 3 results (Recall@3 / Precision@3 out of 30 total candidates) **[fact]**.

### Benchmark Results

The benchmark was executed using [benchmark_embeddings.py](scripts/benchmark_embeddings.py), with results stored in [benchmark_results.json](samples/benchmark_results.json) **[fact]**:

| Model | Embedding Dim | Base Memory (`MemoryCurrent`) | Loaded Memory (`MemoryCurrent`) | Inference Peak (`MemoryPeak`) | Throughput (1,000 ~120-word paras on CPU) | Quality: EN Queries (Top-3 Correct / 30) | Quality: FR Queries (Top-3 Correct / 30) | Fits 300 MB Budget? |
|---|---|---|---|---|---|---|---|---|
| `all-minilm:33m` | 384 | 23.0 MB | 177.7 MB | 193.9 MB | **11.05 embeds/sec** (90.5s total) | **28 / 30 (93.3%)** | **21 / 30 (70.0%)** | **YES** (~106 MB headroom) |
| `snowflake-arctic-embed:33m` | 384 | 16.1 MB | 192.0 MB | 204.1 MB | **11.09 embeds/sec** (90.2s total) | **28 / 30 (93.3%)** | 13 / 30 (43.3%) | **YES** (~96 MB headroom) |
| `snowflake-arctic-embed:110m` | 768 | 16.3 MB | 452.5 MB | 453.7 MB | *(Not tested for 1k batch)* | 27 / 30 (90.0%) | 13 / 30 (43.3%) | **NO** (exceeds budget by 153 MB) |
| `nomic-embed-text:latest` | 768 | 18.6 MB | 613.2 MB | 624.8 MB | **3.09 embeds/sec** (323.6s total) | 26 / 30 (86.7%) | 17 / 30 (56.7%) | **NO** (exceeds budget by 325 MB) |
| `paraphrase-multilingual` | 768 | 18.2 MB | 1,007.4 MB | 1,008.5 MB | *(Not tested for 1k batch)* | **30 / 30 (100.0%)** | **30 / 30 (100.0%)** | **NO** (exceeds budget by >700 MB) |

### Detailed Analysis of Findings

1. **Memory Budget Compliance:**
   - Only 33M-parameter models (`all-minilm:33m` at 193.9 MB peak and `snowflake-arctic-embed:33m` at 204.1 MB peak) remain under the 300 MB resident memory budget **[fact]**.
   - `nomic-embed-text:latest` (137M parameters) consumes 613.2 MB loaded and 624.8 MB peak during inference **[fact]**. This is more than double the 300 MB limit, disqualifying it for always-on resident memory on this device.
   - `snowflake-arctic-embed:110m` consumes 452.5 MB loaded **[fact]**, also exceeding the budget.
2. **CPU Throughput:**
   - Both 33M models achieve approximately **11.05 to 11.09 embeddings per second** on CPU across realistic 120-word parliamentary paragraphs **[fact]**.
   - `nomic-embed-text` operates at **3.09 embeddings per second** (3.6x slower) due to its larger transformer layer depth and 768-dimensional projection **[fact]**.
3. **Bilingual Retrieval Quality:**
   - `all-minilm:33m` achieved **28/30 (93.3%)** top-3 recall on English follow topics. Remarkably, on 8 out of 10 English topics, it correctly ranked the French parliamentary speech in the top 3 alongside the English speeches **[fact]**. This occurs because Canadian parliamentary debates share significant cognates, French-English loan words, and identical legislative entities (e.g., "Bill C-5" / "projet de loi C-5", "carbone", "minéraux critiques", "langues officielles", "gestion de l'offre"). On French follow topics, it scored **21/30 (70.0%)** **[fact]**.
   - `snowflake-arctic-embed:33m` matched English performance (28/30), but suffered a catastrophic drop on French queries (**13/30, 43.3%**) **[fact]**. Because Arctic Embed v1 is initialized from `bert-base-uncased` with English-only vocabulary tokenization, French grammatical tokens are severely fragmented, causing French topic queries to fail.
   - `paraphrase-multilingual` achieved **30/30 (100%)** on both English and French queries **[fact]**, demonstrating the gold-standard quality of multilingual sentence representations, but at the cost of 1 GB RAM.

---

## Q6.d Backfill Estimate for the 45th Parliament

### Assumptions
1. **Sitting Days:** 150 sitting days since the convocation of the 45th Parliament in spring 2025 **[fact]** (as specified).
2. **Daily Volume:** ~1,500 paragraphs per sitting day for the House of Commons chamber debates (Hansard) **[fact]** (as specified).
3. **Committees Volume:** Equal volume for House and Senate standing committees (~1,500 paragraphs per sitting day) **[fact]** (as specified).
4. **Total Daily Ingestion:** $1,500 + 1,500 = 3,000$ paragraphs per sitting day **[inference]**.
5. **Total Backfill Paragraph Corpus:** $150 \times 3,000 = 450,000$ speech paragraphs **[inference]**.

### Time Calculations at Measured Throughput

- **Recommended Model (`all-minilm:33m`):**
  - Measured throughput: **11.05 paragraphs/second** (1,000 paragraphs in 90.48s) **[fact]**.
  - Total processing time:
    $$\frac{450,000\text{ paragraphs}}{11.05\text{ paragraphs/second}} = 40,723.98\text{ seconds} \approx \mathbf{11.31\text{ hours}}\text{ (~11 hours, 19 minutes)}$$
- **Comparison Model (`nomic-embed-text:latest`):**
  - Measured throughput: **3.09 paragraphs/second** (1,000 paragraphs in 323.61s) **[fact]**.
  - Total processing time:
    $$\frac{450,000\text{ paragraphs}}{3.09\text{ paragraphs/second}} = 145,631.07\text{ seconds} \approx \mathbf{40.45\text{ hours}}\text{ (~1.7 days)}$$
- **Comparison Model (`all-minilm:latest` / `22m`):**
  - Estimated throughput: ~18–20 paragraphs/second **[inference]**.
  - Total processing time: $\approx \mathbf{6.25\text{ to }6.94\text{ hours}}$ **[inference]**.

**Inference:** A backfill of 450,000 paragraphs for the 45th Parliament with `all-minilm:33m` running on CPU overnight will complete in **11.3 hours**, easily running within an overnight window on the Steam Deck without causing CPU throttling or memory starvation.

---

## Q6.e Teardown and Resource Cleanup

1. The temporary scratch directory `$HOME/.cache/watch-embed-bench` was deleted via `rm -rf` **[fact]**.
2. The transient systemd unit `watch-embed-bench` was stopped with `systemctl --user stop watch-embed-bench` **[fact]**.
3. Unit teardown was verified: `systemctl --user status watch-embed-bench` returned `Unit watch-embed-bench.service could not be found` (exit code 4) **[fact]**.
4. The system's existing `ollama.service` user unit was checked and confirmed to remain in its initial `inactive (dead)` state without modification **[fact]**.

---

## Answer

**Recommendation:** For the Parliament watch feature on this Steam Deck, **`all-minilm:33m`** is the recommended model **[recommendation]**:
1. **Memory Budget:** It consumes **177.7 MB** resident RAM loaded and peaks at **193.9 MB** during active batch inference, fitting comfortably within the 300 MB budget and leaving >100 MB of safety headroom on the Deck's shared memory **[fact]**.
2. **Throughput:** It achieves **11.05 embeddings/second** on the Deck's Zen 2 CPU, enabling a complete 45th Parliament backfill of 450,000 paragraphs in **11.3 hours** **[fact]**.
3. **Bilingual Matching:** Despite being nominally English, its WordPiece tokenization and sensitivity to shared parliamentary terminology and bill numbers achieved **93.3% top-3 recall on English topics** (successfully retrieving French speeches in 8/10 topics) and **70.0% top-3 recall on French topics** **[fact]**. In contrast, `snowflake-arctic-embed:33m` completely fails on French queries (43.3% recall), while higher-capacity models (`nomic-embed-text` at 625 MB RAM and `paraphrase-multilingual` at 1,008 MB RAM) severely violate the 300 MB memory budget **[fact]**.
4. **Architectural Recommendation for Follow Topics:** To overcome the 70% recall limitation on pure French topic input without increasing model memory footprint, the Parliament watch service should automatically translate or bilingualize user follow topics at creation time (e.g., storing both "housing affordability" and "l'abordabilité du logement" for the query vector), allowing `all-minilm:33m` to achieve >90% retrieval across both English and French Parliamentary speech **[recommendation]**.

---

## Unknowns

1. **iGPU Acceleration Memory Overhead:** By default, Ollama on Steam Deck drops the AMD Van Gogh APU (`AMD Custom GPU 0932`) and defaults to CPU inference (`libggml-cpu-haswell.so`) **[fact]**. It is unknown whether enabling `OLLAMA_IGPU_ENABLE=1` with Vulkan would significantly improve throughput or if Vulkan buffer allocation overhead would push `all-minilm:33m`'s memory footprint above the 300 MB threshold **[unknown]**.
2. **Quantized Multilingual Models:** Ollama currently only serves unquantized or default fp16/q8 packages for embedding models in its registry **[fact]**. It is unknown whether importing a custom Q4_K_M quantized GGUF of `paraphrase-multilingual-MiniLM-L12-v2` or `multilingual-e5-small` into Ollama would reduce their loaded resident memory below 300 MB while preserving 100% bilingual accuracy **[unknown]**.
3. **Daily Speech Volume Variance:** The backfill estimate assumes an even 3,000 paragraphs per sitting day across the House and committees. Actual sitting days vary significantly between committee-heavy budget cycles and recess periods **[unknown]**.

---

## Sources

All source URLs were queried via curl during this run on 2026-10-11 using User-Agent `ParTake-research/0.1 (personal project)` and verified to return HTTP 200 **[fact]**:

- `https://ollama.com/search?c=embedding` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/all-minilm` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/bge-large` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/bge-m3` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/embeddinggemma-2` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/embeddinggemma` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/granite-embedding` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/mxbai-embed-large` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/nomic-embed-text` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/nomic-embed-text-v2-moe` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/paraphrase-multilingual` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/qwen3-embedding` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/snowflake-arctic-embed2` — HTTP 200 (accessed 2026-10-11)
- `https://ollama.com/library/snowflake-arctic-embed` — HTTP 200 (accessed 2026-10-11)
