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
from typing import Any
import requests
import cv2
from settings import OLLAMA_BASE_URL, GEMINI_API_KEY, DEFAULT_GEMINI_MODEL, OLLAMA_VISION_MODEL
from services.meeting_intelligence.step_utils import (
    HOST_UI_KEYWORDS,
    fallback_step_description,
    find_step,
    humanize_speaker_tags,
    is_host_ui_step,
    order_step_ids,
    readable_step_title,
    spoken_quotes_near,
    step_number,
    step_screenshot_path,
)

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
# The report always shows at least this many key moments when the screen recorded any.
MIN_KEY_MOMENTS = 2
# Evenly spaced moments picked when the model chose too few.
FALLBACK_KEY_MOMENTS = 4
# Whole-quote values models use to mean "nobody spoke" (compared after lowercasing and trimming).
_SILENT_QUOTES = {
    "", "none", "n/a", "na", "silent", "silence", "no speech", "no audio", "no spoken dialogue",
    "no speech during this moment", "no speech at this moment", "no speech during this clip moment",
}
# Prompt-template text a model may echo back instead of a real quote.
_QUOTE_PLACEHOLDERS = ("quote exact spoken words", "key spoken dialogue", "or 'no speech", "clip moment")
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
        clean_steps = [s for s in steps if not is_host_ui_step(s)]
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
            full_img_path = step_screenshot_path(step)
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

        # 6. Parse structured blocks, then make sure every chosen moment has a description and quote
        summary, important_steps, step_descriptions, custom_fields_dict = self._parse_structured_response(
            raw_response, effective_steps=effective_steps
        )
        self._complete_step_descriptions(important_steps, step_descriptions, effective_steps, transcript_data)
        return summary, important_steps, step_descriptions, custom_fields_dict

    @staticmethod
    def _complete_step_descriptions(
        important_steps: list[str],
        step_descriptions: dict[str, Any],
        steps: list[dict[str, Any]],
        transcript_data: dict[str, Any] | None,
    ) -> None:
        """Fill a title, description and spoken quote for every important step the model left blank,
        so the app and the PDF show the same text."""
        for sid in important_steps:
            step = find_step(steps, sid)
            if step is None:
                continue
            key = next((k for k in step_descriptions if step_number(k) == step_number(sid)), sid)
            meta = step_descriptions.get(key)
            if not isinstance(meta, dict):
                meta = {}
                step_descriptions[key] = meta
            if not str(meta.get("title") or "").strip():
                meta["title"] = readable_step_title(str(step.get("summary") or ""))
            if not str(meta.get("description") or "").strip():
                meta["description"] = fallback_step_description(step)
            if not str(meta.get("audio_transcript") or "").strip():
                meta["audio_transcript"] = spoken_quotes_near(transcript_data, step)

    @staticmethod
    def _normalize_speakers_in_segments(segments: list[dict[str, Any]]) -> None:
        """Normalize raw machine tags (e.g. SPEAKER_00, SPEAKER_01) to clean human names or Speaker 1, Speaker 2."""
        speaker_mapping: dict[str, str] = {}
        speaker_counter = 0
        for seg in segments:
            raw_spk = str(seg.get("speaker") or "").strip()
            if not raw_spk:
                raw_spk = "Speaker"

            # Check for machine diarization patterns like SPEAKER_00, SPEAKER_01, speaker_0
            match = re.match(r"^SPEAKER_0*(\d+)$", raw_spk, re.IGNORECASE)
            if match:
                if raw_spk not in speaker_mapping:
                    # 0-indexed to 1-indexed (e.g. SPEAKER_00 -> Speaker 1)
                    idx = int(match.group(1)) + 1
                    speaker_mapping[raw_spk] = f"Speaker {idx}"
                seg["speaker"] = speaker_mapping[raw_spk]
            elif raw_spk.lower() in ("speaker", "unknown", "spk", "user"):
                if raw_spk not in speaker_mapping:
                    speaker_counter += 1
                    speaker_mapping[raw_spk] = f"Speaker {speaker_counter}"
                seg["speaker"] = speaker_mapping[raw_spk]
            else:
                # Keep identified human name (e.g. "Ganesh", "Alex", "Speaker 1")
                speaker_mapping[raw_spk] = raw_spk

    def _format_transcript(self, transcript_data: dict[str, Any] | None) -> str:
        if not transcript_data:
            return "AUDIO STATUS: No audio recorded or transcription inactive. Generate summary from visual events."

        segments = transcript_data.get("segments", [])
        if not segments:
            full = transcript_data.get("full_transcript", "")
            return f"AUDIO TRANSCRIPT:\n{full}" if full else "AUDIO STATUS: No speech detected."

        # Normalize speaker labels across segments
        self._normalize_speakers_in_segments(segments)

        lines = ["--- Voxtral Diarized Transcript ---"]
        for seg in segments:
            start = seg.get("start", 0.0)
            end = seg.get("end", 0.0)
            speaker = seg.get("speaker", "Speaker 1")
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
## DYNAMIC CONTENT & RELEVANCE (MANDATORY):
1. **Dynamic Handling**: Only content genuinely relevant to the actual meeting must be captured and displayed. Absolutely nothing should be hardcoded, assumed, or forcibly included. The system must adapt dynamically to the meeting content.
2. **Adaptive Subheadings**: Adapt sections, subheadings, and topics to match what was actually discussed (e.g. `### Architecture & Infrastructure`, `### Security & Compliance`, `### Sales & GTM Strategy`). Do not include boilerplate or empty sections if they were not discussed.
3. **Strict Authenticity**: Derive all participant statements, decisions, and action items strictly from what was spoken or presented in the meeting.

