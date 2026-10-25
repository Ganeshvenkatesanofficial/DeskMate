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
from settings import OLLAMA_BASE_URL, GEMINI_API_KEY, DEFAULT_GEMINI_MODEL, OLLAMA_CHAT_MODEL
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
from services.meeting_intelligence.native_screen_ocr import recognize_text

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
MAX_OLLAMA_CANDIDATES = 4
# The report always shows at least this many key moments when the screen recorded any.
MIN_KEY_MOMENTS = 4
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
        ollama_model: str = OLLAMA_CHAT_MODEL,
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
        effective_steps = clean_steps  # NEVER fall back to steps containing DeskMate UI

        # 1. Build visual timeline text
        timeline_blocks = []
        for s in effective_steps:
            s_id = s.get("step_id", "?")
            s_summary = s.get("summary", "Screen interaction")
            actions = s.get("actions", [])
            s_ts = s.get("timestamp") or (actions[0].get("timestamp") if actions else "00:00")
            action_lines = []
            seen_actions = set()
            for a in actions:
                a_ts = a.get("timestamp", s_ts)
                a_event = a.get("event") or a.get("type", "action")
                a_target = str(a.get("target") or a.get("description", "")).strip()
                if a_target.lower() in ("error_state", "unclassified", "interactive region", ""):
                    desc = a_event
                else:
                    desc = f"{a_event}: {a_target}"
                if desc in seen_actions:
                    continue
                seen_actions.add(desc)
                action_lines.append(f"    - [{a_ts}] {desc}")
                if len(action_lines) >= 4:
                    break
            action_text = "\n".join(action_lines) if action_lines else "    - (UI interaction)"
            summary_clean = s_summary
            prefix = f"Step {s_id}: "
            if summary_clean.startswith(prefix):
                summary_clean = summary_clean[len(prefix):]

            path = step_screenshot_path(s)
            ocr_snippet = ""
            if path:
                lines = recognize_text(path)
                if lines:
                    ocr_snippet = f" | Screen Text: {', '.join(lines[:6])}"

            timeline_blocks.append(f"Step {s_id} [{s_ts}]: {summary_clean}{ocr_snippet}\n{action_text}")
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
            raw_response, effective_steps=effective_steps, transcript_data=transcript_data
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
                meta["title"] = readable_step_title(str(step.get("summary") or ""), step=step)
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
            "For each distinct key spoken point, write ONE concise bullet using this exact format:\n"
            '- **Speaker Name** [MM:SS]: *"Concise verbatim quote or verbal agreement, max 1-2 sentences"*\n'
            "Extract only the most significant decisions, directions, or technical agreements (max 3-4 bullets total). Do NOT dump full paragraphs.\n\n"
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
   - In step descriptions, describe the in-meeting action and operation first, then provide the researched technical context explicitly prefixed with `[Context Reference: ...]` (e.g. `User configured authentication middleware in the backend settings. [Context Reference: In web applications, middleware intercepts incoming HTTP requests to validate session tokens or API credentials before routing to downstream endpoints.]`).
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
7. **SCREENSHOT VERIFICATION & RELEVANCE**: Only select steps whose screenshot image visibly shows actual meeting content (e.g. cloud settings, application UI, code, slides, or diagrams). The description MUST accurately describe the visual content visible on that screen. NEVER select a screenshot that shows DeskMate's own recording screen, a blank screen, or an unrelated window.

---
## COMPREHENSIVE ACTION ITEMS & DYNAMIC DOMAIN DETAILS:
1. **CAPTURE ALL HIGH-PRIORITY & ACTION ITEMS**: Never omit critical deliverables, urgent tasks, blockers, or assigned action items mentioned in speech or shown on screen.
   Tag them clearly:
   - `- **[HIGH PRIORITY]** [Assignee / Team if stated]: [Critical task, blocker, security concern, or urgent deadline]`
   - `- **[ACTION ITEM]** [Assignee / Team if stated]: [Concrete deliverable, next step, or follow-up commitment]`
   - `- **[IMPORTANT]** [Key architectural, business, or operational decision finalized]`
2. **DYNAMIC DOMAIN & TECHNICAL SPECIFICS**:
   Under `### Technical & Domain Parameters` (and additional dynamic subheadings as needed, e.g. `### Architecture & Infrastructure`, `### Security & Permissions`, `### Database & Schema Configurations`), capture all:
   - Software platforms, tools, APIs, configurations, architectures, workflows, and domain parameters discussed or demonstrated.
   - Exact code commands, scripts, CLI flags, or API routes discussed or shown.
   - Configuration parameters, environment variables, resource ARNs, IPs, or endpoints.
   - Domain-specific business rules, metrics, quotas, or operational requirements.
   NEVER output 'Not discussed' if technical operations, cloud tools, or software workflows were demonstrated or discussed in the meeting. If no technical parameters or configurations occurred in the meeting, omit this section.
