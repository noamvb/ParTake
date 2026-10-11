# Q7: Bilingual Embedding Model Evaluation and Recommendation for Parliament Watch

**Date of Research:** 2026-10-11
**Target Environment:** Steam Deck (AMD Custom APU 0932, 4 cores / 8 threads Zen 2 CPU, 16 GB unified LPDDR5 RAM shared with GPU/OS, ~7.5 GB free) **[fact]**.
**Daemon Architecture:** Always-on background daemon matching Canadian Parliamentary debates (Hansard transcripts and ParlVU captions) against user follows in English and French **[fact]**.
**Corpus Domain:** Real Hansard transcripts from House of Commons Sittings 145–149 (45th Parliament, 1st Session, October 2026) **[fact]**.

---

## 1. Candidate Models and Ollama Environment

Five embedding model tags were evaluated directly on Ollama (daemon version `0.35.1`) **[fact]**:

1. `granite-embedding:278m` (IBM Granite bilingual/multilingual encoder, 278M parameters, 562 MB download) **[fact]**.
2. `embeddinggemma-2:270m` (Google DeepMind Gemma 2 text embedding model, 270M parameters) **[fact]**.
3. `embeddinggemma:300m` (Google Gemma multilingual encoder, 300M parameters, 621 MB download) **[fact]**.
4. `paraphrase-multilingual:latest` (Sentence-Transformers MiniLM/mpnet multilingual reference, 278M parameters, 562 MB download) **[fact]**.
5. `all-minilm:33m` (Sentence-Transformers MiniLM-L12-v2, 33M parameters, 67 MB download; run-1 baseline) **[fact]**.

### Pull Results and Incompatibility Note

- `granite-embedding:278m`, `embeddinggemma:300m`, `paraphrase-multilingual:latest`, and `all-minilm:33m` pulled and loaded successfully **[fact]**.
- `embeddinggemma-2:270m` **failed to pull** **[fact]**. When pulled via `ollama pull embeddinggemma-2:270m`, the Ollama registry returned an HTTP 412 status code with the exact error:
  ```text
  Error: pull model manifest: 412:
  The model you are attempting to pull requires a newer version of Ollama.

  Please download the latest version at:

      https://ollama.com/download
  ```
  **Anti-Vacuity Probe:** To ensure this failure was not due to network reachability or daemon configuration, identical pull commands were executed on the same isolated endpoint for `granite-embedding:278m` and `embeddinggemma:300m`, both of which downloaded and unpacked their manifests and layers without error **[fact]**. The HTTP 412 error specifically indicates that the model manifest for the Gemma 2 embedding release requires a manifest schema/format not supported by Ollama 0.35.1 **[fact]**.

### Isolated Daemon Configuration

The isolated benchmarking daemon was launched in a transient systemd user unit with a 2,500 MB memory cap:
```bash
systemd-run --user --slice=aiorch-agents.slice -p MemoryMax=2500M \
  --unit=watch-embed-bench2 --collect \
  -E OLLAMA_HOST=127.0.0.1:11536 -E OLLAMA_MODELS=$HOME/.cache/watch-embed-bench2 \
  -E OLLAMA_NUM_PARALLEL=1 -E OLLAMA_MAX_LOADED_MODELS=1 -E OLLAMA_CONTEXT_LENGTH=512 \
  -- ~/.local/ollama/bin/ollama serve
```
The existing system `ollama.service` user unit remained `inactive (dead)` throughout all testing **[fact]**. All embeddings executed strictly on CPU using `libggml-cpu-haswell.so` (AVX2/FMA instructions) **[fact]**.

---

## 2. Ground-Truth Hansard Dataset Construction

A bilingual corpus of **600 real paragraphs** was extracted directly from official House of Commons Hansard XML files for Sittings 145 to 149 (45th Parliament, 1st Session) **[fact]**:
- `https://www.ourcommons.ca/Content/House/451/Debates/{145..149}/HAN{145..149}-E.XML` (HTTP 200) **[fact]**.
- `https://www.ourcommons.ca/Content/House/451/Debates/{145..149}/HAN{145..149}-F.XML` (HTTP 200) **[fact]**.