---
## CONTEXT AWARENESS & EXTERNAL RESEARCH AUGMENTATION (MANDATORY):
1. **Organized, Detailed Steps**: Descriptions and steps must be clearly organized, detailed, and augmented with the available context.
2. **Accurate Context Gap Filling**: When tools, cloud services (e.g. AWS, GCP, Azure), CLI commands, API specifications, database schemas, or business domain concepts are referenced or used without full verbal explanation, use authoritative technical domain knowledge to augment and enrich the description.
3. **MANDATORY DISTINCTION BETWEEN IN-MEETING AND RESEARCHED CONTEXT**:
   - You MUST clearly distinguish between what was directly discussed or performed by participants in the meeting and what is external augmented context.
   - In step descriptions, describe the in-meeting action and operation first, then provide the researched technical context explicitly prefixed with `[Context Reference: ...]` (e.g. `User configured an IAM trust policy specifying the Lambda service principal. [Context Reference: In AWS IAM, trust policies define which external identities or services are permitted to assume a role via the sts:AssumeRole API.]`).
   - In summary sections, clearly mark external researched information with `[Context Reference: ...]` so that readers can distinguish meeting decisions from external technical context.

---
## SPEAKER IDENTIFICATION (MANDATORY):
1. **Identify Names When Available**: Actively cross-reference dialogue cues (e.g. "Hi Ganesh", "This is Alex speaking", "Thanks Priya", "Over to you Sarah") and screen visuals (e.g. video meeting participant names, active user profiles, email/Slack headers, terminal username). Whenever a speaker's actual personal name can be identified, ALWAYS attribute their statements and actions to their real name throughout the entire report (e.g. "Ganesh:", "Alex:").
2. **Standard Fallback for Unnamed Speakers**: If a speaker's personal name is not explicitly mentioned or verifiable, consistently identify them as "Speaker 1", "Speaker 2", "Speaker 3", etc.
3. **NEVER use raw machine tags**: Completely eliminate machine tags like "SPEAKER_00", "SPEAKER_01", or "speaker_0" from your entire output. Replace them with the identified person's name or "Speaker 1", "Speaker 2".