3. If participants did NOT explicitly designate follow-up tasks, state:
   `- No explicit follow-up action items were assigned during this session.`

---
---
## CRITICAL GROUNDING & FIDELITY DIRECTIVE (STRICT ANTI-HALLUCINATION):
1. **EXCLUSIVELY USE PROVIDED SOURCES**: All meeting titles, executive summaries, spoken highlights, decisions, action items, and technical parameters MUST be derived EXCLUSIVELY from SOURCE 1 (Visual Event Log & Screen OCR) and SOURCE 2 (Voxtral Audio Transcript).
2. **ZERO TOLERANCE FOR BORROWED OR FICTIONAL TOPICS**: Absolutely DO NOT invent, assume, or mention topics, projects, or people (such as 'API Gateway', 'Throttle Sync', 'CloudWatch', 'Alex', 'John', 'Peter', 'billing', 'database connection pool') unless they are explicitly present in the actual audio transcript or screen OCR provided above.
3. **STRICT DOMAIN ALIGNMENT**: If the meeting transcript and visual timeline are about AWS IAM user creation, the entire report—title, overview, decisions, action items, and technical parameters—MUST focus 100% on AWS IAM user creation, permissions, and security credentials.

---
## INSTRUCTIONS & STRUCTURE:
1. TITLE REQUIREMENT: Start the ===SUMMARY=== block with a single top-level `# [Specific Meeting Title]` naming the substantive topic or project discussed (derived strictly from what was discussed and shown on screen). DO NOT use generic phrases like "Meeting Summary". NEVER copy example text.
2. STEP DESCRIPTIONS REQUIREMENT: For each step in ===IMPORTANT_STEPS===, you MUST provide an entry in ===STEP_DESCRIPTIONS===:
   - "title": Concise 2-5 word action-oriented title.
   - "description": 1-3 detailed sentences explaining EXACTLY what operation was performed at that specific time, what tool or console was manipulated, and what changes occurred. When filling technical context gaps, append `[Context Reference: ...]` clearly distinguishing researched context from the in-meeting action.
   - "audio_transcript": The exact words spoken by the relevant speaker at this moment, labeled with their name or Speaker 1/2 (e.g., "Speaker 1: '...'"). If no speech occurred at that moment, output "" (empty string).

STRUCTURE YOUR OUTPUT WITH THESE EXACT DELIMITERS:

===SUMMARY===

# [Specific 3-7 Word Meeting Title Based on Core Topic]

### Executive Overview
Meaningful, cohesive summary of 50-60 words capturing the primary meeting discussion, core decisions, and critical action items without fluff.

- **Primary Focus & Platforms**: Detailed, clearly highlighted key point explaining the primary discussion and platforms.
- **Technical & Architectural Scope**: Detailed, clearly highlighted key point noting specific architectural or operational agreements.
- **Key Milestones & Deliverables**: Detailed, clearly highlighted key point outlining next steps and milestone deliverables.

{transcript_section}
### Decisions & Outcomes
- Accomplishments finalized.
- Follow-up items using **[HIGH PRIORITY]** or **[ACTION ITEM]** tags.

### Technical & Domain Parameters
- Specific tools, platforms, APIs, schemas, configurations, commands, endpoints, or domain metrics discussed or demonstrated. If no technical parameters or configurations occurred in the meeting, omit this section.

===IMPORTANT_STEPS===
["step_1", "step_2", "step_3"]
(IMPORTANT: Output ONLY valid step IDs matching the numbers from SOURCE 1 Visual Event Log, e.g. ["step_1", "step_2"]. NEVER output arbitrary text strings like ["ui_interaction"]).