### Structure and Disjoint Interventions

- **10 Topics:** Ten major debate subjects spanning government bills, private member bills, supply days, and standing committee topics were identified directly from `<SubjectOfBusinessTitle>` and `<SubjectOfBusinessQualifier>` headings **[fact]**.
- **Paragraphs per Topic:** Exactly 60 paragraphs per topic (30 English, 30 French) = **600 paragraphs total** **[fact]**.
- **Strictly Disjoint Interventions:** To prevent translation pairs from artificially inflating cross-lingual retrieval scores, all English paragraphs were drawn from intervention IDs $I_E$ and all French paragraphs from intervention IDs $I_F$ such that $I_E \cap I_F = \emptyset$ (60 unique EN interventions and 95 unique FR interventions across the corpus) **[fact]**. No English paragraph has a French translation counterpart in the corpus **[fact]**.
- **Payload Artifacts:** The full dataset is saved in [hansard_bilingual_corpus.json.gz](./samples/hansard_bilingual_corpus.json.gz) (93.8 KB gzipped) **[fact]**.

### 10 Evaluated Topics and Follow Queries

| ID | Official Debate Subject | English Follow Query (`query_en`) | French Follow Query (`query_fr`) | Relevant EN Paras | Relevant FR Paras |
|---|---|---|---|---|---|
| `T01` | Building Canada Strong Act (Bill C-69) | `Building Canada Strong` | `bâtir un Canada fort` | 30 | 30 |
| `T02` | First Nations Clean Water Act (Bill C-61) | `First Nations clean water` | `eau propre des Premières Nations` | 30 | 30 |
| `T03` | Youth Criminal Justice Act (Bill C-395) | `youth criminal justice` | `justice pénale pour les adolescents` | 30 | 30 |
| `T04` | Flood and Drought Forecasting Act (Bill C-351) | `flood and drought forecasting` | `prévision des inondations et des sécheresses` | 30 | 30 |
| `T05` | Ukrainian Heritage Month Act (Bill C-411) | `Ukrainian Heritage Month` | `Mois du patrimoine ukrainien` | 30 | 30 |
| `T06` | Sergei Magnitsky Act (Bill S-222) | `Magnitsky sanctions` | `sanctions Magnitski` | 30 | 30 |
| `T07` | Criminal Code: Places of Worship (Bill C-255) | `places of worship` | `lieux de culte` | 30 | 30 |
| `T08` | Diesel Fuel Prices (Opposition Supply Day) | `diesel prices` | `prix du diesel` | 30 | 30 |
| `T09` | Taxation and Tax Relief | `taxation` | `fiscalité` | 30 | 30 |
| `T10` | Public Services and Procurement | `government procurement` | `approvisionnement public` | 30 | 30 |

---

## 3. Empirical Benchmark Results

Each model was evaluated sequentially with a fresh unit restart between models to ensure monotonic systemd cgroup counters (`MemoryPeak`) reflected only that specific model **[fact]**. Results were generated by [benchmark_embeddings_bilingual.py](./scripts/benchmark_embeddings_bilingual.py) and saved in [benchmark_results.json](./samples/benchmark_results.json) **[fact]**.

### A. Memory Footprint

`MemoryCurrent` was measured with no model loaded (daemon baseline), after loading the model with an initial embedding, and `MemoryPeak` was recorded after completing all inference batches **[fact]**:

