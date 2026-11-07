"""
knowledge.search — Fused name + meaning search
==========================================================
One ranked list from two lanes:

* **name** — breadth-first tokenized filename search (``fs_service``).
* **meaning** — FastEmbed query vector against the Qdrant chunk index.

Meaning hits are z-normalised against the query's own score distribution, so
a query nothing in the index answers returns *nothing* instead of the nearest
noise. A file qualifies on meaning when it stands out (z ≥ 2) **and** clears
an absolute cosine floor, or when its best passage holds at least half of the
query's words. Filename evidence anchors the rank; both-lane hits get a bump.
"""

from __future__ import annotations

import math
import os
import re
import time
from pathlib import Path
from typing import Any

from knowledge import embedder, vector_store
from files import fs_service
from knowledge.indexer import is_hidden_from_ai

MIN_MATCH = 0.62          # bge-small cosine floor for a meaning hit
Z_QUALIFY = 2.0
Z_STRONG = 3.0
_WORD = re.compile(r"[\w']+", re.UNICODE)
_STOP = {
    "a", "an", "the", "of", "in", "on", "for", "to", "and", "or", "my", "me", "from", "with", "about", "is",
    "are", "was", "that", "this", "find", "show", "file", "files", "where", "what", "which", "i",
}

KIND_GROUPS = {
    "folders": {"folder"},
    "docs": {"pdf", "document", "spreadsheet", "presentation", "ebook"},
    "images": {"image"},
    "audio": {"audio"},
    "video": {"video"},
    "code": {"code", "data"},
}


def query_terms(q: str) -> list[str]:
    return [w for w in (m.lower() for m in _WORD.findall(q)) if len(w) > 1 and w not in _STOP]


