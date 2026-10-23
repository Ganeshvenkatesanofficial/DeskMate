"""
services.meeting_intelligence.summarizer — Multimodal Meeting Reasoner
======================================================================
Fuses screen interaction logs, key screenshot OCR data, and Voxtral 4B
diarized audio transcripts into an executive report.

Supported Engines:
  - Google Gemini 2.5 Flash (Default Multimodal Vision Cloud)
  - Local Ollama (100% Offline Fallback)
"""

from __future__ import annotations

import base64
import io
import json
import logging
import re
from pathlib import Path
from typing import Any
import requests
import cv2
from settings import OLLAMA_BASE_URL, GEMINI_API_KEY, DEFAULT_GEMINI_MODEL, OLLAMA_VISION_MODEL, USER_DATA_DIR

logger = logging.getLogger("deskmate.meeting_summarizer")

_GENERIC_TITLE_PREFIXES = ("summary", "executive", "meeting summary", "meeting notes", "meeting minutes")


def extract_meeting_title(summary_md: str) -> str:
    """The topic title the summarizer writes as the first `# Heading`, or '' if missing/generic."""
    for line in (summary_md or "").splitlines():
        stripped = line.strip()
        if not stripped.startswith("# "):
            continue
        title = re.sub(r"[*_`]", "", stripped[2:]).strip()
        if title and not title.lower().startswith(_GENERIC_TITLE_PREFIXES):
            return title
    return ""

GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"
# Tried in order when the configured model has been retired (HTTP 404).
GEMINI_FALLBACK_MODELS = ("gemini-2.5-flash", "gemini-flash-latest")
MAX_OLLAMA_CANDIDATES = 2
GEMINI_AUDIO_CHUNK_SECONDS = 240
# Transcript segments sent per translation request (keeps prompts small for local models).
TRANSLATE_BATCH_SIZE = 40


class NothingToSummarizeError(RuntimeError):
    """Raised when a session has neither screen steps nor usable speech."""


class SummarizationUnavailableError(RuntimeError):
    """Raised when no AI engine (Gemini or Ollama) could produce a summary."""


