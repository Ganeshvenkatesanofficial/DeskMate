"""
core.conversation — Multi-turn prompt construction
==================================================
Turns a chat's recent history plus the new request into one agent prompt, and
rewrites short follow-ups ("in Downloads?", "show me all") into standalone
requests with a fast model so tool calls get the right scope.
"""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

import litellm

from core.config import DEFAULT_GEMINI_MODEL
from core.llm.models import chat_local_llm, get_default_model, get_installed_chat_models

logger = logging.getLogger("deskmate.conversation")


def should_contextualize(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
) -> bool:
    """
    Determines if user input is an incomplete follow-up fragment or answer to a question
    that requires contextualization against previous conversation turns.
    """
    clean = user_input.strip()
    if not clean:
        return False

    tokens = clean.lower().split()
    if not tokens:
        return False
    lower = clean.lower()

    # 1. If previous assistant turn ended with a question mark or asked a question, user is responding to it
    if history:
        for item in reversed(history):
            if str(item.get("role", "")).strip().lower() == "assistant":
                prev_text = str(item.get("content", "")).strip()
                if prev_text:
                    # If assistant asked for clarification, choices, or questions
                    if "?" in prev_text or any(q in prev_text.lower() for q in ["which", "let me know", "would you like", "or", "say so"]):
                        return True
                    # Check if user query mentions numbers or counts present in assistant's previous message
                    # e.g., assistant found 43 files, user says "show location 43 places" or "43"
                    for tok in tokens:
                        if tok.isdigit() and tok in prev_text:
                            return True
                break

    # 2. Short phrases starting with follow-up words: "just", "only", "show", "give", "list", "where", "in", "at", etc.
    fragment_starters = (
        "in ", "at ", "on ", "under ", "from ", "inside ",
        "and ", "also ", "or ", "but ", "what about ", "how about ",
        "what of ", "why ", "where ", "which one", "again",
        "just ", "only ", "show ", "list ", "give ", "tell ", "display "
    )
    if len(tokens) <= 7 and any(lower.startswith(starter) for starter in fragment_starters):
        return True

    # 3. Contains anaphoric pronoun or ordinal referring to previous context without explicit target
    anaphora_words = {
        "it", "that", "this", "them", "those", "there", "its", "former", "latter",
        "all", "both", "one", "first", "second", "third", "last", "places", "locations"
    }
    if any(token in anaphora_words for token in tokens) and len(tokens) <= 8:
        return True

    return False


