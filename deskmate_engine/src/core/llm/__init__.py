"""
core.llm — LLM factory and conversation helpers
================================================
Re-exports from sub-modules:
  models       — get_model, get_installed_chat_models, check_local_llm_status
  conversation — build_chat_prompt, should_contextualize
"""

from __future__ import annotations

from core.llm.models import (
    LocalLiteLLMModel,
    chat_local_llm,
    check_local_llm_status,
    get_default_model,
    get_installed_chat_models,
    get_model,
)
from core.llm.conversation import (
    build_chat_prompt,
    format_conversation_history,
    should_contextualize,
)

__all__ = [
    # models
    "get_model",
    "get_installed_chat_models",
    "get_default_model",
    "check_local_llm_status",
    "chat_local_llm",
    "LocalLiteLLMModel",
    # conversation
    "build_chat_prompt",
    "format_conversation_history",
    "should_contextualize",
]