| Model | Parameters | Download Size | Unloaded Daemon (`MemoryCurrent`) | Loaded Model (`MemoryCurrent`) | Inference Peak (`MemoryPeak`) | Fits 300 MB Budget? |
|---|---|---|---|---|---|---|
| `all-minilm:33m` | 33M | 67 MB | 30.3 MB | **171.7 MB** | **251.7 MB** | **YES** (+48.3 MB headroom) |
| `granite-embedding:278m` | 278M | 562 MB | 16.1 MB | 1,044.6 MB | 1,326.2 MB | **NO** (+744.6 MB over budget) |
| `paraphrase-multilingual:latest` | 278M | 562 MB | 17.3 MB | 1,144.7 MB | 1,272.5 MB | **NO** (+844.7 MB over budget) |
| `embeddinggemma:300m` | 300M | 621 MB | 71.3 MB | 1,256.7 MB | 1,612.3 MB | **NO** (+956.7 MB over budget) |
| `embeddinggemma-2:270m` | 270M | — | — | — | — | **N/A** (Pull failed HTTP 412) |

### B. Throughput Benchmark

Throughput was measured by processing 1,000 real Hansard paragraphs (cycling the 600-paragraph corpus) sent in batches of 32 via `POST /api/embed` with `"input": [list]` **[fact]**:

| Model | Paragraphs Evaluated | Batch Size | Wall Clock Time | Throughput | Relative Speed vs. Baseline |
|---|---|---|---|---|---|
| `all-minilm:33m` | 1,000 | 32 | 43.19 s | **23.15 paragraphs/sec** | 1.00x (baseline) |
| `paraphrase-multilingual:latest` | 1,000 | 32 | 111.00 s | **9.01 paragraphs/sec** | 0.39x |
| `granite-embedding:278m` | 1,000 | 32 | 132.86 s | **7.53 paragraphs/sec** | 0.33x |
| `embeddinggemma:300m` | 1,000 | 32 | 156.72 s | **6.38 paragraphs/sec** | 0.28x |

### C. Bilingual Retrieval Quality

Quality was measured across all 10 topics using Top-10 ranking over the corpus, partitioned into mono-lingual and cross-lingual directions **[fact]**:
- `EN -> EN`: English query against 300 English paragraphs.
- `EN -> FR`: English query against 300 French paragraphs (cross-lingual).
- `FR -> EN`: French query against 300 English paragraphs (cross-lingual).
- `FR -> FR`: French query against 300 French paragraphs.
- `Global EN / Global FR`: Query evaluated over all 600 corpus paragraphs simultaneously.

Since each topic has 30 relevant paragraphs in each 300-paragraph language partition, Precision@10 ($P@10 = \text{correct} / 10$) and Recall@10 ($R@10 = \text{correct} / 30$) measure the top 10 returned candidates **[fact]**:

#### Cross-Language Performance Matrix (Macro-Averaged Precision@10 / Recall@10)

| Model | EN $\to$ EN (P / R) | EN $\to$ FR (P / R) [Cross] | FR $\to$ EN (P / R) [Cross] | FR $\to$ FR (P / R) | Global EN Pool (P / R) | Global FR Pool (P / R) |
|---|---|---|---|---|---|---|
| `paraphrase-multilingual:latest` | **0.76 / 0.25** | **0.73 / 0.24** | 0.67 / 0.22 | **0.69 / 0.23** | **0.86 / 0.14** | 0.78 / 0.13 |
| `embeddinggemma:300m` | 0.75 / 0.25 | 0.71 / 0.24 | **0.70 / 0.23** | 0.65 / 0.22 | 0.78 / 0.13 | **0.79 / 0.13** |
| `granite-embedding:278m` | 0.73 / 0.24 | 0.68 / 0.23 | 0.64 / 0.21 | 0.66 / 0.22 | **0.86 / 0.14** | 0.76 / 0.13 |
| `all-minilm:33m` | 0.71 / 0.24 | 0.55 / 0.18 | 0.53 / 0.18 | 0.41 / 0.14 | 0.74 / 0.12 | 0.44 / 0.07 |

---

## 4. Per-Topic Quality Breakdown

The table below details Precision@10 ($P@10$) for each topic across models **[fact]**:

