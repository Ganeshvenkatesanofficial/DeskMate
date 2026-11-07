"""api.ai — Model configuration and installs (``/api/fa/ai/*``)."""

from __future__ import annotations

from api.common import AiConfigBody, ModelBody, api_router, respond
from knowledge import embedder
from agent import model_setup
from agent.ai_config import AI_CONFIG

router = api_router("ai")


@router.get("/ai/status")
def status():
    """Embedder, Ollama, model catalog with pull progress, machine specs and the chat-model config."""
    return respond(model_setup.ai_status)


@router.get("/ai/config")
def get_config():
    return respond(AI_CONFIG.snapshot)


@router.put("/ai/config")
def update_config(body: AiConfigBody):
    """Choose the chat model (an Ollama id or the Gemini choice) and/or set the Gemini key ('' removes it)."""
    return respond(lambda: AI_CONFIG.update(chat_model=body.chatModel, gemini_api_key=body.geminiApiKey))


@router.post("/ai/embedder/download")
def download_embedder():
    return respond(embedder.start_download)


@router.post("/ai/ollama/pull")
def pull_model(body: ModelBody):
    return respond(lambda: model_setup.pull_model(body.model))
