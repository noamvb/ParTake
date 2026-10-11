#!/usr/bin/env python3
"""Extract 600 Hansard paragraphs (300 EN, 300 FR) from sittings 145-149.

Ensures:
- 10 distinct topics with official debate headings.
- Exactly 30 English and 30 French paragraphs per topic.
- English and French paragraphs are drawn from mutually exclusive intervention IDs
  to prevent translation pairs from making cross-lingual retrieval trivial.
- Paragraphs are saved under samples/hansard_bilingual_corpus.json.gz.
"""

from collections import defaultdict
import sys
import gzip
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET


TOPIC_DEFS = [
    {
        "id": "T01",
        "name_en": "Building Canada Strong Act (Bill C-69)",
        "name_fr": "Loi visant à bâtir un Canada fort (projet de loi C-69)",
        "query_en": "Building Canada Strong",
        "query_fr": "bâtir un Canada fort",
        "match": lambda st, sq: "Building Canada Strong" in st or "bâtir un Canada fort" in st,
    },
    {
        "id": "T02",
        "name_en": "First Nations Clean Water Act (Bill C-61)",
        "name_fr": "Loi sur l'eau propre des Premières Nations (projet de loi C-61)",
        "query_en": "First Nations clean water",
        "query_fr": "eau propre des Premières Nations",
        "match": lambda st, sq: "Clean Water" in st or "eau propre" in st,
    },
    {
        "id": "T03",
        "name_en": "Youth Criminal Justice Act (Bill C-395)",
        "name_fr": "Loi sur la justice pénale pour les adolescents (projet de loi C-395)",
        "query_en": "youth criminal justice",
        "query_fr": "justice pénale pour les adolescents",
        "match": lambda st, sq: "Youth Criminal Justice" in st or "justice pénale pour les adolescents" in st,
    },
    {
        "id": "T04",
        "name_en": "Flood and Drought Forecasting Act (Bill C-351)",
        "name_fr": "Loi sur la prévision des inondations et des sécheresses (projet de loi C-351)",
        "query_en": "flood and drought forecasting",
        "query_fr": "prévision des inondations et des sécheresses",
        "match": lambda st, sq: "Flood and Drought" in st or "inondations et des sécheresses" in st,
    },
    {
        "id": "T05",
        "name_en": "Ukrainian Heritage Month Act (Bill C-411)",
        "name_fr": "Loi sur le Mois du patrimoine ukrainien (projet de loi C-411)",
        "query_en": "Ukrainian Heritage Month",
        "query_fr": "Mois du patrimoine ukrainien",
        "match": lambda st, sq: "Ukrainian Heritage Month" in st or "Mois du patrimoine ukrainien" in st,
    },
    {
        "id": "T06",
        "name_en": "Sergei Magnitsky Act (Bill S-222)",
        "name_fr": "Loi de Sergueï Magnitski (projet de loi S-222)",
        "query_en": "Magnitsky sanctions",
        "query_fr": "sanctions Magnitski",
        "match": lambda st, sq: "Magnitsky" in st or "Magnitski" in st,
    },
    {
        "id": "T07",
        "name_en": "Criminal Code: Places of Worship (Bill C-255)",
        "name_fr": "Code criminel : lieux de culte (projet de loi C-255)",
        "query_en": "places of worship",
        "query_fr": "lieux de culte",
        "match": lambda st, sq: st == "Criminal Code" or st == "Le Code criminel",
    },
    {
        "id": "T08",
        "name_en": "Diesel Fuel Prices (Opposition Motion)",
        "name_fr": "Prix du carburant diesel (motion de l'opposition)",
        "query_en": "diesel prices",
        "query_fr": "prix du diesel",
        "match": lambda st, sq: "Diesel" in st or "diésel" in st or "Diesel" in sq or "diésel" in sq,
    },
    {
        "id": "T09",
        "name_en": "Taxation and Tax Relief",
        "name_fr": "La fiscalité et allègement fiscal",
        "query_en": "taxation",
        "query_fr": "fiscalité",
        "match": lambda st, sq: st == "Taxation" or st == "La fiscalité",
    },
    {
        "id": "T10",
        "name_en": "Public Services and Procurement",
        "name_fr": "Services publics et Approvisionnement",
        "query_en": "government procurement",
        "query_fr": "approvisionnement public",
        "match": lambda st, sq: "Procurement" in st or "approvisionnement" in st.lower(),
    },
]