| Topic ID & English Query | `all-minilm:33m` (EN $\to$ EN / EN $\to$ FR / FR $\to$ FR) | `granite-embedding:278m` (EN $\to$ EN / EN $\to$ FR / FR $\to$ FR) | `embeddinggemma:300m` (EN $\to$ EN / EN $\to$ FR / FR $\to$ FR) | `paraphrase-multilingual` (EN $\to$ EN / EN $\to$ FR / FR $\to$ FR) |
|---|---|---|---|---|
| `T01` Building Canada Strong | 0.3 / 0.6 / 0.7 | 0.5 / 0.9 / 0.9 | 0.2 / 0.9 / 0.8 | 0.3 / 0.9 / 0.9 |
| `T02` First Nations clean water | **1.0 / 0.0 / 0.4** | **1.0 / 1.0 / 1.0** | **1.0 / 1.0 / 1.0** | **1.0 / 1.0 / 1.0** |
| `T03` youth criminal justice | 0.9 / 0.3 / 0.2 | 0.7 / 0.5 / 0.6 | 1.0 / 0.7 / 0.6 | 1.0 / 0.6 / 0.8 |
| `T04` flood & drought forecasting | 1.0 / 0.9 / 0.2 | 1.0 / 0.8 / 0.8 | 1.0 / 0.9 / 1.0 | 1.0 / 0.7 / 0.6 |
| `T05` Ukrainian Heritage Month | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 | 1.0 / 1.0 / 1.0 |
| `T06` Magnitsky sanctions | 1.0 / 0.9 / 0.7 | 0.9 / 0.7 / 0.7 | 0.9 / 0.5 / 0.4 | 0.9 / 0.8 / 0.8 |
| `T07` places of worship | 0.9 / 0.4 / 0.2 | 0.9 / 0.4 / 0.5 | 0.9 / 0.4 / 0.4 | 0.9 / 0.4 / 0.5 |
| `T08` diesel fuel prices | 0.4 / 0.4 / 0.3 | 0.6 / 0.4 / 0.4 | 0.5 / 0.5 / 0.4 | 0.5 / 0.6 / 0.6 |
| `T09` taxation | 0.2 / 0.7 / 0.3 | 0.1 / 0.6 / 0.5 | 0.1 / 0.5 / 0.4 | 0.3 / 0.6 / 0.6 |
| `T10` government procurement | 0.4 / 0.3 / 0.1 | 0.6 / 0.5 / 0.2 | 0.9 / 0.7 / 0.5 | 0.7 / 0.7 / 0.1 |

### Anti-Vacuity Probe on Cross-Lingual Failure

On topic `T02` ("First Nations clean water"), `all-minilm:33m` yielded **P@10 = 0.0 (0/10 correct)** on English $\to$ French cross-lingual matching **[fact]**. By contrast, `granite-embedding:278m`, `embeddinggemma:300m`, and `paraphrase-multilingual:latest` all achieved **P@10 = 1.0 (10/10 correct)** on the exact same query against the exact same French paragraphs **[fact]**. This directly proves that the relevant French paragraphs existed and were easily retrievable by multilingual models, but failed completely in `all-minilm` due to its lack of bilingual representation **[inference]**.

---

## 5. Trade-Off Analysis and Recommendation

The empirical data establishes a sharp trade-off between memory footprint and bilingual capability:

1. **The 300 MB Budget Barrier:**
   - `all-minilm:33m` is the **only** model that fits within the strict ~300 MB resident memory budget (171.7 MB loaded, 251.7 MB peak) **[fact]**.
   - However, its French performance degrades severely: French $\to$ French precision is only **0.41** (compared to 0.71 on English $\to$ English), and in global corpus retrieval, French query recall drops to **0.073 (7.3%)** **[fact]**. For cross-lingual retrieval (e.g. following "First Nations clean water"), it retrieves 0 out of 10 French speeches **[fact]**.
   - **Inference:** In an officially bilingual Canadian parliament where debates transition between English and French in the same sitting, `all-minilm:33m` cannot reliably serve French or cross-lingual follows.