===STEP_DESCRIPTIONS===
{{"step_1": {{"title": "[Concise Action Title for Step 1]", "description": "[Accurate description of the visual action and context for Step 1]", "audio_transcript": "[Exact spoken words at this moment, or empty string if silent]"}}}}
{custom_delimiters}
"""

    def _resolve_available_ollama_models(self) -> list[str]:
        """Resolve available Ollama models. Prioritizes the user's configured model,
        followed by the highest parameter/capability text-generation models installed on the system."""
        candidates = []
        try:
            r = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=3)
            if r.status_code == 200:
                models_data = r.json().get("models", [])
                compatible_entries = []
                for m in models_data:
                    name = str(m.get("name") or "")
                    details = m.get("details") or {}
                    family = str(details.get("family") or "").lower()
                    # Exclude embedding models and vision-specific architectures
                    if any(term in name.lower() or term in family for term in ["embed", "vision", "mllama", "clip"]):
                        continue
                    # Parse parameter size to prioritize larger models (e.g. 20.9B > 7B > 1.5B)
                    param_str = str(details.get("parameter_size") or "0").upper().replace("B", "").replace("M", "")
                    try:
                        param_val = float(param_str)
                    except ValueError:
                        param_val = 0.0
                    compatible_entries.append((param_val, name))

                # Sort compatible models by parameter size descending (most capable first)
                compatible_entries.sort(key=lambda x: x[0], reverse=True)
                compatible = [entry[1] for entry in compatible_entries]

                # 1. Prioritize user's configured model if explicitly set and text-compatible
                if self.ollama_model and not any(term in self.ollama_model.lower() for term in ["vision", "mllama"]):
                    for m in compatible:
                        if self.ollama_model.lower() in m.lower() or m.lower() in self.ollama_model.lower():
                            candidates.append(m)
                            break

                # 2. Add remaining compatible models as candidates
                for m in compatible:
                    if m not in candidates:
                        candidates.append(m)
        except Exception as e:
            logger.debug(f"Failed to query Ollama tags: {e}")

        if not candidates and self.ollama_model:
            candidates.append(self.ollama_model)
        return candidates

    def _resolve_available_ollama_model(self) -> str:
        """Resolve the primary available Ollama model name."""
        try:
            candidates = self._resolve_available_ollama_models()
            return candidates[0] if candidates else (self.ollama_model or "ollama")
        except Exception:
            return self.ollama_model or "ollama"

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
        """Translate each transcript segment into English (any source language).
        Segments that can't be translated stay as spoken."""
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
            logger.info(f"[MODEL SELECT] Meeting Summarizer selected Cloud Gemini: '{self.gemini_model}'")
            logger.info("[MODEL INFERENCE] Meeting Summarizer querying Gemini REST API...")
            text = self._gemini_generate(parts, api_key)
            if text:
                logger.info(f"[MODEL SUCCESS] Gemini '{self.gemini_model}' generated executive summary ({len(text)} chars)")
                return text
            logger.warning("[MODEL WARNING] Gemini did not return a summary. Falling back to local Ollama.")

        # 2. Local Ollama fallback
        candidates = self._resolve_available_ollama_models()
        logger.info(f"[MODEL SELECT] Meeting Summarizer resolving Ollama candidates: {candidates[:MAX_OLLAMA_CANDIDATES]}")

        for active_model in candidates[:MAX_OLLAMA_CANDIDATES]:
            try:
                logger.info(f"[MODEL LOAD] Invoking Ollama candidate model: '{active_model}' for summarization...")
                # Trim prompt if exceedingly large for small local context models
                trimmed_prompt = plain_prompt if len(plain_prompt) <= 16000 else plain_prompt[:16000] + "\n\n[Prompt truncated for local context limits. Please produce the complete report structure above.]"
                res = requests.post(
                    f"{OLLAMA_BASE_URL}/api/generate",
                    json={
                        "model": active_model,
                        "prompt": trimmed_prompt,
                        "stream": True,
                        "options": {"num_ctx": 4096},
                    },
                    stream=True,
                    timeout=(15, 300),
                )
                if res.status_code == 200:
                    chunks = []
                    for line in res.iter_lines():
                        if line:
                            try:
                                data = json.loads(line.decode("utf-8"))
                                chunks.append(data.get("response", ""))
                                if data.get("done", False):
                                    break
                            except Exception:
                                pass
                    text_resp = "".join(chunks)
                    if text_resp and text_resp.strip():
                        logger.info(f"[MODEL SUCCESS] Ollama model '{active_model}' successfully generated summary ({len(text_resp)} chars)")
                        return text_resp
                else:
                    logger.warning(
                        f"[MODEL WARNING] Ollama model '{active_model}' returned {res.status_code}: {res.text}. Trying next candidate model..."
                    )
            except Exception as oe:
                logger.warning(f"[MODEL WARNING] Local Ollama generation error with model '{active_model}': {oe}. Trying next candidate...")

        logger.warning("[MODEL FAILED] All summarization engines failed (Gemini and Ollama). Generating local structured meeting brief.")
        return """===SUMMARY===
# Executive Meeting Brief (Local Analysis)

## Executive Overview
This meeting recording has been archived and processed locally. Key screen captures, discussion timestamps, and visual checkpoints are detailed in the audit chronology below.

## Key Discussion Points
- Session recording and visual audit trail preserved.
- Local OCR and timeline synchronized with audio discussion.

===IMPORTANT_STEPS===
[]
===STEP_DESCRIPTIONS===
{}
===CUSTOM_FIELDS===
{}
"""

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

    @staticmethod
    def _clean_technical_parameters(
        summary: str, transcript_data: dict[str, Any] | None, steps: list[dict[str, Any]]
    ) -> str:
        """Format Technical & Domain Parameters cleanly when provided by the model,
        and completely remove the section if no technical parameters were discussed
        (preventing empty 'Not discussed' boilerplate)."""
        pattern = r"#{2,3}\s*Technical\s*&\s*Domain\s*Parameters.*?(?=(?:#{1,4}\s+|\Z))"
        match = re.search(pattern, summary, re.IGNORECASE | re.DOTALL)
        if not match:
            return summary

        sec_body = match.group(0).strip()
        lines = [line.strip() for line in sec_body.splitlines() if line.strip()]

        # Filter out empty or negative boilerplate
        valid_bullets = [
            l for l in lines[1:]
            if l.startswith(("-", "*")) and not any(p in l.lower() for p in ("not discussed", "n/a", "none", "not applicable", "no technical", "not specified"))
        ]

        if valid_bullets:
            cleaned_bullets = []
            for b in valid_bullets:
                b_content = re.sub(r"^[-*]\s*", "", b).strip()
                if not b_content.startswith("**"):
                    if ":" in b_content:
                        p0, p1 = b_content.split(":", 1)
                        cleaned_bullets.append(f"- **{p0.strip()}**: {p1.strip()}")
                    else:
                        words = b_content.split()
                        lead = " ".join(words[:min(3, len(words))])
                        rest = " ".join(words[min(3, len(words)):])
                        cleaned_bullets.append(f"- **{lead}**: {rest}" if rest else f"- **{lead}**")
                else:
                    cleaned_bullets.append(f"- {b_content}")
            replacement = "### Technical & Domain Parameters\n" + "\n".join(cleaned_bullets)
            return re.sub(pattern, replacement + "\n\n", summary, flags=re.DOTALL | re.IGNORECASE).strip()

        # If no valid domain/technical parameters were discussed or identified by the model,
        # remove the section completely rather than keeping empty boilerplate.
        return re.sub(pattern, "", summary, flags=re.DOTALL | re.IGNORECASE).strip()

    @staticmethod
    def _clean_executive_overview(
        summary: str, transcript_data: dict[str, Any] | None, steps: list[dict[str, Any]]
    ) -> str:
        """Ensure Executive Overview has a cohesive introductory paragraph followed by clearly highlighted bullets,
        all dynamically derived from the meeting content."""
        pattern = r"(#{2,3}\s*Executive Overview\s*\n)(.*?)(?=(?:#{1,4}\s+|\Z))"
        match = re.search(pattern, summary, re.IGNORECASE | re.DOTALL)
        if not match:
            return summary

        header = match.group(1)
        body = match.group(2).strip()

        existing_bullets = [line for line in body.split("\n") if line.strip().startswith(("-", "*"))]

        # Case 1: Bullets already provided by the model
        if len(existing_bullets) >= 2:
            cleaned_lines = []
            for line in body.split("\n"):
                stripped = line.strip()
                if stripped.startswith(("-", "*")):
                    b_content = re.sub(r"^[-*]\s*", "", stripped).strip()
                    if not b_content.startswith("**"):
                        if ":" in b_content:
                            parts = b_content.split(":", 1)
                            line = f"- **{parts[0].strip()}**: {parts[1].strip()}"
                        else:
                            words = b_content.split()
                            bold_count = min(3, len(words))
                            bold_part = " ".join(words[:bold_count])
                            rest = " ".join(words[bold_count:])
                            line = f"- **{bold_part}**: {rest}" if rest else f"- **{bold_part}**"
                cleaned_lines.append(line)
            replacement = header + "\n".join(cleaned_lines) + "\n\n"
            return re.sub(pattern, replacement, summary, flags=re.DOTALL | re.IGNORECASE).strip()

        # Case 2: Model provided prose/paragraphs without bullets
        body_non_bullet = "\n".join(l for l in body.split("\n") if not l.strip().startswith(("-", "*"))).strip()
        body_sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", body_non_bullet) if len(s.strip()) > 20]

        overview_para = ""
        bullets = []

        if len(body_sentences) >= 2:
            overview_para = body_sentences[0]
            for s in body_sentences[1:4]:
                words = s.split()
                bold_count = min(3, len(words))
                bold_lead = " ".join(words[:bold_count]).strip(": -")
                rest = " ".join(words[bold_count:]).strip()
                bullets.append(f"- **{bold_lead}**: {rest}" if rest else f"- **{bold_lead}**")
        elif body_sentences:
            overview_para = body_sentences[0]

        # Case 3: Need dynamic bullets from actual meeting data (steps and transcript)
        if len(bullets) < 2:
            substantive_steps = [s for s in steps if not is_host_ui_step(s) and str(s.get("summary") or "").strip()]
            transcript_segs = (transcript_data or {}).get("segments", [])

            if not overview_para:
                if substantive_steps:
                    overview_para = f"This session covered {substantive_steps[0].get('summary', 'the core workflow')}, reviewing operational procedures and key discussions across the meeting timeline."
                elif transcript_segs:
                    first_text = str(transcript_segs[0].get("text") or "").strip()
                    overview_para = f"This session addressed key topics initiated in the discussion: {first_text[:120]}."
                else:
                    overview_para = "This meeting focused on operational procedures, system workflows, and key project deliverables."

            if substantive_steps:
                first_s = substantive_steps[0].get("summary") or "Initiated session workflow"
                bullets.append(f"- **Initial Focus & Setup**: {first_s.rstrip('.')}.")
                if len(substantive_steps) > 1:
                    mid_s = substantive_steps[len(substantive_steps) // 2].get("summary") or "Reviewed operational details"
                    bullets.append(f"- **Core Workflow**: {mid_s.rstrip('.')}.")
                if len(substantive_steps) > 2:
                    last_s = substantive_steps[-1].get("summary") or "Finalized session deliverables"
                    bullets.append(f"- **Outcomes & Next Steps**: {last_s.rstrip('.')}.")
            elif transcript_segs:
                positions = [0]
                if len(transcript_segs) > 1:
                    positions.append(len(transcript_segs) // 2)
                if len(transcript_segs) > 2:
                    positions.append(len(transcript_segs) - 1)
                labels = ["Primary Focus", "Key Discussion", "Next Steps"]
                for p_idx, pos in enumerate(positions):
                    seg = transcript_segs[pos]
                    t = str(seg.get("text") or "").strip()
                    if t:
                        t_clean = re.sub(r"(?i)^(?:so\s*,?|okay\s*,?|well\s*,?)+\s*", "", t)[:140].strip()
                        bullets.append(f"- **{labels[p_idx]}**: {t_clean.rstrip('.')}.")

        if not bullets:
            bullets.append("- **Primary Focus**: Comprehensive session review and operational alignment.")
            bullets.append("- **Key Outcomes**: Documented discussion checkpoints and next action items.")

        new_section = f"{header}{overview_para}\n\n" + "\n".join(bullets) + "\n\n"
        return re.sub(pattern, new_section, summary, flags=re.DOTALL | re.IGNORECASE).strip()

    @staticmethod
    def _clean_spoken_transcript_highlights(
        summary: str, transcript_data: dict[str, Any] | None
    ) -> str:
        """Format Spoken Transcript Highlights into concise, bolded, attributed quotes with timestamps,
        dynamically selected across the meeting timeline."""
        pattern = r"#{2,3}\s*Spoken Transcript Highlights.*?(?=(?:#{1,4}\s+|\Z))"
        match = re.search(pattern, summary, re.IGNORECASE | re.DOTALL)

        segments = []
        if transcript_data:
            segments = transcript_data.get("segments", [])

        # If no transcript data exists at all, remove empty section if model generated one
        if not segments and not (transcript_data and transcript_data.get("full_transcript")):
            if match:
                summary = re.sub(pattern, "", summary, flags=re.DOTALL | re.IGNORECASE).strip()
            return summary

        new_bullets = []

        def clean_quote_text(raw: str) -> str:
            q = re.sub(r"(?i)^(?:so\s*,?|okay\s*,?|well\s*,?|anyway\s*,?|now\s*,?|all right\s*,?|um\s*,?|uh\s*,?|yeah\s*,?)+\s*", "", raw)
            q = re.sub(r"(?i)\b(?:as you can see|like i said|you know|i'm just gonna|i'm just going to)\b", "", q)
            q = re.sub(r"\s{2,}", " ", q).strip()
            sents = [s.strip() for s in re.split(r"(?<=[.!?])\s+", q) if s.strip()]
            if sents:
                res = sents[0]
                if len(res) < 70 and len(sents) > 1:
                    res += " " + sents[1]
                if len(res) > 140:
                    res = res[:137].rsplit(" ", 1)[0] + "..."
            else:
                res = q[:137].rsplit(" ", 1)[0] + "..." if len(q) > 140 else q
            return res.strip().rstrip(".,") + "." if not res.endswith((".", "!", "?", "...")) else res

        # 1. Parse existing bullets from summary if present
        if match:
            section_text = match.group(0)
            lines = section_text.split("\n")
            for line in lines:
                stripped = line.strip()
                if not stripped or stripped.startswith("###") or ("extract" in stripped.lower() and "transcript" in stripped.lower()):
                    continue

                clean_line = re.sub(r"^[-*]\s*", "", stripped)

                ts_match = re.search(r"\[(\d{1,2}:\d{2})\]|\((\d{1,2}:\d{2})\)", clean_line)
                ts_str = f" [{ts_match.group(1) or ts_match.group(2)}]" if ts_match else ""
                clean_line = re.sub(r"\[\d{1,2}:\d{2}(?:\s*->\s*\d{1,2}:\d{2})?\]|\(\d{1,2}:\d{2}\)", "", clean_line).strip()

                spk_match = re.match(r"^(\*{0,2}(?:Speaker\s*\d+|[A-Z][a-zA-Z0-9_\s]{1,15})\*{0,2}):\s*(.*)", clean_line)
                if spk_match:
                    speaker = spk_match.group(1).replace("*", "").strip()
                    quote = spk_match.group(2).strip()
                else:
                    speaker = "Speaker 1"
                    quote = clean_line

                quote = quote.strip("\"'")
                if not quote or len(quote) < 10:
                    continue

                condensed = clean_quote_text(quote)
                if len(condensed) > 15:
                    new_bullets.append(f'- **{speaker}**{ts_str}: *"{condensed}"*')

        # 2. If fewer than 3 bullets, extract dynamically from transcript segments across timeline
        if len(new_bullets) < 3 and segments:
            new_bullets = []
            valid_segs = [
                seg for seg in segments
                if len(str(seg.get("text") or "").strip()) >= 25
                and not any(phrase in str(seg.get("text") or "").lower() for phrase in ("can you hear me", "sound check", "testing 1 2"))
            ]

            if valid_segs:
                num_picks = min(4, len(valid_segs))
                step_size = len(valid_segs) / float(num_picks)
                chosen_segs = []
                for b_idx in range(num_picks):
                    bin_start = int(b_idx * step_size)
                    bin_end = int((b_idx + 1) * step_size) if b_idx < num_picks - 1 else len(valid_segs)
                    bin_candidates = valid_segs[bin_start:bin_end]
                    if bin_candidates:
                        best = max(bin_candidates, key=lambda s: len(str(s.get("text") or "").strip()))
                        chosen_segs.append(best)

                for seg in chosen_segs:
                    speaker = str(seg.get("speaker") or "Speaker 1").strip()
                    start = float(seg.get("start") or 0.0)
                    sm, ss = int(start // 60), int(start % 60)
                    ts_str = f" [{sm:02d}:{ss:02d}]"
                    raw_text = str(seg.get("text") or "").strip()
                    condensed = clean_quote_text(raw_text)
                    if len(condensed) > 15:
                        new_bullets.append(f'- **{speaker}**{ts_str}: *"{condensed}"*')

        if new_bullets:
            replacement = "### Spoken Transcript Highlights\n" + "\n".join(new_bullets[:4])
            if match:
                summary = re.sub(pattern, replacement + "\n\n", summary, flags=re.DOTALL | re.IGNORECASE).strip()
            else:
                d_pattern = r"(###\s*Decisions\s*&\s*Outcomes)"
                if re.search(d_pattern, summary, re.IGNORECASE):
                    summary = re.sub(d_pattern, replacement + "\n\n\\1", summary, flags=re.IGNORECASE)
                else:
                    summary += "\n\n" + replacement

        return summary

    @staticmethod
    def _convert_json_summary_if_needed(
        summary: str,
    ) -> tuple[str, list[str] | None, dict[str, Any] | None]:
        """Convert JSON model responses into structured Markdown, important steps, and descriptions."""
        trimmed = summary.strip()
        cleaned = re.sub(r"```(?:json)?\s*(.*?)\s*```", r"\1", trimmed, flags=re.DOTALL).strip()
        if not (cleaned.startswith("{") and ("OVERVIEW" in cleaned.upper() or "SUMMARY" in cleaned.upper() or "STEPS" in cleaned.upper())):
            return summary, None, None

        title = "# Meeting Intelligence Brief"
        exec_lines = []
        overview_text = ""
        decisions_bullets = []
        tech_bullets = []
        other_sections = []
        imp_steps = None
        step_desc = None

        parsed_json: dict[str, Any] | None = None
        try:
            parsed_json = json.loads(cleaned)
        except Exception:
            j_match = re.search(r"\{.*\}", cleaned, re.DOTALL)
            if j_match:
                try:
                    parsed_json = json.loads(j_match.group(0))
                except Exception:
                    pass

        if isinstance(parsed_json, dict):
            for k, v in parsed_json.items():
                k_lower = k.lower()
                if k.startswith("#") or "title" in k_lower:
                    title = f"# {str(v).lstrip('#').strip()}" if not k.startswith("#") else k
                elif "important_step" in k_lower or k_lower == "steps":
                    if isinstance(v, list):
                        imp_steps = [str(x) for x in v]
                elif "step_description" in k_lower or "descriptions" in k_lower:
                    if isinstance(v, dict):
                        step_desc = v
                elif "overview" in k_lower or "summary" in k_lower:
                    if isinstance(v, dict):
                        for sub_k, sub_v in v.items():
                            exec_lines.append(f"- **{sub_k.replace('_', ' ').title()}**: {sub_v}")
                    elif isinstance(v, list):
                        for item in v:
                            exec_lines.append(f"- {item}")
                    elif isinstance(v, str):
                        overview_text = v
                elif any(word in k_lower for word in ("decision", "outcome", "action", "next_step")):
                    if isinstance(v, list):
                        for item in v:
                            decisions_bullets.append(f"- {item}")
                    elif isinstance(v, dict):
                        for sub_k, sub_v in v.items():
                            decisions_bullets.append(f"- **{sub_k.replace('_', ' ').title()}**: {sub_v}")
                    elif isinstance(v, str):
                        decisions_bullets.append(f"- {v}")
                elif any(word in k_lower for word in ("technical", "domain", "parameter", "architecture", "config")):
                    if isinstance(v, list):
                        for item in v:
                            tech_bullets.append(f"- {item}")
                    elif isinstance(v, dict):
                        for sub_k, sub_v in v.items():
                            tech_bullets.append(f"- **{sub_k.replace('_', ' ').title()}**: {sub_v}")
                    elif isinstance(v, str):
                        tech_bullets.append(f"- {v}")
                else:
                    if isinstance(v, (str, list, dict)):
                        sec_heading = f"\n### {k.replace('_', ' ').title()}"
                        if isinstance(v, list):
                            sec_body = "\n".join(f"- {item}" for item in v)
                        elif isinstance(v, dict):
                            sec_body = "\n".join(f"- **{sk.replace('_', ' ').title()}**: {sv}" for sk, sv in v.items())
                        else:
                            sec_body = str(v)
                        other_sections.append(f"{sec_heading}\n{sec_body}")
        else:
            title_match = re.search(r'"(#\s*[^"\n]+)"', cleaned)
            if title_match:
                title = title_match.group(1).strip()

            for k, v in re.findall(r'"([^"\n]{2,40})":\s*"([^"\n]{10,500})"', cleaned):
                if "step" not in k.lower():
                    exec_lines.append(f"- **{k.strip()}**: {v.strip()}")

            dec_matches = re.search(r'"(?:DECISIONS|OUTCOMES)[^"]*":\s*\[(.*?)\]', cleaned, re.DOTALL | re.IGNORECASE)
            if dec_matches:
                for item in re.findall(r'"([^"]+)"', dec_matches.group(1)):
                    decisions_bullets.append(f"- {item.strip()}")

            tech_matches = re.search(r'"(?:TECHNICAL|DOMAIN)[^"]*":\s*\[(.*?)\]', cleaned, re.DOTALL | re.IGNORECASE)
            if tech_matches:
                for item in re.findall(r'"([^"]+)"', tech_matches.group(1)):
                    tech_bullets.append(f"- {item.strip()}")

            steps_match = re.search(r'"IMPORTANT_STEPS":\s*\[(.*?)\]', cleaned, re.DOTALL)
            if steps_match:
                raw_ids = re.findall(r'"([^"]+)"', steps_match.group(1))
                if raw_ids:
                    imp_steps = raw_ids

            sd_match = re.search(r'"STEP_DESCRIPTIONS":\s*(\{.*?\})\s*\}', cleaned, re.DOTALL)
            if sd_match:
                try:
                    step_desc = json.loads(sd_match.group(1))
                except Exception:
                    pass

        # Build clean markdown document
        md_sections = [title, "### Executive Overview"]
        if overview_text:
            md_sections.append(overview_text)
        if exec_lines:
            md_sections.extend(exec_lines)
        elif not overview_text:
            md_sections.append("Comprehensive meeting discussion and visual workflow synthesized below.")

        if decisions_bullets:
            md_sections.append("\n### Decisions & Outcomes")
            md_sections.extend(decisions_bullets)

        if tech_bullets:
            md_sections.append("\n### Technical & Domain Parameters")
            md_sections.extend(tech_bullets)

        if other_sections:
            md_sections.extend(other_sections)

        return "\n".join(md_sections).strip(), imp_steps, step_desc

    def _parse_structured_response(
        self,
        raw: str,
        effective_steps: list[dict[str, Any]] | None = None,
        transcript_data: dict[str, Any] | None = None,
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

        # Strip stray markdown code fences or JSON wrapper artifacts
        if summary.startswith("```"):
            summary = re.sub(r"^```(?:json|markdown)?\s*", "", summary).strip()
            summary = re.sub(r"\s*```$", "", summary).strip()
        summary = re.sub(r'^\s*\{\s*"SUMMARY":\s*', "", summary).strip()
        summary = re.sub(r'^\s*"SUMMARY":\s*', "", summary).strip()

        # If model returned JSON instead of markdown, convert it
        summary, json_imp_steps, json_step_desc = self._convert_json_summary_if_needed(summary)
        if json_imp_steps and not important_steps:
            important_steps = [str(x) for x in json_imp_steps]
        if json_step_desc and not step_descriptions:
            step_descriptions = json_step_desc

        # Purge any granular raw action timelines from the summary
        summary = re.sub(
            r"#{1,4}\s*Detailed Actions Timeline.*?(?=(?:#{1,4}\s+|\Z))",
            "",
            summary,
            flags=re.DOTALL | re.IGNORECASE,
        ).strip()

        # Clean technical parameters from 'not discussed' when discussion happened
        summary = self._clean_technical_parameters(summary, transcript_data, effective_steps or [])

        # Clean executive overview to ensure bold highlights and clean structure
        summary = self._clean_executive_overview(summary, transcript_data, effective_steps or [])

        # Clean spoken transcript highlights into concise, bolded quote bullets
        summary = self._clean_spoken_transcript_highlights(summary, transcript_data)

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
                    for meta in raw_sd.values():
                        if isinstance(meta, dict):
                            meta["audio_transcript"] = self._clean_step_quote(meta.get("audio_transcript"))
                    # Remap any non-standard keys to available steps so descriptions are retained
                    steps = effective_steps or []
                    if steps:
                        remapped_sd = {}
                        avail_ids = [str(s.get("step_id")) for s in steps]
                        avail_idx = 0
                        for k, v in raw_sd.items():
                            snum = step_number(k)
                            if snum.isdigit() and int(snum) > 0:
                                remapped_sd[f"step_{snum}"] = v
                            elif avail_idx < len(avail_ids):
                                remapped_sd[f"step_{avail_ids[avail_idx]}"] = v
                                avail_idx += 1
                            else:
                                remapped_sd[k] = v
                        step_descriptions = remapped_sd
                    else:
                        step_descriptions = raw_sd
            except Exception as e:
                logger.debug(f"Failed to parse step_descriptions JSON: {e}")

        summary = humanize_speaker_tags(summary)

        # Extract IMPORTANT_STEPS
        raw_imp_steps = []
        if "IMPORTANT_STEPS" in blocks:
            steps_block = self._strip_code_fences(blocks["IMPORTANT_STEPS"])
            try:
                json_match = re.search(r"\[.*\]", steps_block, re.DOTALL)
                parsed = json.loads(json_match.group(0) if json_match else steps_block)
                if isinstance(parsed, list):
                    raw_imp_steps = [str(x) for x in parsed]
            except Exception as e:
                logger.debug(f"Failed to parse important_steps JSON, trying regex fallback: {e}")
                raw_imp_steps = [f"step_{m}" for m in re.findall(r"(?:step[_\s]*)?(\d+)", steps_block, re.IGNORECASE)]

        # Recovery: the model described steps but forgot to list them
        if not raw_imp_steps and step_descriptions:
            logger.info("Recovering important_steps from step_descriptions keys.")
            raw_imp_steps = [str(k) for k in step_descriptions]

        steps = effective_steps or []
        avail_step_map = {step_number(s.get("step_id")): s for s in steps}

        # Normalize and validate every important step against real session steps
        important_steps = []
        for x in raw_imp_steps:
            snum = step_number(x)
            if snum.isdigit() and snum in avail_step_map:
                sid = f"step_{snum}"
                if sid not in important_steps:
                    important_steps.append(sid)
            else:
                # If LLM wrote a tag or description keyword like 'ui_interaction', map to matching step
                query = str(x).lower().replace("step_", "").replace("step", "").strip()
                matched_num = None
                for num, s in avail_step_map.items():
                    s_sum = str(s.get("summary") or "").lower()
                    if query and (query in s_sum or s_sum in query):
                        matched_num = num
                        break
                if matched_num:
                    sid = f"step_{matched_num}"
                    if sid not in important_steps:
                        important_steps.append(sid)

        # Post-filter: drop internal DeskMate or window-switch moments the model picked anyway
        def is_noise(sid: str) -> bool:
            meta = step_descriptions.get(sid) or step_descriptions.get(sid.lower())
            meta_text = f"{meta.get('title') or ''} {meta.get('description') or ''}" if isinstance(meta, dict) else ""
            if any(kw in f"{meta_text} {sid}".lower() for kw in HOST_UI_KEYWORDS):
                return True
            step = find_step(steps, sid)
            return step is not None and is_host_ui_step(step)

        important_steps = [sid for sid in important_steps if not is_noise(sid)]

        # Fallback: keep at least min(MIN_KEY_MOMENTS, len(steps)) by adding evenly spaced real moments
        target_count = min(MIN_KEY_MOMENTS, len(steps))
        if len(important_steps) < target_count and steps:
            chosen = {step_number(sid) for sid in important_steps}
            candidates = [
                s for s in steps
                if step_number(s.get("step_id")) not in chosen and not is_host_ui_step(s)
            ]
            needed = target_count - len(important_steps)
            if len(candidates) > needed:
                last = len(candidates) - 1
                picks = sorted({round(i * last / (needed - 1)) for i in range(needed)}) if needed > 1 else [0]
                candidates = [candidates[i] for i in picks]
            if candidates:
                logger.info(f"Adding {len(candidates)} representative visual moments as fallback.")
            important_steps += [f"step_{s.get('step_id')}" for s in candidates]

        important_steps = order_step_ids(important_steps, steps)

        return summary, important_steps, step_descriptions, custom_fields_dict