class MeetingSummarizer:
    """Production multimodal meeting summarizer for DeskMate."""

    def __init__(
        self,
        gemini_api_key: str | None = None,
        gemini_model: str = DEFAULT_GEMINI_MODEL.split("/")[-1],
        ollama_model: str = OLLAMA_VISION_MODEL,
    ):
        self.gemini_api_key = gemini_api_key or GEMINI_API_KEY
        self.gemini_model = gemini_model
        self.ollama_model = ollama_model

    INTERNAL_NOISE_KEYWORDS = {
        "deskmate",
        "meeting scribe",
        "start meeting",
        "end meeting",
        "stop meeting",
        "recording dashboard",
        "telemetry",
        "deskmate live",
        "deskmate ai",
        "modal_window",
        "modal",
        "runner",
        "flutter",
        "electron",
        "deskmate_app",
        "save to drive",
        "download pdf",
        "email pdf",
        "email meeting summary",
        "sync to deskmate",
        "app switcher",
        "mission control",
        "dock",
        "taskbar",
        "window switch",
        "switching window",
        "switch to",
    }

    def _is_noise_step(self, step: dict[str, Any]) -> bool:
        summary = (step.get("summary") or "").lower()
        actions = step.get("actions", [])
        combined = summary + " " + " ".join([
            (a.get("target") or a.get("description") or a.get("event") or "").lower()
            for a in actions
        ])
        for kw in self.INTERNAL_NOISE_KEYWORDS:
            if kw in combined:
                return True
        return False

    def summarize_meeting(
        self,
        steps: list[dict[str, Any]],
        transcript_data: dict[str, Any] | None = None,
        custom_fields: list[dict[str, str]] | None = None,
        gemini_api_key: str | None = None,
    ) -> tuple[str, list[str], dict[str, Any], dict[str, Any]]:
        """
        Synthesize session into an executive summary report.

        Returns:
            Tuple of:
              - Markdown summary text
              - List of important step IDs (e.g. ['step_1', 'step_4'])
              - Dict of step descriptions mapping step_id -> {title, description}
              - Dict of custom fields analysis
        """
        has_audio = bool(
            transcript_data
            and (transcript_data.get("segments") or transcript_data.get("full_transcript"))
        )
        if not steps and not has_audio:
            raise NothingToSummarizeError(
                "No meeting content was detected to summarize: no speech and no screen activity. "
                "Speak or show content on screen during the meeting. If you did, check Screen Recording and "
                "Microphone permission for DeskMate in System Settings > Privacy & Security."
            )

        # 0. Filter out internal DeskMate tool interactions & transient window switches
        clean_steps = [s for s in steps if not self._is_noise_step(s)]
        effective_steps = clean_steps if clean_steps else steps

        # 1. Build visual timeline text
        timeline_blocks = []
        for s in effective_steps:
            s_id = s.get("step_id", "?")
            s_summary = s.get("summary", "Screen interaction")
            actions = s.get("actions", [])
            s_ts = s.get("timestamp") or (actions[0].get("timestamp") if actions else "00:00")
            action_lines = []
            for a in actions:
                a_ts = a.get("timestamp", s_ts)
                a_event = a.get("event") or a.get("type", "action")
                a_target = a.get("target") or a.get("description", "")
                desc = f"{a_event}: {a_target}" if a_target else a_event
                action_lines.append(f"    - [{a_ts}] {desc}")
            action_text = "\n".join(action_lines) if action_lines else "    - (UI interaction)"
            summary_clean = s_summary
            prefix = f"Step {s_id}: "
            if summary_clean.startswith(prefix):
                summary_clean = summary_clean[len(prefix):]
            timeline_blocks.append(f"Step {s_id} [{s_ts}]: {summary_clean}\n{action_text}")
        visual_timeline = (
            "\n\n".join(timeline_blocks)
            if timeline_blocks
            else "No screen changes were captured. Build the report from the audio transcript only, and leave ===IMPORTANT_STEPS=== and ===STEP_DESCRIPTIONS=== empty."
        )

        # 2. Format Voxtral transcript with speaker diarization
        audio_section = self._format_transcript(transcript_data)

        # 3. Build structured prompt
        prompt = self._build_prompt(visual_timeline, audio_section, len(effective_steps), custom_fields, has_audio=has_audio)

        # 4. Prepare multimodal parts with Base64 screenshot images
        parts = [{"text": prompt}]
        for step in effective_steps:
            s_id = step.get("step_id", "?")
            img_path = step.get("screenshot_path", "")
            if not img_path:
                actions = step.get("actions", [])
                img_path = next((a.get("asset_path") for a in actions if a.get("asset_path")), "")

            full_img_path = None
            if img_path:
                cand_p = Path(img_path)
                search_candidates = [
                    cand_p,
                    cand_p.resolve(),
                    Path.cwd() / img_path,
                    USER_DATA_DIR / img_path,
                ]
                for cand in search_candidates:
                    if cand.exists() and cand.is_file():
                        full_img_path = str(cand)
                        break

            if full_img_path:
                try:
                    img = cv2.imread(full_img_path)
                    if img is not None:
                        h, w = img.shape[:2]
                        if max(h, w) > 768:
                            scale = 768.0 / max(h, w)
                            img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
                        _, buf = cv2.imencode(".jpg", img, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
                        b64 = base64.b64encode(buf).decode("utf-8")
                        parts.append({"text": f"\n\n[SCREENSHOT FOR STEP {s_id}]"})
                        parts.append({"inlineData": {"mimeType": "image/jpeg", "data": b64}})
                except Exception as e:
                    logger.debug(f"Failed to attach screenshot for {s_id}: {e}")

        # 5. Query Gemini (or fall back to local Ollama)
        raw_response = self._query_llm(parts, prompt, gemini_api_key or self.gemini_api_key)

        # 6. Parse structured blocks
        return self._parse_structured_response(raw_response)

    def _format_transcript(self, transcript_data: dict[str, Any] | None) -> str:
        if not transcript_data:
            return "AUDIO STATUS: No audio recorded or transcription inactive. Generate summary from visual events."

        segments = transcript_data.get("segments", [])
        if not segments:
            full = transcript_data.get("full_transcript", "")
            return f"AUDIO TRANSCRIPT:\n{full}" if full else "AUDIO STATUS: No speech detected."

        lines = ["--- Voxtral Diarized Transcript ---"]
        for seg in segments:
            start = seg.get("start", 0.0)
            end = seg.get("end", 0.0)
            speaker = seg.get("speaker", "Speaker")
            text = seg.get("text", "").strip()
            if text:
                start_m, start_s = int(start // 60), int(start % 60)
                end_m, end_s = int(end // 60), int(end % 60)
                lines.append(f"[{start_m:02d}:{start_s:02d} -> {end_m:02d}:{end_s:02d}] {speaker}: {text}")

        return "\n".join(lines)

    def _build_prompt(
        self,
        visual_timeline: str,
        audio_section: str,
        step_count: int,
        custom_fields: list[dict[str, str]] | None,
        *,
        has_audio: bool = False,
    ) -> str:
        transcript_section = (
            "### Spoken Transcript Highlights\n"
            "Key spoken decisions, directions, answers, and verbal agreements extracted from the transcript.\n"
            if has_audio else ""
        )

        custom_instructions = ""
        custom_delimiters = ""
        if custom_fields:
            cf_list = []
            for cf in custom_fields:
                n = cf.get("name", "")
                inst = cf.get("instruction", "")
                cf_list.append(f"- Topic: \"{n}\"\n  Instructions: {inst}")
            custom_instructions = (
                "\n\n## SOURCE 3: User's Requested Custom Analysis Topics\n"
                + "\n".join(cf_list)
                + "\n\nProvide deep-dive analysis addressing each of the user's custom focus topics."
            )
            custom_delimiters = (
                "\n\n===CUSTOM_FIELDS===\n"
                '{"Topic Name": {"content": "Detailed markdown analysis for this topic...", "relevant_steps": ["step_1"]}}'
            )

        return f"""You are DeskMate's Senior Documentation & Meeting Intelligence Writer.
Your task is to produce a comprehensive, structured meeting intelligence report by cross-referencing visual interaction timeline, screen image OCR content, and audio transcript.

## SOURCE 1: Visual Event Log
{visual_timeline}

## SOURCE 2: Voxtral Audio Transcript
{audio_section}
{custom_instructions}

---
## GROUNDING RULE (MANDATORY):
You MUST derive every claim, name, deadline, decision, and action item SOLELY from the provided visual timeline, screenshot OCR text, and audio transcript above. If a piece of information is not present in any source, DO NOT infer, assume, or fabricate it. Write "Not discussed" or omit the item entirely rather than guessing.

---
## MULTILINGUAL & TRANSLATION REQUIREMENT (MANDATORY):
1. The spoken meeting dialogue, transcript, or on-screen text may be in Tamil, Tanglish (Tamil-English blend/code-switching), Hindi, or other regional languages.
2. Regardless of the spoken language or mix of languages used in the meeting, you MUST synthesize, translate, and express the ENTIRE report in CLEAN, FLUENT, GRAMMATICALLY ACCURATE, PROFESSIONAL ENGLISH.
3. Every section—Executive Overview, Detailed Actions Timeline, Decisions & Outcomes, Technical Parameters, Action Items, Step Titles, and Step Descriptions—MUST be written strictly in professional English.
4. DO NOT output Tanglish, phonetic transliterations (e.g. "pannalam", "mudichitom"), or untranslated regional phrases. Accurately translate their core meaning into polished, professional business English.

---
## STRICT EXCLUSION & FILTERING RULES:
1. NEVER describe, mention, or include actions inside the DeskMate application itself (e.g. clicking 'Start Meeting Scribe', 'End Meeting', opening DeskMate, or viewing recording metrics). These are host tool operations, NOT meeting content.
2. NEVER describe transient window switching, Alt-Tab/Cmd-Tab, Dock clicks, or minimizing/maximizing windows to switch into or out of the meeting.
3. FOCUS EXCLUSIVELY on the substantive content presented: slides, web pages, software tools, code, diagrams, and spoken discussion.
4. In ===IMPORTANT_STEPS=== and ===STEP_DESCRIPTIONS===, NEVER include internal DeskMate steps or window-switch moments.
5. **STRICT VISUAL & AUDIO SYNCHRONIZATION**: In ===STEP_DESCRIPTIONS===, each step's "description" and "audio_transcript" MUST strictly correspond to what was on screen and what was spoken at that exact moment. NEVER attach dialogue spoken at other times in the meeting to an unrelated screenshot. If no speech occurred at that moment, output `"audio_transcript": "No speech during this moment"`.

---
## ACTION ITEM & DECISION RULES (STRICT NON-HALLUCINATION POLICY):
1. **HIGH-IMPACT DELIVERABLES ONLY**: You MUST only tag an item with `**[ACTION ITEM]**` or `**[HIGH PRIORITY]**` if it represents a CONCRETE, EXPLICIT, SIGNIFICANT TASK, ASSIGNMENT, OR MILESTONE explicitly agreed upon by participants.
2. **ZERO CONVERSATIONAL FILLER**: NEVER generate action items from passive chatter, greetings, rhetorical questions, routine software navigation, or casual comments (e.g. DO NOT create items like "Check microphone", "Click on browser", "Review presentation", "Look at screen").
3. **DO NOT FABRICATE ACTION ITEMS**: If participants did NOT explicitly designate follow-up tasks or future commitments during the session, DO NOT invent them. In that case, write:
   `- No explicit follow-up action items were assigned during this session.`
4. **FORMAT OF TRUE ACTION ITEMS**:
   Every genuine action item MUST be concise and state:
   `- **[ACTION ITEM]** [Assignee / Team if stated]: [Specific deliverable] (Due/Next Step: [Milestone if stated])`
   `- **[HIGH PRIORITY]** [Critical blocker, security patch, or urgent deadline explicitly flagged as urgent]`
   `- **[IMPORTANT]** [Key architectural, business, or operational decision finalized]`

---
## INSTRUCTIONS:
1. TITLE REQUIREMENT: Start the ===SUMMARY=== block with a single top-level `# [Specific Meeting Title]` naming the substantive topic or project discussed (e.g. `# API Gateway Architecture & Throttle Sync` or `# Q3 Product Roadmap Alignment`). DO NOT use generic phrases like "Meeting Summary".
STRUCTURE YOUR OUTPUT WITH THESE EXACT DELIMITERS:

===SUMMARY===

# [Specific 3-7 Word Meeting Title Based on Core Topic]

### Executive Overview
Concise 3-5 sentence summary of the meeting's core purpose, platforms used, and primary outcome.

### Detailed Actions Timeline
Chronological narrative combining visual on-screen actions, screenshot text/OCR details, and spoken statements. Explain the purpose of each significant action.

{transcript_section}### Decisions & Outcomes
- Accomplishments finalized.
- Items designated for follow-up (use **[ACTION ITEM]** or **[HIGH PRIORITY]** strictly according to the rules above).

### Technical & Domain Parameters
Relevant code commands, configuration flags, client requests, or operational parameters.

===IMPORTANT_STEPS===
["step_1", "step_3"]

===STEP_DESCRIPTIONS===
{{"step_1": {{"title": "Descriptive Action Name", "description": "2-3 sentences explaining visual screen actions, parameters, or outcomes.", "audio_transcript": "Key spoken dialogue or discussion from the audio transcript during this clip moment (or 'No speech during this moment' if silent)."}}}}
{custom_delimiters}
"""

    def _resolve_available_ollama_model(self) -> str:
        """Resolve an active Ollama model. If configured model is missing or unsupported, fallback to any available installed model."""
        try:
            r = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=3)
            if r.status_code == 200:
                models_data = r.json().get("models", [])
                available = [m.get("name") for m in models_data if m.get("name")]
                # Filter out embedding models and models with known runner crash architectures like 'mllama'
                compatible = []
                for m in models_data:
                    name = m.get("name", "")
                    family = (m.get("details") or {}).get("family", "").lower()
                    if "embed" not in name.lower() and family != "mllama":
                        compatible.append(name)

                # Prefer user model if compatible
                for m in compatible:
                    if self.ollama_model and (self.ollama_model in m or m in self.ollama_model):
                        return m

                if compatible:
                    logger.info(f"Using compatible Ollama model: {compatible[0]}")
                    return compatible[0]

                # Fallback to any non-embedding model
                llm_candidates = [m for m in available if "embed" not in m.lower()]
                if llm_candidates:
                    return llm_candidates[0]
        except Exception as e:
            logger.debug(f"Failed to query Ollama tags: {e}")
        return self.ollama_model

    def _gemini_generate(
        self, parts: list[dict[str, Any]], api_key: str, timeout: int = 120, temperature: float = 0.2
    ) -> str | None:
        """Call Gemini generateContent, moving to newer models when the configured one is retired."""
        models: list[str] = []
        for m in (self.gemini_model, *GEMINI_FALLBACK_MODELS):
            if m and m not in models:
                models.append(m)

        headers = {"x-goog-api-key": api_key, "Content-Type": "application/json"}
        body = {
            "contents": [{"parts": parts}],
            "generationConfig": {"temperature": temperature, "maxOutputTokens": 16384},
        }
        for model in models:
            try:
                resp = requests.post(
                    f"{GEMINI_API_BASE}/{model}:generateContent",
                    json=body,
                    headers=headers,
                    timeout=timeout,
                )
                if resp.status_code == 404:
                    logger.warning(f"Gemini model '{model}' is unavailable (404). Trying next model.")
                    continue
                resp.raise_for_status()
                candidates = resp.json().get("candidates", [])
                if candidates:
                    content_parts = candidates[0].get("content", {}).get("parts", [])
                    text = "".join(p.get("text", "") for p in content_parts)
                    if text.strip():
                        if model != self.gemini_model:
                            self.gemini_model = model
                        return text
                return None
            except Exception as e:
                logger.warning(f"Gemini request with model '{model}' failed: {e}")
                return None
        return None

    def transcribe_audio_with_gemini(self, audio_path: str, api_key: str) -> dict[str, Any] | None:
        """Transcribe a 16 kHz WAV with Gemini, in short chunks to stay under the inline request limit."""
        try:
            import soundfile as sf

            data, sr = sf.read(audio_path, dtype="int16")
            if data.ndim > 1:
                data = data.mean(axis=1).astype("int16")
            if len(data) == 0 or not sr:
                return None

            chunk_len = GEMINI_AUDIO_CHUNK_SECONDS * sr
            segments: list[dict[str, Any]] = []
            failed_chunks = 0
            for offset in range(0, len(data), chunk_len):
                chunk = data[offset : offset + chunk_len]
                if not chunk.any():
                    continue
                buf = io.BytesIO()
                sf.write(buf, chunk, sr, format="WAV", subtype="PCM_16")
                offset_s = offset / float(sr)
                parts = [
                    {
                        "text": (
                            "Transcribe this meeting audio and translate it into clear English. Speech may be "
                            "Tamil, Tanglish, Hindi or any other language. Identify different speakers as "
                            '"Speaker 1", "Speaker 2", etc. Return ONLY a JSON array: '
                            '[{"start": seconds, "end": seconds, "speaker": "Speaker 1", '
                            '"text": "English translation", "original": "exact words as spoken"}]. '
                            'If speech is already English, "original" equals "text". '
                            "Times are seconds from the start of this clip. Return [] if there is no speech."
                        )
                    },
                    {"inlineData": {"mimeType": "audio/wav", "data": base64.b64encode(buf.getvalue()).decode("utf-8")}},
                ]
                raw = self._gemini_generate(parts, api_key, timeout=180, temperature=0.0)
                if not raw:
                    # Keep the chunks that already worked; one bad chunk must not lose them.
                    failed_chunks += 1
                    logger.warning(f"Gemini returned nothing for audio chunk at {offset_s:.0f}s; skipping it.")
                    continue
                try:
                    items = json.loads(self._strip_code_fences(raw))
                except Exception:
                    items = [{"start": 0.0, "end": len(chunk) / float(sr), "speaker": "Speaker 1", "text": raw.strip()}]
                for it in items if isinstance(items, list) else []:
                    if not isinstance(it, dict):
                        continue
                    text = str(it.get("text", "")).strip()
                    if not text:
                        continue
                    try:
                        start = float(it.get("start", 0.0) or 0.0)
                        end = float(it.get("end", 0.0) or 0.0)
                    except (TypeError, ValueError):
                        start, end = 0.0, len(chunk) / float(sr)
                    segment = {
                        "start": round(offset_s + start, 2),
                        "end": round(offset_s + end, 2),
                        "speaker": str(it.get("speaker") or "Speaker 1"),
                        "text": text,
                    }
                    original = str(it.get("original") or "").strip()
                    if original and original != text:
                        segment["original_text"] = original
                    segments.append(segment)

            if not segments and failed_chunks:
                return None
            return {
                "full_transcript": " ".join(s["text"] for s in segments),
                "segments": segments,
                "duration_seconds": round(len(data) / float(sr), 2),
                "language": "en",
                "engine": f"gemini:{self.gemini_model}",
                "translated": True,
            }
        except Exception as e:
            logger.warning(f"Gemini audio transcription failed: {e}")
            return None

    def translate_transcript_to_english(
        self, transcript: dict[str, Any], api_key: str | None = None
    ) -> dict[str, Any]:
        """Translate each transcript segment into English (any source language), keeping the
        spoken words in `original_text`. Segments that can't be translated stay as spoken."""
        segments = transcript.get("segments") or []
        if not segments and str(transcript.get("full_transcript") or "").strip():
            segments = [{
                "start": 0.0,
                "end": float(transcript.get("duration_seconds") or 0.0),
                "speaker": "Speaker 1",
                "text": str(transcript["full_transcript"]).strip(),
            }]
            transcript["segments"] = segments
        if transcript.get("translated") or not segments:
            return transcript

        translated_count = 0
        for start in range(0, len(segments), TRANSLATE_BATCH_SIZE):
            batch = segments[start : start + TRANSLATE_BATCH_SIZE]
            lines = [str(seg.get("text") or "") for seg in batch]
            prompt = (
                "Translate each line of this meeting transcript into clear, natural English. "
                "Lines may be Tamil, Tanglish (Tamil written in English letters), Hindi or any other "
                "language, or a mix. Keep names, numbers and technical terms. If a line is already "
                "English, return it unchanged. Return ONLY a JSON array of strings with exactly "
                f"{len(lines)} items, in the same order.\n\n" + json.dumps(lines, ensure_ascii=False)
            )
            try:
                raw = self._query_llm([{"text": prompt}], prompt, api_key)
                english = json.loads(self._strip_code_fences(raw))
            except Exception as e:
                logger.warning(f"Transcript translation failed for lines {start}-{start + len(batch)}: {e}")
                continue
            if not isinstance(english, list) or len(english) != len(batch):
                logger.warning("Transcript translation returned the wrong number of lines; keeping originals.")
                continue
            for seg, spoken, eng in zip(batch, lines, english):
                eng = str(eng or "").strip()
                if eng and eng != spoken:
                    seg["original_text"] = spoken
                    seg["text"] = eng
                    translated_count += 1

        transcript["full_transcript"] = " ".join(str(seg.get("text") or "") for seg in segments)
        transcript["translated"] = True
        transcript["language"] = "en"
        logger.info(f"Translated {translated_count}/{len(segments)} transcript segments to English.")
        return transcript

    def _query_llm(self, parts: list[dict[str, Any]], plain_prompt: str, api_key: str | None = None) -> str:
        """Query Gemini via REST, falling back to local Ollama."""
        # 1. Gemini REST
        if api_key:
            text = self._gemini_generate(parts, api_key)
            if text:
                return text
            logger.warning("Gemini did not return a summary. Falling back to local Ollama.")

        # 2. Local Ollama fallback
        candidates: list[str] = []
        preferred = self._resolve_available_ollama_model()
        if preferred:
            candidates.append(preferred)
        try:
            r = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=3)
            if r.status_code == 200:
                available = [m.get("name") for m in r.json().get("models", []) if m.get("name")]
                for m in available:
                    if "embed" not in m.lower() and m not in candidates:
                        candidates.append(m)
        except Exception:
            pass

        for active_model in candidates[:MAX_OLLAMA_CANDIDATES]:
            try:
                res = requests.post(
                    f"{OLLAMA_BASE_URL}/api/generate",
                    json={
                        "model": active_model,
                        "prompt": plain_prompt,
                        "stream": False,
                        "options": {"num_ctx": 8192},
                    },
                    timeout=180,
                )
                if res.status_code == 200:
                    text_resp = res.json().get("response", "")
                    if text_resp and text_resp.strip():
                        logger.info(f"Ollama successfully generated summary using model '{active_model}'")
                        return text_resp
                else:
                    logger.warning(
                        f"Ollama model '{active_model}' returned {res.status_code}: {res.text}. Trying next candidate model..."
                    )
            except Exception as oe:
                logger.warning(f"Local Ollama generation error with model '{active_model}': {oe}. Trying next candidate...")

        logger.error("All summarization engines failed (Gemini and Ollama).")
        raise SummarizationUnavailableError(
            "No AI engine could write the report. Start Ollama with a chat model, or add a valid Gemini API key "
            "in Settings, then press Retry summary. Your recording is saved."
        )

    @staticmethod
    def _strip_code_fences(text: str) -> str:
        return re.sub(r"```(?:json)?\s*(.*?)\s*```", r"\1", text.strip(), flags=re.DOTALL)

    def _parse_structured_response(
        self, raw: str
    ) -> tuple[str, list[str], dict[str, Any], dict[str, Any]]:
        summary = "Meeting summary could not be extracted."
        important_steps: list[str] = []
        step_descriptions: dict[str, Any] = {}
        custom_fields_dict: dict[str, Any] = {}

        # 1. Extract CUSTOM_FIELDS independently
        if "===CUSTOM_FIELDS===" in raw:
            raw, cf_block = raw.split("===CUSTOM_FIELDS===", 1)
            try:
                custom_fields_dict = json.loads(self._strip_code_fences(cf_block))
            except Exception as cfe:
                logger.debug(f"Failed to parse custom fields JSON: {cfe}")

        # 2. Extract STEP_DESCRIPTIONS independently
        if "===STEP_DESCRIPTIONS===" in raw:
            raw, desc_block = raw.split("===STEP_DESCRIPTIONS===", 1)
            try:
                step_descriptions = json.loads(self._strip_code_fences(desc_block))
            except Exception as e:
                logger.debug(f"Failed to parse step_descriptions JSON: {e}")

        # 3. Extract IMPORTANT_STEPS independently
        if "===IMPORTANT_STEPS===" in raw:
            raw, steps_block = raw.split("===IMPORTANT_STEPS===", 1)
            try:
                important_steps = json.loads(self._strip_code_fences(steps_block))
            except Exception as e:
                logger.debug(f"Failed to parse important_steps JSON: {e}")

        # 4. Extract SUMMARY (everything after the delimiter, now that later blocks are removed)
        if "===SUMMARY===" in raw:
            summary = raw.split("===SUMMARY===", 1)[1].strip()
        elif raw.strip():
            summary = re.sub(r"===[A-Z_]+=== *", "", raw).strip()

        # Post-filter: purge any internal DeskMate or window-switch steps returned by the model
        clean_important = []
        for sid in important_steps:
            sid_str = str(sid).lower()
            desc_meta = step_descriptions.get(sid) or step_descriptions.get(sid_str) or {}
            title = (desc_meta.get("title") if isinstance(desc_meta, dict) else "").lower()
            desc = (desc_meta.get("description") if isinstance(desc_meta, dict) else "").lower()
            if any(kw in f"{title} {desc} {sid_str}" for kw in self.INTERNAL_NOISE_KEYWORDS):
                continue
            clean_important.append(sid)
        important_steps = clean_important

        return summary, important_steps, step_descriptions, custom_fields_dict