def mark_snippet(text: str, terms: list[str], width: int = 220) -> str:
    """A window of ``text`` around the first query term, terms wrapped in «»."""
    if not text:
        return ""
    flat = " ".join(text.split())
    lower = flat.lower()
    first = min((i for i in (lower.find(t) for t in terms) if i >= 0), default=0)
    start = max(0, first - width // 3)
    snippet = flat[start : start + width]
    if start > 0:
        snippet = "…" + snippet
    if start + width < len(flat):
        snippet += "…"
    for t in sorted(set(terms), key=len, reverse=True):
        snippet = re.sub(rf"(?i)(?<!«)\b({re.escape(t)}\w*)", r"«\1»", snippet)
    return snippet


def _coverage(terms: list[str], text: str) -> float:
    if not terms:
        return 0.0
    lower = text.lower()
    return sum(1 for t in terms if t in lower) / len(terms)


def search(
    query: str,
    root: str | None = None,
    scope: str = "everywhere",
    kinds: list[str] | None = None,
    since: float | None = None,
    limit: int = 60,
) -> dict[str, Any]:
    t0 = time.monotonic()
    q = query.strip()
    if not q:
        return {"results": [], "strong": 0, "lanes": [], "tookMs": 0}
    terms = query_terms(q)
    allowed = set().union(*(KIND_GROUPS.get(k, {k}) for k in kinds)) if kinds else None
    search_root = root if (scope == "folder" and root) else str(Path.home())
    lanes: list[str] = ["name"]

    merged: dict[str, dict[str, Any]] = {}

    # ── name lane ───────────────────────────────────────────────────────────
    # "Everywhere" sweeps the folder in view first (FilDOS), then the home folder.
    roots = [search_root]
    if scope != "folder" and root and root != search_root:
        roots.insert(0, root)
    name_hits = [h for r in roots for h in fs_service.name_search(q, r, limit=150, deadline_s=1.5 / len(roots))]
    for hit in name_hits:
        if hit["path"] in merged:
            continue
        merged[hit["path"]] = {
            **hit,
            "lanes": ["name"],
            "nameTier": hit.pop("tier", 1),
            "meaning": None,
            "snippet": None,
            "page": None,
        }

    # ── meaning lane ────────────────────────────────────────────────────────
    meaning_ok = embedder.is_downloaded() and not embedder.is_downloading()
    if meaning_ok:
        try:
            qv = embedder.embed_query(q)
            prefix = (root.rstrip(os.sep) + os.sep) if (scope == "folder" and root) else None
            chunks = vector_store.query(qv, limit=400, path_prefix=prefix)
        except Exception:
            chunks = []
        if chunks:
            lanes.append("meaning")
            scores = [c["score"] for c in chunks]
            mean = sum(scores) / len(scores)
            std = math.sqrt(sum((s - mean) ** 2 for s in scores) / len(scores)) or 1e-6
            best: dict[str, dict[str, Any]] = {}
            for c in chunks:
                path = c.get("path")
                if not path or (path in best and best[path]["score"] >= c["score"]):
                    continue
                best[path] = c
            for path, c in best.items():
                if is_hidden_from_ai(path):
                    continue
                z = (c["score"] - mean) / std
                cov = _coverage(terms, c.get("text", "") + " " + Path(path).name)
                qualifies = (z >= Z_QUALIFY and c["score"] >= MIN_MATCH) or (cov >= 0.5 and c["score"] >= MIN_MATCH - 0.08)
                if not qualifies:
                    continue
                meaning = z + 2 * cov ** 1.5
                entry = merged.get(path)
                if entry is None:
                    try:
                        entry = fs_service.entry_for(Path(path))
                    except OSError:
                        continue
                    entry.update({"lanes": [], "nameTier": 0})
                    merged[path] = entry
                entry["lanes"] = sorted(set(entry["lanes"]) | {"meaning"})
                entry["meaning"] = round(meaning, 3)
                entry["cosine"] = round(c["score"], 4)
                entry["z"] = round(z, 2)
                entry["snippet"] = mark_snippet(c.get("text", ""), terms)
                entry["page"] = c.get("page")
                entry["passage"] = c.get("text", "")[:1200]

    # ── fuse ────────────────────────────────────────────────────────────────
    results = []
    for entry in merged.values():
        if allowed and entry.get("kind") not in allowed:
            continue
        if since and entry.get("mtime", 0) < since:
            continue
        name_part = entry.get("nameTier", 0) * 3.0
        meaning_part = (entry.get("meaning") or 0.0) * (0.5 if name_part else 1.0)
        both = 1.0 if len(entry["lanes"]) == 2 else 0.0
        entry["score"] = round(name_part + meaning_part + both, 3)
        entry["strong"] = entry.get("nameTier", 0) >= 2 or (entry.get("z") or 0) >= Z_STRONG
        results.append(entry)
    results.sort(key=lambda e: (-e["score"], e["name"].lower()))
    results = results[:limit]
    return {
        "results": results,
        "strong": sum(1 for r in results if r["strong"]),
        "lanes": lanes,
        "meaningAvailable": meaning_ok,
        "tookMs": int((time.monotonic() - t0) * 1000),
    }


def search_passages(query: str, limit: int = 6, root: str | None = None) -> list[dict[str, Any]]:
    """Top passages for the Folder Agent's ``search_index`` tool and ``/find``."""
    if not embedder.is_downloaded():
        return []
    res = search(query, root=root, scope="folder" if root else "everywhere", limit=limit * 2)
    return [
        {"path": r["path"], "name": r["name"], "page": r.get("page"), "passage": r.get("passage") or "", "score": r["score"]}
        for r in res["results"]
        if "meaning" in r["lanes"] or r.get("nameTier")
    ][:limit]


def passages_in_file(path: str, query: str, limit: int = 5) -> list[dict[str, Any]]:
    """The passages of one indexed file that best cover the query (preview highlighting / open at page)."""
    terms = query_terms(query)
    chunks = vector_store.file_chunks(path)
    ranked = sorted(chunks, key=lambda c: -_coverage(terms, c.get("text", "")))
    return [{"page": c.get("page"), "snippet": mark_snippet(c.get("text", ""), terms)} for c in ranked[:limit]]
