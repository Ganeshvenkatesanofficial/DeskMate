"""
knowledge.graph — Canvas knowledge-graph builder
============================================================
Builds one render-ready ``GraphSnapshot`` over the indexed files from four
signals:

* **similar**  — cosine k-NN between file centroids (mean of chunk vectors);
* **entity**   — files that mention the same person/organisation/place get
                 linked through an entity node;
* **tag**      — user tags become hub nodes;
* **temporal** — files modified within the same working session are chained.

Communities come from Louvain (networkx). Layout is computed here so the
Flutter canvas only has to paint: clusters sit on a ring sized by
membership, each cluster gets a seeded spring layout, and isolated files trail
along an outer arc. Progress streams as ``graph.progress`` events.
"""

from __future__ import annotations

import json
import logging
import math
import threading
import time
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np

from db import events, store
from knowledge import vector_store
from settings import get_user_data_dir

logger = logging.getLogger("deskmate.folder_agent.graph")

MAX_FILES = 4000
K_NEIGHBOURS = 6
SIM_THRESHOLD = 0.78
SESSION_GAP_S = 25 * 60
ENTITY_MIN_FILES, ENTITY_MAX_FILES = 2, 40
MAX_ENTITIES = 400
_SNAPSHOT = get_user_data_dir() / "folder_agent_graph.json"

_build_lock = threading.Lock()
_state: dict[str, Any] = {"state": "idle", "phase": None, "done": 0, "total": 0}


def status() -> dict[str, Any]:
    return dict(_state, builtAt=_snapshot_built_at())


def _progress(phase: str | None, done: int, total: int, state: str = "building") -> None:
    _state.update(state=state, phase=phase, done=done, total=total)
    events.publish("graph.progress", **_state)


def _snapshot_built_at() -> float | None:
    try:
        return _SNAPSHOT.stat().st_mtime
    except OSError:
        return None


