"""
agent.ai_config — The Folder Agent's model configuration
========================================================================
The engine owns which chat model the agent runs on: an Ollama model or Gemini
(with the user's key). The app reads and changes it through
``/api/fa/ai/config``; every agent turn resolves its model here, so there is
one source of truth and the key never travels with chat messages.

The choice may name an Ollama model that is still downloading: it stays the
choice, and turns fall back to an installed model until the pull lands.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Optional

from core.llm.models import get_installed_chat_models
from db import store
from settings import DEFAULT_GEMINI_MODEL

GEMINI_CHOICE = "gemini-2.5-flash"
GEMINI_LABEL = "Gemini 2.5 Flash (Cloud)"
_MODEL_PREF = "chatModel"
_KEY_PREF = "geminiApiKey"

# Prefs that hold secrets: never returned by /prefs, only settable through AiConfig.
SECRET_PREFS = frozenset({_KEY_PREF})


class NoModelError(RuntimeError):
    """No chat model is configured or installed (shown to the user as-is)."""


@dataclass(frozen=True)
class ResolvedModel:
    """What a turn actually runs on."""

    model_id: str  # LiteLLM / Ollama id handed to core.models.get_model
    api_key: Optional[str]  # set only for Gemini
    label: str


class AiConfig:
    """Read, change and resolve the chat model choice."""

    @staticmethod
    def _gemini_key() -> str:
        return (store.get_pref(_KEY_PREF) or os.getenv("GEMINI_API_KEY") or "").strip()

    def snapshot(self, installed: Optional[list[str]] = None) -> dict[str, Any]:
        """The configuration as the app shows it (the key itself is never returned)."""
        installed = get_installed_chat_models() if installed is None else installed
        choice = store.get_pref(_MODEL_PREF)
        has_key = bool(self._gemini_key())
        try:
            effective = self.resolve(installed).label
        except NoModelError:
            effective = None
        return {
            "chatModel": choice,
            "effectiveModel": effective,
            "provider": "gemini" if choice == GEMINI_CHOICE and has_key else "ollama",
            "hasGeminiKey": has_key,
            "geminiChoice": GEMINI_CHOICE,
            "geminiLabel": GEMINI_LABEL,
            "installedModels": installed,
        }

    def update(self, *, chat_model: Optional[str] = None, gemini_api_key: Optional[str] = None) -> dict[str, Any]:
        """Change the model and/or the Gemini key. An empty key removes it."""
        patch: dict[str, Any] = {}
        if gemini_api_key is not None:
            patch[_KEY_PREF] = gemini_api_key.strip() or None
            if not patch[_KEY_PREF] and store.get_pref(_MODEL_PREF) == GEMINI_CHOICE:
                patch[_MODEL_PREF] = None  # Gemini without a key isn't a usable choice
        if chat_model is not None:
            patch[_MODEL_PREF] = chat_model.strip() or None
        if patch:
            store.set_prefs(patch)
        return self.snapshot()

    def resolve(self, installed: Optional[list[str]] = None) -> ResolvedModel:
        """The model this turn runs on, or ``NoModelError`` with what to do about it."""
        choice = store.get_pref(_MODEL_PREF)
        key = self._gemini_key()
        if choice == GEMINI_CHOICE and key:
            return ResolvedModel(DEFAULT_GEMINI_MODEL, key, GEMINI_LABEL)
        installed = get_installed_chat_models() if installed is None else installed
        if choice and choice != GEMINI_CHOICE:
            for name in installed:
                if name == choice or name == f"{choice}:latest" or name.split(":latest")[0] == choice:
                    return ResolvedModel(name, None, name)
        if installed:
            return ResolvedModel(installed[0], None, installed[0])
        if key:
            return ResolvedModel(DEFAULT_GEMINI_MODEL, key, GEMINI_LABEL)
        raise NoModelError(
            "No chat model yet. Open Settings → AI & Models to install one with Ollama or add a Gemini key."
        )


AI_CONFIG = AiConfig()