2. **Multilingual Models Performance and Memory:**
   - All true multilingual models require approximately **1.0 to 1.3 GB** of loaded memory and **1.3 to 1.6 GB** of peak memory during batch inference **[fact]**.
   - `paraphrase-multilingual:latest` achieved the highest quality overall (**0.76 EN $\to$ EN, 0.73 EN $\to$ FR, 0.69 FR $\to$ FR**) and the highest multilingual CPU throughput (**9.01 paras/sec**) while requiring **1,144.7 MB** loaded memory (1,272.5 MB peak) **[fact]**.
   - `granite-embedding:278m` is a close runner-up with the lowest loaded memory among the multilingual models (**1,044.6 MB**, saving 100 MB compared to paraphrase-multilingual) and solid quality (**0.73 EN $\to$ EN, 0.68 EN $\to$ FR, 0.66 FR $\to$ FR**) at **7.53 paras/sec** **[fact]**.
   - `embeddinggemma:300m` had the highest memory footprint (**1,256.7 MB loaded, 1,612.3 MB peak**) and lowest throughput (**6.38 paras/sec**) without exceeding `paraphrase-multilingual` on average quality **[fact]**.

### Recommendation

**Recommendation:** For ParTake Parliament Watch, the service memory budget should be adjusted from 300 MB to **1,200 MB** resident memory (leaving >5.5 GB free on the Steam Deck's 16 GB RAM), and **`paraphrase-multilingual:latest`** should be deployed as the primary bilingual embedding model **[recommendation]**. If resident memory must be squeezed further while maintaining bilingual parity, **`granite-embedding:278m`** is recommended as a 100 MB lighter alternative at 1,044.6 MB **[recommendation]**. `all-minilm:33m` should only be used if hard hardware constraints make exceeding 300 MB impossible and French retrieval failure is accepted **[recommendation]**.

---

## Answer

On the Steam Deck, true bilingual Parliament Watch retrieval requires a model footprint of 1,045–1,145 MB resident memory. **`paraphrase-multilingual:latest`** is the recommended model, delivering balanced bilingual retrieval (P@10: 0.76 EN$\to$EN, 0.73 EN$\to$FR, 0.69 FR$\to$FR) at 9.01 paras/sec with 1,144.7 MB loaded / 1,272.5 MB peak memory, whereas the 300 MB baseline (`all-minilm:33m` at 171.7 MB loaded) suffers severe cross-lingual collapse (0.41 FR$\to$FR, 0.00 on clean water).

---

## Unknowns

1. **`embeddinggemma-2:270m` Retrieval Quality:** Because Ollama 0.35.1 returned HTTP 412 on manifest pull, this specific model could not be loaded or measured on the current system daemon without upgrading Ollama. The follow-up below tried Ollama 0.40.2: the model needs the MLX runtime, which the Linux build lacks, so its quality on this machine stays unmeasured.
2. **iGPU / Vulkan Acceleration Stability:** All models ran on CPU using `libggml-cpu-haswell.so` because Ollama explicitly drops the Steam Deck's Van Gogh RDNA 2 APU (`pci_id=0000:04:00.0`). Whether enabling Vulkan via `OLLAMA_IGPU_ENABLE=1` would lower CPU load or increase memory contention remains unmeasured.

---

## Sources

Every source URL cited was retrieved directly via HTTP GET with curl on 2026-10-11 using User-Agent `ParTake-research/0.1 (personal project)`, with HTTP status codes recorded at fetch time **[fact]**:

1. `https://ollama.com/library/granite-embedding` - HTTP 200 (accessed 2026-10-11)
2. `https://ollama.com/library/embeddinggemma-2` - HTTP 200 (accessed 2026-10-11)
3. `https://ollama.com/library/embeddinggemma` - HTTP 200 (accessed 2026-10-11)
4. `https://ollama.com/library/paraphrase-multilingual` - HTTP 200 (accessed 2026-10-11)
5. `https://ollama.com/library/all-minilm` - HTTP 200 (accessed 2026-10-11)
6. `https://ollama.com/download` - HTTP 200 (accessed 2026-10-11)
7. `https://www.ourcommons.ca/Content/House/451/Debates/145/HAN145-E.XML` - HTTP 200 (accessed 2026-10-11)
8. `https://www.ourcommons.ca/Content/House/451/Debates/145/HAN145-F.XML` - HTTP 200 (accessed 2026-10-11)
9. `https://www.ourcommons.ca/Content/House/451/Debates/146/HAN146-E.XML` - HTTP 200 (accessed 2026-10-11)
10. `https://www.ourcommons.ca/Content/House/451/Debates/146/HAN146-F.XML` - HTTP 200 (accessed 2026-10-11)
11. `https://www.ourcommons.ca/Content/House/451/Debates/147/HAN147-E.XML` - HTTP 200 (accessed 2026-10-11)
12. `https://www.ourcommons.ca/Content/House/451/Debates/147/HAN147-F.XML` - HTTP 200 (accessed 2026-10-11)
13. `https://www.ourcommons.ca/Content/House/451/Debates/148/HAN148-E.XML` - HTTP 200 (accessed 2026-10-11)
14. `https://www.ourcommons.ca/Content/House/451/Debates/148/HAN148-F.XML` - HTTP 200 (accessed 2026-10-11)
15. `https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-E.XML` - HTTP 200 (accessed 2026-10-11)
16. `https://www.ourcommons.ca/Content/House/451/Debates/149/HAN149-F.XML` - HTTP 200 (accessed 2026-10-11)

---

## System Clean-up and Verification

The transient unit `watch-embed-bench2.service` was stopped and unloaded, and the model cache `~/.cache/watch-embed-bench2` was removed **[fact]**:
```text
$ systemctl --user status watch-embed-bench2
Unit watch-embed-bench2.service could not be found.

$ ls -la ~/.cache/watch-embed-bench2
ls: cannot access '/home/deck/.cache/watch-embed-bench2': No such file or directory
```
The persistent user unit `ollama.service` remains `inactive (dead)` and unmanaged **[fact]**.

---

## Follow-up, 11 Oct 2026 (orchestrator): Ollama 0.40.2

Run by hand after the owner chose to try `embeddinggemma-2` on a newer
Ollama kept apart from the main install.

- **Install:** `ollama-linux-amd64.tar.zst` v0.40.2 extracted to
  `~/.local/ollama-watch/` without the `cuda_*`, `rocm*`, `vulkan` and `mlx*`
  library folders (61 MB on disk). The tarball has no MLX libraries in any
  case, only `MLX_LICENSE` and `MLX_C_LICENSE` **[fact]**.
- **`embeddinggemma-2`:** the library lists only MLX-format tags (`bf16`,
  `mxfp8`, `nvfp4`, in 270m/440m/570m/740m sizes). Pulling
  `embeddinggemma-2:270m` and `embeddinggemma-2:270m-bf16-text` both fail with
  `Error: this model requires MLX support, but the MLX runtime is not available`
  **[fact]**. It cannot run on this Deck.
- **`paraphrase-multilingual:latest` re-run** with the same script, corpus and
  server settings (port 11536, MemoryMax 2500M, context 512, batches of 32):
  identical quality (P@10 0.76 / 0.73 / 0.67 / 0.69 for EN->EN, EN->FR,
  FR->EN, FR->FR), 9.17 paragraphs/s, and much less memory: **712.5 MB
  loaded, 874.0 MB peak**, against 1,144.7 / 1,272.5 MB on 0.35.1 **[fact]**.
  Both runs are in `samples/benchmark_results.json` (the new one under
  `paraphrase-multilingual:latest @ ollama 0.40.2`).
- **Decision:** `paraphrase-multilingual` on Ollama 0.40.2 (see
  `docs/watch/PLAN.md`, Decisions 5). The pulled model was kept in
  `~/.local/ollama-watch/models` for the watch embedding service.