def extract_paragraphs(scratch_xml_dir: Path):
    all_paras_en = []
    all_paras_fr = []
    topics_meta = []
    global_ivs_e = set()
    global_ivs_f = set()

    for t in TOPIC_DEFS:
        tid = t["id"]
        match_fn = t["match"]
        intervs_e = defaultdict(list)
        intervs_f = defaultdict(list)

        for n in range(145, 150):
            fn_e = scratch_xml_dir / f"HAN{n}-E.XML"
            tree_e = ET.parse(fn_e)
            for sob in tree_e.iter("SubjectOfBusiness"):
                st = (sob.findtext("SubjectOfBusinessTitle") or "").strip()
                sq = (sob.findtext("SubjectOfBusinessQualifier") or "").strip()
                if match_fn(st, sq):
                    for iv in sob.findall(".//Intervention"):
                        ivid = iv.attrib.get("id")
                        if not ivid:
                            continue
                        for pt in iv.findall(".//ParaText"):
                            pid = pt.attrib.get("id", "")
                            txt = " ".join("".join(pt.itertext()).split())
                            # Skip tiny fragments or procedural remarks
                            if len(txt) >= 40:
                                intervs_e[ivid].append({
                                    "original_para_id": pid,
                                    "sitting": n,
                                    "heading": st,
                                    "qualifier": sq,
                                    "text": txt,
                                    "word_count": len(txt.split()),
                                })

            fn_f = scratch_xml_dir / f"HAN{n}-F.XML"
            tree_f = ET.parse(fn_f)
            for sob in tree_f.iter("SubjectOfBusiness"):
                st = (sob.findtext("SubjectOfBusinessTitle") or "").strip()
                sq = (sob.findtext("SubjectOfBusinessQualifier") or "").strip()
                if match_fn(st, sq):
                    for iv in sob.findall(".//Intervention"):
                        ivid = iv.attrib.get("id")
                        if not ivid:
                            continue
                        for pt in iv.findall(".//ParaText"):
                            pid = pt.attrib.get("id", "")
                            txt = " ".join("".join(pt.itertext()).split())
                            if len(txt) >= 40:
                                intervs_f[ivid].append({
                                    "original_para_id": pid,
                                    "sitting": n,
                                    "heading": st,
                                    "qualifier": sq,
                                    "text": txt,
                                    "word_count": len(txt.split()),
                                })

        # Partition interventions between EN and FR
        all_ivs = sorted(list(set(intervs_e.keys()) | set(intervs_f.keys())))

        # Greedy selection to ensure exactly 30 paragraphs for EN and 30 for FR
        ivs_for_e = []
        count_e = 0
        for iv in all_ivs:
            if count_e < 30 and len(intervs_e[iv]) > 0:
                ivs_for_e.append(iv)
                count_e += len(intervs_e[iv])

        ivs_for_f = [iv for iv in all_ivs if iv not in ivs_for_e and len(intervs_f[iv]) > 0]

        # Draw exactly 30 paragraphs for EN
        t_paras_e = []
        used_e_ivs = set()
        for iv in ivs_for_e:
            for p in intervs_e[iv]:
                t_paras_e.append({
                    "topic_id": tid,
                    "lang": "en",
                    "intervention_id": iv,
                    **p,
                })
                used_e_ivs.add(iv)
                if len(t_paras_e) == 30:
                    break
            if len(t_paras_e) == 30:
                break

        # Draw exactly 30 paragraphs for FR
        t_paras_f = []
        used_f_ivs = set()
        for iv in ivs_for_f:
            for p in intervs_f[iv]:
                t_paras_f.append({
                    "topic_id": tid,
                    "lang": "fr",
                    "intervention_id": iv,
                    **p,
                })
                used_f_ivs.add(iv)
                if len(t_paras_f) == 30:
                    break
            if len(t_paras_f) == 30:
                break

        assert len(t_paras_e) == 30, f"Topic {tid} has {len(t_paras_e)} EN paras, expected 30"
        assert len(t_paras_f) == 30, f"Topic {tid} has {len(t_paras_f)} FR paras, expected 30"
        assert len(used_e_ivs & used_f_ivs) == 0, f"Topic {tid} interventions overlap!"

        global_ivs_e.update(used_e_ivs)
        global_ivs_f.update(used_f_ivs)

        all_paras_en.extend(t_paras_e)
        all_paras_fr.extend(t_paras_f)

        topics_meta.append({
            "id": tid,
            "name_en": t["name_en"],
            "name_fr": t["name_fr"],
            "query_en": t["query_en"],
            "query_fr": t["query_fr"],
            "en_intervention_count": len(used_e_ivs),
            "fr_intervention_count": len(used_f_ivs),
        })

    assert len(global_ivs_e & global_ivs_f) == 0, "Global intervention overlap detected!"
    assert len(all_paras_en) == 300, f"Expected 300 EN paras, got {len(all_paras_en)}"
    assert len(all_paras_fr) == 300, f"Expected 300 FR paras, got {len(all_paras_fr)}"

    # Assign final sequential IDs
    all_paras = []
    for idx, p in enumerate(all_paras_en):
        all_paras.append({
            "id": f"P_EN_{idx+1:03d}",
            **p,
        })
    for idx, p in enumerate(all_paras_fr):
        all_paras.append({
            "id": f"P_FR_{idx+1:03d}",
            **p,
        })

    # Add ground truth lists to topics
    for t in topics_meta:
        tid = t["id"]
        rel_en = [p["id"] for p in all_paras if p["topic_id"] == tid and p["lang"] == "en"]
        rel_fr = [p["id"] for p in all_paras if p["topic_id"] == tid and p["lang"] == "fr"]
        t["relevant_en_ids"] = rel_en
        t["relevant_fr_ids"] = rel_fr
        t["relevant_total_ids"] = rel_en + rel_fr

    return {
        "metadata": {
            "description": "Bilingual Canadian Hansard debate corpus (sittings 145-149, 45th Parl 1st Sess)",
            "total_paragraphs": len(all_paras),
            "en_paragraphs": len(all_paras_en),
            "fr_paragraphs": len(all_paras_fr),
            "topics_count": len(topics_meta),
            "disjoint_interventions": True,
            "unique_en_interventions": len(global_ivs_e),
            "unique_fr_interventions": len(global_ivs_f),
        },
        "topics": topics_meta,
        "paragraphs": all_paras,
    }


def main():
    # Directory holding HAN145-E.XML ... HAN149-F.XML (download them from the
    # ourcommons.ca URLs listed in REPORT.md first).
    scratch_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("hansard")
    out_dir = Path(__file__).resolve().parent.parent / "samples"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_gz = out_dir / "hansard_bilingual_corpus.json.gz"

    dataset = extract_paragraphs(scratch_dir)
    raw_json = json.dumps(dataset, indent=2, ensure_ascii=False).encode("utf-8")

    with gzip.open(out_gz, "wb") as f:
        f.write(raw_json)

    print(f"Wrote {len(raw_json)} bytes ({len(raw_json)/(1024):.1f} KB uncompressed) to {out_gz}")
    print(f"Gzipped size: {os.path.getsize(out_gz)/(1024):.1f} KB")
    print(f"Corpus stats: {dataset['metadata']}")


if __name__ == "__main__":
    main()