def get_snapshot() -> dict[str, Any] | None:
    try:
        return json.loads(_SNAPSHOT.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def build_async() -> dict[str, Any]:
    if _build_lock.locked():
        return status()
    threading.Thread(target=build, name="fa-graph", daemon=True).start()
    return status()


def build() -> dict[str, Any] | None:
    if not _build_lock.acquire(blocking=False):
        return None
    try:
        snap = _build()
        _SNAPSHOT.write_text(json.dumps(snap))
        _progress(None, 0, 0, state="idle")
        events.publish("graph.ready", stats=snap["stats"], builtAt=snap["builtAt"])
        return snap
    except Exception as exc:
        logger.error(f"[GRAPH] Build failed: {exc}", exc_info=True)
        _state.update(state="error", error=str(exc))
        events.publish("graph.progress", **_state)
        return None
    finally:
        _build_lock.release()


# ─── build ───────────────────────────────────────────────────────────────────

def _centroids() -> tuple[list[str], np.ndarray, dict[str, dict[str, Any]]]:
    sums: dict[str, np.ndarray] = {}
    counts: dict[str, int] = defaultdict(int)
    meta: dict[str, dict[str, Any]] = {}
    for path, vec, payload in vector_store.iter_vectors():
        if path in sums:
            sums[path] += vec
        else:
            sums[path] = vec.copy()
            meta[path] = payload
        counts[path] += 1
    paths = [p for p in sums if Path(p).exists()]
    if not paths:
        return [], np.zeros((0, 0), dtype=np.float32), {}
    mat = np.stack([sums[p] / counts[p] for p in paths]).astype(np.float32)
    mat /= np.maximum(np.linalg.norm(mat, axis=1, keepdims=True), 1e-9)
    return paths, mat, meta


def _knn_edges(paths: list[str], mat: np.ndarray) -> list[tuple[int, int, float]]:
    n = len(paths)
    edges: dict[tuple[int, int], float] = {}
    block = 512
    for start in range(0, n, block):
        sims = mat[start : start + block] @ mat.T
        for r in range(sims.shape[0]):
            i = start + r
            sims[r, i] = -1.0
            k = min(K_NEIGHBOURS, n - 1)
            if k <= 0:
                continue
            idx = np.argpartition(-sims[r], k)[:k]
            for j in idx:
                s = float(sims[r, j])
                if s >= SIM_THRESHOLD:
                    key = (min(i, int(j)), max(i, int(j)))
                    edges[key] = max(edges.get(key, 0.0), s)
        _progress("similarity", min(n, start + block), n)
    return [(a, b, w) for (a, b), w in edges.items()]


def _build() -> dict[str, Any]:
    import networkx as nx

    _progress("similarity", 0, 0)
    paths, mat, meta = _centroids()
    stats_truncated = False

    file_nodes: dict[str, dict[str, Any]] = {}
    for p in paths:
        try:
            st = Path(p).stat()
        except OSError:
            continue
        file_nodes[p] = {
            "id": f"f:{p}", "kind": "file", "label": Path(p).name, "path": p,
            "ext": Path(p).suffix.lower().lstrip("."), "mtime": st.st_mtime, "size": st.st_size,
            "fileKind": meta.get(p, {}).get("kind", "file"),
        }
    keep_rows = [i for i, p in enumerate(paths) if p in file_nodes]
    if len(keep_rows) != len(paths):
        mat = mat[keep_rows]
        paths = [paths[i] for i in keep_rows]

    G = nx.Graph()
    edges_out: list[dict[str, Any]] = []

    def add_edge(a: str, b: str, kind: str, w: float) -> None:
        if a == b:
            return
        G.add_edge(a, b, weight=G.get_edge_data(a, b, {}).get("weight", 0) + w)
        edges_out.append({"source": a, "target": b, "kind": kind, "weight": round(w, 4)})

    for p in paths:
        G.add_node(f"f:{p}")

    # similar
    for i, j, w in _knn_edges(paths, mat) if len(paths) > 1 else []:
        add_edge(f"f:{paths[i]}", f"f:{paths[j]}", "similar", w)

    # entities
    _progress("entities", 0, 1)
    path_set = set(paths)
    by_entity: dict[str, set[str]] = defaultdict(set)
    for path, name, _count in store.all_entities():
        if path in path_set:
            by_entity[name].add(path)
    entity_nodes = []
    ranked = sorted(
        ((name, files) for name, files in by_entity.items() if ENTITY_MIN_FILES <= len(files) <= ENTITY_MAX_FILES),
        key=lambda x: -len(x[1]),
    )[:MAX_ENTITIES]
    for name, files in ranked:
        eid = f"e:{name.lower()}"
        entity_nodes.append({"id": eid, "kind": "entity", "label": name, "entityType": "MISC"})
        G.add_node(eid)
        for f in files:
            add_edge(eid, f"f:{f}", "entity", 1.0 / math.sqrt(len(files)))
    _progress("entities", 1, 1)

    # tags
    tags = {t["id"]: t for t in store.list_tags()}
    tag_nodes = {}
    for path, tag_id in store.all_file_tags():
        if path not in path_set or tag_id not in tags:
            continue
        tid = f"t:{tag_id}"
        if tid not in tag_nodes:
            t = tags[tag_id]
            tag_nodes[tid] = {"id": tid, "kind": "tag", "label": t["name"], "color": t["color"]}
            G.add_node(tid)
        add_edge(tid, f"f:{path}", "tag", 1.0)

    # temporal sessions
    by_time = sorted(paths, key=lambda p: file_nodes[p]["mtime"])
    for a, b in zip(by_time, by_time[1:]):
        if file_nodes[b]["mtime"] - file_nodes[a]["mtime"] <= SESSION_GAP_S and Path(a).parent == Path(b).parent:
            add_edge(f"f:{a}", f"f:{b}", "temporal", 0.5)

    # cap: keep the best-connected (then most recent) files
    _progress("assemble", 0, 1)
    if len(paths) > MAX_FILES:
        stats_truncated = True
        keep = sorted(paths, key=lambda p: (G.degree(f"f:{p}"), file_nodes[p]["mtime"]), reverse=True)[:MAX_FILES]
        drop = {f"f:{p}" for p in set(paths) - set(keep)}
        G.remove_nodes_from(drop)
        edges_out = [e for e in edges_out if e["source"] not in drop and e["target"] not in drop]
        paths = keep

    # communities
    clusters: dict[str, int] = {}
    if G.number_of_edges():
        comms = nx.community.louvain_communities(G, weight="weight", seed=42, resolution=1.0)
        comms = sorted(comms, key=len, reverse=True)
        for cid, members in enumerate(comms):
            for m in members:
                clusters[m] = cid
    for node in G.nodes:
        clusters.setdefault(node, -1)

    positions = _layout(G, clusters)

    nodes: list[dict[str, Any]] = []
    for p in paths:
        nid = f"f:{p}"
        nodes.append({**file_nodes[p], "degree": G.degree(nid), "clusterId": clusters.get(nid, -1), **positions.get(nid, {"x": 0, "y": 0})})
    for n in entity_nodes + list(tag_nodes.values()):
        if n["id"] in G:
            nodes.append({**n, "degree": G.degree(n["id"]), "clusterId": clusters.get(n["id"], -1), **positions.get(n["id"], {"x": 0, "y": 0})})

    _progress("assemble", 1, 1)
    times = [file_nodes[p]["mtime"] for p in paths]
    return {
        "nodes": nodes,
        "edges": edges_out,
        "builtAt": time.time(),
        "stats": {
            "files": len(paths),
            "entities": len(entity_nodes),
            "tags": len(tag_nodes),
            "edges": len(edges_out),
            "clusters": len({c for c in clusters.values() if c >= 0}),
            "truncated": stats_truncated,
            "minTime": min(times) if times else None,
            "maxTime": max(times) if times else None,
        },
    }


def _layout(G, clusters: dict[str, int]) -> dict[str, dict[str, float]]:
    """Clusters on a ring (big ones near the centre), spring layout inside each, singletons on an arc."""
    import networkx as nx

    members: dict[int, list[str]] = defaultdict(list)
    for node, cid in clusters.items():
        members[cid].append(node)
    singles = [n for n in members.pop(-1, [])]
    # Single-node "communities" are singletons too.
    for cid in [c for c, m in members.items() if len(m) == 1]:
        singles.extend(members.pop(cid))

    pos: dict[str, dict[str, float]] = {}
    ordered = sorted(members.items(), key=lambda kv: -len(kv[1]))
    golden = math.pi * (3 - math.sqrt(5))
    for rank, (cid, nodes) in enumerate(ordered):
        radius = 60 * math.sqrt(len(nodes))
        # Sunflower placement: biggest cluster centred, the rest spiral outward.
        dist = 0 if rank == 0 else 260 * math.sqrt(rank) + radius
        angle = rank * golden
        cx, cy = dist * math.cos(angle), dist * math.sin(angle)
        sub = G.subgraph(nodes)
        if len(nodes) > 2:
            local = nx.spring_layout(sub, seed=cid + 7, iterations=40 if len(nodes) < 400 else 20, weight="weight")
        else:
            local = {n: np.array([i - 0.5, 0.0]) for i, n in enumerate(nodes)}
        for n, (x, y) in local.items():
            pos[n] = {"x": round(cx + float(x) * radius, 2), "y": round(cy + float(y) * radius, 2)}

    if singles:
        extent = max((math.hypot(p["x"], p["y"]) for p in pos.values()), default=300) + 220
        span = math.pi * 0.9
        for i, n in enumerate(sorted(singles)):
            t = 0.5 if len(singles) == 1 else i / (len(singles) - 1)
            a = math.pi * 0.55 + span * t
            pos[n] = {"x": round(extent * math.cos(a), 2), "y": round(extent * math.sin(a), 2)}
    return pos