---
## MULTILINGUAL & TRANSLATION REQUIREMENT (MANDATORY):
1. The spoken meeting dialogue, transcript, or on-screen text may be in Tamil, Tanglish (Tamil-English blend/code-switching), Hindi, or other regional languages.
2. Regardless of the spoken language or mix of languages used in the meeting, you MUST synthesize, translate, and express the ENTIRE report in CLEAN, FLUENT, GRAMMATICALLY ACCURATE, PROFESSIONAL ENGLISH.
3. Every section—Executive Overview, Decisions & Outcomes, Technical & Domain Parameters, Action Items, Step Titles, and Step Descriptions—MUST be written strictly in professional English.
4. DO NOT output Tanglish, phonetic transliterations (e.g. "pannalam", "mudichitom"), or untranslated regional phrases. Accurately translate their core meaning into polished, professional business English.

---
## STRICT EXCLUSION & FILTERING RULES:
1. NEVER describe, mention, or include actions inside the DeskMate application itself (e.g. clicking 'Start Meeting Scribe', 'End Meeting', opening DeskMate, or viewing recording metrics). These are host tool operations, NOT meeting content.
2. NEVER describe transient window switching, Alt-Tab/Cmd-Tab, Dock clicks, or minimizing/maximizing windows to switch into or out of the meeting.
3. FOCUS EXCLUSIVELY on the substantive content presented: slides, web pages, software tools, code, diagrams, and spoken discussion.
4. In ===IMPORTANT_STEPS=== and ===STEP_DESCRIPTIONS===, NEVER include internal DeskMate steps or window-switch moments.
5. **STRICT VISUAL & AUDIO SYNCHRONIZATION**: In ===STEP_DESCRIPTIONS===, each step's "description" and "audio_transcript" MUST strictly correspond to what was on screen and what was spoken at that exact moment. NEVER attach dialogue spoken at other times in the meeting to an unrelated screenshot. If no speech occurred at that moment, output `"audio_transcript": ""` (empty string). Do NOT output dummy placeholder text.
6. **NO RAW CLICK TIMELINES**: NEVER generate a "Detailed Actions Timeline" or list granular button clicks, menu bar interactions, or raw event logs in the summary. Screen interactions are represented exclusively through the key visual screenshots in ===IMPORTANT_STEPS=== and ===STEP_DESCRIPTIONS===.
7. **SCREENSHOT VERIFICATION & RELEVANCE**: Only select steps whose screenshot image visibly shows actual meeting content (e.g. AWS console, cloud settings, code, slides, or diagrams). The description MUST accurately describe the visual content visible on that screen. NEVER select a screenshot that shows DeskMate's own recording screen, a blank screen, or an unrelated window.

---
## COMPREHENSIVE ACTION ITEMS & DYNAMIC DOMAIN DETAILS:
1. **CAPTURE ALL HIGH-PRIORITY & ACTION ITEMS**: Never omit critical deliverables, urgent tasks, blockers, or assigned action items mentioned in speech or shown on screen.
   Tag them clearly:
   - `- **[HIGH PRIORITY]** [Assignee / Team if stated]: [Critical task, blocker, security concern, or urgent deadline]`
   - `- **[ACTION ITEM]** [Assignee / Team if stated]: [Concrete deliverable, next step, or follow-up commitment]`
   - `- **[IMPORTANT]** [Key architectural, business, or operational decision finalized]`
2. **DYNAMIC DOMAIN & TECHNICAL SPECIFICS**:
   Under `### Technical & Domain Parameters` (and additional dynamic subheadings as needed, e.g. `### Architecture & Infrastructure`, `### Security & Permissions`, `### Database & Schema Configurations`), capture all:
   - Exact code commands, scripts, CLI flags, or API routes discussed or shown.
   - Configuration parameters, environment variables, resource ARNs, IPs, or endpoints.
   - Domain-specific business rules, metrics, quotas, or operational requirements.
   Format these with markdown code blocks or structured bullet points so no technical details are lost.
3. If participants did NOT explicitly designate follow-up tasks, state:
   `- No explicit follow-up action items were assigned during this session.`