def resolve_contextual_query(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """
    Dynamically rewrite follow-up queries (e.g. 'in chennai', 'how about tomorrow?')
    into self-contained standalone queries using a fast LLM.
    If the query is already standalone or no history exists, returns user_input unchanged.
    Safe with zero-crash fallbacks.
    """
    clean_input = user_input.strip()
    if not clean_input:
        return ""

    if not history:
        return clean_input

    # Fast-path: Check if the query is already self-contained
    if not should_contextualize(clean_input, history):
        return clean_input

    # 1. Extract the immediate preceding turn (last user message & last assistant message)
    last_user = ""
    last_assistant = ""
    for item in reversed(history):
        role = str(item.get("role", "")).strip().lower()
        content = str(item.get("content", "")).strip()
        if not content:
            continue
        if role == "assistant" and not last_assistant:
            # Keep concise to minimize rewriter prompt length
            last_assistant = content[:250].replace("\n", " ").strip()
        elif role == "user" and not last_user:
            last_user = content[:250].replace("\n", " ").strip()
        if last_user and last_assistant:
            break

    # If there is no previous user turn, nothing to contextualize against
    if not last_user:
        return clean_input

    # 2. Build lean few-shot contextualizer prompt with strict system & user separation
    system_instruction = (
        "You are a query contextualizer. Merge a follow-up with its prior turn into one standalone query.\n\n"
        "Rules:\n"
        "1. If the follow-up is already self-contained or introduces a new topic/scope, return it EXACTLY as-is.\n"
        "2. Only fill in missing context for incomplete fragments ('in backend?', 'how about tomorrow?', 'show me all').\n"
        "3. Preserve the user's explicit scope — never override 'in lap', 'in Desktop', 'in Downloads' with a prior directory.\n"
        "4. Say 'across your laptop' instead of 'current directory' when referencing '~' or home.\n"
        "5. Output ONLY the standalone query. No explanation, no filler.\n\n"
        "Examples:\n"
        "  User: Show details of requirements.txt | Assistant: Found 43 files. | Follow-up: show me all\n"
        "  → List all requirements.txt files found across your laptop\n"
        "  User: Show details of requirements.txt | Follow-up: in backend directory check?\n"
        "  → Check and show details of requirements files in the backend directory\n"
        "  User: Weather in London? | Follow-up: in New York?\n"
        "  → What is the weather in New York?\n"
        "  User: Find PDF files > 10MB | Follow-up: in Downloads\n"
        "  → Find PDF files larger than 10MB in Downloads\n"
        "  User: Check files in verdex-backend | Follow-up: can you find my resume in lap\n"
        "  → can you find my resume in lap\n"
    )
    user_turn_content = (
        f"Previous User: {last_user}\n"
        f"Previous Assistant: {last_assistant or 'None'}\n"
        f"Follow-up Query: {clean_input}\n\n"
        "Standalone Query:"
    )

    rewritten: Optional[str] = None

    # Step A: Try fast local Ollama model via chat API
    try:
        installed = get_installed_chat_models()
        chosen_local: Optional[str] = None
        
        # Priority 1: Known ultra-fast models (1B - 3B)
        for cand in ["qwen2.5-coder:1.5b", "qwen2.5:1.5b", "llama3.2:1b", "llama3.2:3b", "phi3:mini"]:
            if cand in installed:
                chosen_local = cand
                break
        
        # Priority 2: Any model with small size marker
        if not chosen_local:
            for m in installed:
                ml = m.lower()
                if any(tag in ml for tag in [":1b", ":1.5b", ":2b", ":3b"]):
                    chosen_local = m
                    break
        
        # Priority 3: Fall back to model_id if local, or default model
        if not chosen_local:
            if model_id and model_id in installed:
                chosen_local = model_id
            else:
                chosen_local = get_default_model()

        if chosen_local:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_turn_content},
            ]
            resp = chat_local_llm(
                messages,
                model=chosen_local,
                temperature=0.0,
            )
            raw = resp.get("content", "").strip()
            if raw:
                rewritten = raw
    except Exception as exc:
        logger.debug(f"Local query rewriter attempt skipped/failed: {exc}")

    # Step B: If local LLM was not available or failed, try Gemini Flash if API key provided
    if not rewritten and api_key and api_key.strip():
        try:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_turn_content},
            ]
            resp = litellm.completion(
                model=DEFAULT_GEMINI_MODEL,
                api_key=api_key.strip(),
                messages=messages,
                max_tokens=48,
                temperature=0.0,
                timeout=2.0,
            )
            raw_text = resp.choices[0].message.content or ""
            if raw_text.strip():
                rewritten = raw_text.strip()
        except Exception as exc:
            logger.debug(f"Cloud query rewriter attempt skipped/failed: {exc}")

    # Step C: Post-process rewritten text
    if rewritten:
        cleaned = rewritten
        for prefix in ["Standalone Query:", "Rewritten Query:", "Query:", "Standalone request:", "Output:"]:
            if cleaned.lower().startswith(prefix.lower()):
                cleaned = cleaned[len(prefix):].strip()
        cleaned = cleaned.strip('`"\'').strip()

        # Reject conversational artifacts (e.g., "Sure, please provide...", "As an AI...", "Here is...")
        conversational_reject_patterns = [
            "sure", "certainly", "please provide", "as an ai", "i would be happy",
            "i can help", "feel free", "how can i help", "what would you like",
            "could you please", "rewritten into", "i am an ai", "sorry"
        ]
        cleaned_lower = cleaned.lower()
        if any(cleaned_lower.startswith(pat) or pat in cleaned_lower for pat in conversational_reject_patterns):
            logger.warning(f"Discarding conversational rewriter artifact: '{cleaned}', keeping original query: '{clean_input}'")
            return clean_input

        # Sanity check: must be a reasonable length sentence (not a huge hallucination)
        if cleaned and len(cleaned.split("\n")) <= 2 and len(cleaned) < 300:
            if cleaned.lower() != clean_input.lower():
                logger.info(f"Contextualized Query: '{clean_input}' -> '{cleaned}'")
            return cleaned

    # Fallback: Return original query unchanged
    return clean_input


def format_conversation_history(
    history: Optional[List[Dict[str, str]]],
    max_turns: int = 6,
) -> str:
    """Format recent conversation turns into a clean context block."""
    if not history:
        return ""

    valid_items = [
        item for item in history
        if isinstance(item, dict) and str(item.get("content", "")).strip()
    ]
    if not valid_items:
        return ""

    # Keep up to max_turns most recent messages
    recent_items = valid_items[-max_turns:]
    lines = []
    for item in recent_items:
        role = str(item.get("role", "")).strip().lower()
        role_label = "User" if role == "user" else "Assistant"
        content = str(item.get("content", "")).strip()

        # Truncate overly long assistant messages to keep prompt focused and within context budget
        if role != "user" and len(content) > 500:
            content = content[:350].strip() + "\n... [truncated] ...\n" + content[-120:].strip()

        lines.append(f"{role_label}: {content}")

    return "\n".join(lines)


def build_chat_prompt(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """
    Build a context-aware prompt combining conversation history and current user request.
    Guarantees that the agent understands follow-up answers, questions it asked, and references
    to previous findings without losing context across turns.
    """
    clean_input = user_input.strip()
    if not clean_input:
        return ""

    if not history:
        return clean_input

    history_text = format_conversation_history(history, max_turns=6)
    if not history_text:
        return clean_input

    # Also attempt dynamic query contextualization to provide a helpful target hint
    query_hint = ""
    try:
        resolved = resolve_contextual_query(
            user_input=clean_input,
            history=history,
            api_key=api_key,
            model_id=model_id,
        )
        if resolved and resolved.strip().lower() != clean_input.lower():
            query_hint = f"\n[Context Clarification: The user is referring to: {resolved.strip()}]\n"
    except Exception as e:
        logger.debug(f"Telemetry contextual query resolution failed: {e}")

    return (
        f"### CONVERSATION HISTORY (Previous turns in this chat session):\n"
        f"{history_text}\n"
        f"{query_hint}\n"
        f"### CURRENT USER REQUEST:\n"
        f"{clean_input}\n\n"
        f"INSTRUCTION: Fulfill the CURRENT USER REQUEST, using the CONVERSATION HISTORY above to resolve any references to files, questions you asked, or counts/locations mentioned earlier. "
        f"Execute any necessary tools to fulfill the user's request."
    )
