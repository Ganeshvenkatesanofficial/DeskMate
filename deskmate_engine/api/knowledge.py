"""routers.folder_agent.knowledge — Index, search, Canvas graph (``/api/fa/{index,search,graph}``)."""

from __future__ import annotations

from typing import Optional

from fastapi import Query

from routers.folder_agent.common import ExtensionsBody, PathsBody, RootsBody, api_router, respond
from services.folder_agent import graph, indexer, search
from services.folder_agent.indexer import INDEXER, IndexSettings

router = api_router("knowledge")


@router.get("/index/status")
def index_status():
    return respond(INDEXER.status)


@router.post("/index/start")
def index_start():
    return respond(INDEXER.start)


@router.post("/index/pause")
def index_pause():
    return respond(INDEXER.pause)


@router.post("/index/clear")
def index_clear():
    return respond(INDEXER.clear)


@router.put("/index/roots")
def index_roots(body: RootsBody):
    return respond(lambda: IndexSettings.set_roots(body.roots))


@router.post("/index/excludes")
def add_excludes(body: PathsBody):
    return respond(lambda: IndexSettings.add_excludes(body.paths))


@router.delete("/index/excludes")
def remove_exclude(path: str):
    return respond(lambda: IndexSettings.remove_exclude(path))


@router.put("/index/exclude-extensions")
def exclude_extensions(body: ExtensionsBody):
    return respond(lambda: IndexSettings.set_exclude_extensions(body.extensions))


@router.post("/index/estimate")
def estimate(body: RootsBody):
    return respond(lambda: indexer.estimate(body.roots))


@router.get("/search")
def search_files(
    q: str,
    root: Optional[str] = None,
    scope: str = "everywhere",
    kinds: Optional[str] = None,
    since: Optional[float] = None,
    limit: int = Query(60, le=200),
):
    kind_list = [k for k in (kinds or "").split(",") if k] or None
    return respond(lambda: search.search(q, root=root, scope=scope, kinds=kind_list, since=since, limit=limit))


@router.get("/search/file")
def search_in_file(path: str, q: str):
    """Best passages inside one file (preview highlighting / open at page)."""
    return respond(lambda: search.passages_in_file(path, q))


@router.get("/graph")
def get_graph():
    return respond(graph.get_snapshot)


@router.post("/graph/build")
def build_graph():
    return respond(graph.build_async)


@router.get("/graph/status")
def graph_status():
    return respond(graph.status)