---
## INSTRUCTIONS & STRUCTURE:
1. TITLE REQUIREMENT: Start the ===SUMMARY=== block with a single top-level `# [Specific Meeting Title]` naming the substantive topic or project discussed (e.g. `# API Gateway Architecture & Throttle Sync` or `# Q3 Product Roadmap Alignment`). DO NOT use generic phrases like "Meeting Summary".
2. STEP DESCRIPTIONS REQUIREMENT: For each step in ===IMPORTANT_STEPS===, you MUST provide an entry in ===STEP_DESCRIPTIONS===:
   - "title": Concise 2-5 word action-oriented title (e.g., "IAM Trust Policy Setup").
   - "description": 1-3 detailed sentences explaining EXACTLY what operation was performed at that specific time, what tool or console was manipulated, and what changes occurred. When filling technical context gaps, append `[Context Reference: ...]` clearly distinguishing researched context from the in-meeting action.
   - "audio_transcript": The exact words spoken by the relevant speaker at this moment, labeled with their name or Speaker 1/2 (e.g., "Alex: 'Make sure we allow sts:AssumeRole for the lambda service'"). If no speech occurred at that moment, output "" (empty string).

STRUCTURE YOUR OUTPUT WITH THESE EXACT DELIMITERS:

===SUMMARY===

# [Specific 3-7 Word Meeting Title Based on Core Topic]

### Executive Overview
Meaningful, cohesive summary of 50-60 words capturing the primary meeting discussion, core decisions, and critical action items without fluff.

- Detailed, clearly highlighted key point 1 explaining the primary discussion and platforms.
- Detailed, clearly highlighted key point 2 noting specific architectural or operational agreements.
- Detailed, clearly highlighted key point 3 outlining next steps and milestone deliverables.

{transcript_section}### Decisions & Outcomes
- Accomplishments finalized.
- Follow-up items using **[HIGH PRIORITY]** or **[ACTION ITEM]** tags.

### Technical & Domain Parameters
- Specific commands, configuration values, domain rules, and architecture details discussed or demonstrated.

===IMPORTANT_STEPS===
["step_1", "step_2", "step_3"]

===STEP_DESCRIPTIONS===
{{"step_1": {{"title": "Role Configuration", "description": "User initiated IAM role creation and specified trusted entities for access. [Context Reference: In AWS IAM, trust policies define which external identities or services are permitted to assume a role via the sts:AssumeRole API.]", "audio_transcript": "Speaker 1: 'Now let's configure the trusted entities for the deployment role.'"}}}}
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
    def _clean_step_quote(quote: Any) -> str:
        """The model's spoken quote with speaker tags humanized, or '' when it means silence."""
        text = str(quote or "").strip()
        lowered = text.lower().strip(" .\"'()")
        if lowered in _SILENT_QUOTES or any(ph in lowered for ph in _QUOTE_PLACEHOLDERS):
            return ""
        return humanize_speaker_tags(text)

    @staticmethod
    def _strip_code_fences(text: str) -> str:
        return re.sub(r"```(?:json)?\s*(.*?)\s*```", r"\1", text.strip(), flags=re.DOTALL)

    def _parse_structured_response(
        self, raw: str, effective_steps: list[dict[str, Any]] | None = None
    ) -> tuple[str, list[str], dict[str, Any], dict[str, Any]]:
        summary = "Meeting summary could not be extracted."
        important_steps: list[str] = []
        step_descriptions: dict[str, Any] = {}
        custom_fields_dict: dict[str, Any] = {}

        # 1. Parse delimited blocks order-independently
        sections = re.split(r"===([A-Z_]+)===", raw)
        blocks: dict[str, str] = {}
        if len(sections) > 1:
            for i in range(1, len(sections), 2):
                h = sections[i].strip()
                c = sections[i + 1].strip()
                blocks[h] = c
        else:
            blocks["SUMMARY"] = raw.strip()

        # Extract SUMMARY (text before the first delimiter when the model skipped ===SUMMARY===)
        summary = blocks.get("SUMMARY") or sections[0].strip() or summary

        # Purge any granular raw action timelines from the summary
        summary = re.sub(
            r"#{1,4}\s*Detailed Actions Timeline.*?(?=(?:#{1,4}\s+|\Z))",
            "",
            summary,
            flags=re.DOTALL | re.IGNORECASE,
        ).strip()

        # Extract CUSTOM_FIELDS
        if "CUSTOM_FIELDS" in blocks:
            try:
                cleaned_cf = self._strip_code_fences(blocks["CUSTOM_FIELDS"])
                json_match = re.search(r"\{.*\}", cleaned_cf, re.DOTALL)
                custom_fields_dict = json.loads(json_match.group(0) if json_match else cleaned_cf)
            except Exception as cfe:
                logger.debug(f"Failed to parse custom fields JSON: {cfe}")

        # Extract STEP_DESCRIPTIONS
        if "STEP_DESCRIPTIONS" in blocks:
            try:
                cleaned_desc = self._strip_code_fences(blocks["STEP_DESCRIPTIONS"])
                json_match = re.search(r"\{.*\}", cleaned_desc, re.DOTALL)
                raw_sd = json.loads(json_match.group(0) if json_match else cleaned_desc)
                if isinstance(raw_sd, dict):
                    step_descriptions = raw_sd
                    for meta in raw_sd.values():
                        if isinstance(meta, dict):
                            meta["audio_transcript"] = self._clean_step_quote(meta.get("audio_transcript"))
            except Exception as e:
                logger.debug(f"Failed to parse step_descriptions JSON: {e}")

        summary = humanize_speaker_tags(summary)

        # Extract IMPORTANT_STEPS
        if "IMPORTANT_STEPS" in blocks:
            steps_block = self._strip_code_fences(blocks["IMPORTANT_STEPS"])
            try:
                json_match = re.search(r"\[.*\]", steps_block, re.DOTALL)
                parsed = json.loads(json_match.group(0) if json_match else steps_block)
                if isinstance(parsed, list):
                    important_steps = [str(x) for x in parsed]
            except Exception as e:
                logger.debug(f"Failed to parse important_steps JSON, trying regex fallback: {e}")
                important_steps = [f"step_{m}" for m in re.findall(r"(?:step[_\s]*)?(\d+)", steps_block, re.IGNORECASE)]

        # Recovery: the model described steps but forgot to list them
        if not important_steps and step_descriptions:
            logger.info("Recovering important_steps from step_descriptions keys.")
            important_steps = [str(k) for k in step_descriptions]

        steps = effective_steps or []

        # Post-filter: drop internal DeskMate or window-switch moments the model picked anyway
        def is_noise(sid: str) -> bool:
            meta = step_descriptions.get(sid) or step_descriptions.get(sid.lower())
            meta_text = f"{meta.get('title') or ''} {meta.get('description') or ''}" if isinstance(meta, dict) else ""
            if any(kw in f"{meta_text} {sid}".lower() for kw in HOST_UI_KEYWORDS):
                return True
            step = find_step(steps, sid)
            return step is not None and is_host_ui_step(step)

        important_steps = [sid for sid in important_steps if not is_noise(sid)]

        # Fallback: keep at least MIN_KEY_MOMENTS by adding evenly spaced real moments
        if len(important_steps) < MIN_KEY_MOMENTS and steps:
            chosen = {step_number(sid) for sid in important_steps}
            candidates = [
                s for s in steps
                if step_number(s.get("step_id")) not in chosen and not is_host_ui_step(s)
            ]
            if len(candidates) > FALLBACK_KEY_MOMENTS:
                last = len(candidates) - 1
                picks = sorted({round(i * last / (FALLBACK_KEY_MOMENTS - 1)) for i in range(FALLBACK_KEY_MOMENTS)})
                candidates = [candidates[i] for i in picks]
            if candidates:
                logger.info(f"Adding {len(candidates)} representative visual moments as fallback.")
            important_steps += [f"step_{s.get('step_id')}" for s in candidates]

        important_steps = order_step_ids(important_steps, steps)

        return summary, important_steps, step_descriptions, custom_fields_dict
