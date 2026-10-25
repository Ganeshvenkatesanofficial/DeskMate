"""
routers.meeting_routes — DeskMate Meeting Intelligence REST API
==============================================================
Provides lifecycle endpoints for starting/stopping sessions, streaming stats,
executing multimodal summarization, downloading DeskMate PDFs, and syncing tasks.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
import re
import os
import sys
import subprocess
import time
from datetime import datetime
from typing import Any, Optional
from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from pydantic import BaseModel

from core.database import db_add_task
from .ws_meeting_agent import meeting_ws_manager
from services.meeting_intelligence import (
    LivePipeline,
    VoxtralSpeechEngine,
    AudioExtractor,
    ChunkedTranscriber,
    MeetingSummarizer,
    MeetingPDFGenerator,
    MeetingExportService,
)
from services.meeting_intelligence.audio_service import LiveAudioRecorder
from services.meeting_intelligence.screen_capture_service import ScreenCapture
from services.meeting_intelligence.summarizer import (
    NothingToSummarizeError,
    SummarizationUnavailableError,
    extract_meeting_title,
)

from settings import SESSIONS_OUTPUT_DIR, DEFAULT_SCREEN_FPS, MAX_RETAINED_SESSIONS

logger = logging.getLogger("deskmate.meeting_routes")
router = APIRouter(prefix="/api/meeting", tags=["meeting"])

# Global session state singleton
_SESSION_STATE: dict[str, Any] = {
    "capture": None,
    "pipeline": None,
    "audio_recorder": None,
    "voxtral": VoxtralSpeechEngine(),
    "summarizer": MeetingSummarizer(),
    "pdf_generator": MeetingPDFGenerator(),
    "export_service": MeetingExportService(output_dir=SESSIONS_OUTPUT_DIR),
    "active_session_id": None,
    "output_dir": SESSIONS_OUTPUT_DIR,
}


class StartMeetingRequest(BaseModel):
    monitor: int = 1
    fps: float = DEFAULT_SCREEN_FPS
    allow_lightweight_mode: bool = False
    start_muted: bool = False
    gemini_api_key: Optional[str] = None


class SummarizeMeetingRequest(BaseModel):
    session_id: Optional[str] = None
    custom_fields: Optional[list[dict[str, str]]] = None
    purge_raw_assets_after: bool = False
    gemini_api_key: Optional[str] = None


class SyncTasksRequest(BaseModel):
    session_id: str
    action_items: list[str]


class ExportDriveRequest(BaseModel):
    session_id: str
    folder_name: str = "DeskMate Meetings"


class SendEmailRequest(BaseModel):
    session_id: str
    to_email: str
    subject: Optional[str] = None
    cc_email: Optional[str] = None
    user_name: Optional[str] = None
    designation: Optional[str] = None
    sender_email: Optional[str] = None
    pdf_name: Optional[str] = None


class CleanupSessionsRequest(BaseModel):
    max_keep: int = 10


class MuteMeetingRequest(BaseModel):
    muted: bool


_WIN_ES_CONTINUOUS = 0x80000000
_WIN_ES_SYSTEM_REQUIRED = 0x00000001
_WIN_ES_AWAYMODE_REQUIRED = 0x00000040


def _prevent_system_sleep() -> None:
    """Keep the computer awake while a meeting records (a sleep would cut the recording)."""
    try:
        if sys.platform == "darwin":
            # -w ties the assertion to this process, so it also ends if the backend dies.
            _SESSION_STATE["caffeinate_proc"] = subprocess.Popen(
                ["/usr/bin/caffeinate", "-ims", "-w", str(os.getpid())],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif sys.platform == "win32":
            import ctypes
            ctypes.windll.kernel32.SetThreadExecutionState(
                _WIN_ES_CONTINUOUS | _WIN_ES_SYSTEM_REQUIRED | _WIN_ES_AWAYMODE_REQUIRED
            )
    except Exception as err:
        logger.warning(f"Could not prevent system sleep during recording: {err}")


def _allow_system_sleep() -> None:
    try:
        caffeinate = _SESSION_STATE.pop("caffeinate_proc", None)
        if caffeinate:
            caffeinate.terminate()
        if sys.platform == "win32":
            import ctypes
            ctypes.windll.kernel32.SetThreadExecutionState(_WIN_ES_CONTINUOUS)
    except Exception as err:
        logger.debug(f"Could not release sleep prevention: {err}")


@router.post("/start")
async def start_meeting(req: StartMeetingRequest):
    """Start screen capture, live meeting event tracking & background audio recording."""
    try:
        if _SESSION_STATE["pipeline"] and _SESSION_STATE["pipeline"].state == LivePipeline.STATE_RECORDING:
            return {
                "status": "already_running",
                "session_id": _SESSION_STATE["active_session_id"],
            }

        # Ensure either local LLM or Gemini is available (Native Screen OCR provides visual intelligence)
        from core.models import get_installed_chat_models
        has_gemini = bool((req.gemini_api_key or "").strip() or _SESSION_STATE["summarizer"].gemini_api_key)
        installed_chat_models = get_installed_chat_models()

        if not installed_chat_models and not has_gemini:
            raise HTTPException(
                status_code=400,
                detail="No reasoning LLM found. Please ensure Ollama is running with any local chat model (e.g. `ollama run qwen2.5-coder:1.5b` or `gpt-oss:20b`) or configure a Gemini API key.",
            )
        logger.info(
            f"Starting meeting with Native Screen OCR & reasoning engine: "
            f"{installed_chat_models[0] if installed_chat_models else 'Gemini 2.5 Flash'}"
        )

        loop = asyncio.get_running_loop()
        def on_meeting_event(event):
            asyncio.run_coroutine_threadsafe(
                meeting_ws_manager.broadcast({"type": "meeting_event", "data": event}),
                loop
            )

        capture = ScreenCapture(monitor=req.monitor, fps=req.fps)
        pipeline = LivePipeline(
            screen_capture=capture,
            output_dir=_SESSION_STATE["output_dir"],
            event_callback=on_meeting_event,
        )

        session_id = pipeline.start()
        session_dir = str(Path(_SESSION_STATE["output_dir"]) / session_id)

        # Start automated background audio recording (captures speakers/system & mic)
        audio_rec = LiveAudioRecorder()
        await asyncio.to_thread(
            audio_rec.start_recording, session_dir, "audio.wav", start_muted=req.start_muted
        )
        _SESSION_STATE["audio_recorder"] = audio_rec

        _SESSION_STATE["capture"] = capture
        _SESSION_STATE["pipeline"] = pipeline
        _SESSION_STATE["active_session_id"] = session_id

        _prevent_system_sleep()

        logger.info(
            f"[START] Meeting session recording started: {session_id} "
            f"(Monitor: {req.monitor}, Target FPS: {req.fps}, Mic Muted: {req.start_muted}, "
            f"Mic Stream: {audio_rec.mic_audio_active}, System Audio Stream: {audio_rec.system_audio_active})"
        )

        return {
            "status": "recording",
            "session_id": session_id,
            "fps": req.fps,
            "monitor": req.monitor,
            "audio_recording": audio_rec.is_recording,
            "system_audio": audio_rec.system_audio_active,
            "mic_audio": audio_rec.mic_audio_active,
            "audio_warning": audio_rec.warning,
            "mic_muted": req.start_muted,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"[FAILED] Failed to start meeting session: {e}")
        raise HTTPException(
            status_code=500,
            detail="Meeting start failed. Check that DeskMate has Screen Recording and Microphone permission in System Settings > Privacy & Security, then try again.",
        )


@router.get("/status")
async def get_meeting_status():
    """Retrieve real-time meeting capture telemetry including mic mute and audio recording state."""
    pipeline = _SESSION_STATE.get("pipeline")
    audio_rec: Optional[LiveAudioRecorder] = _SESSION_STATE.get("audio_recorder")
    mic_muted = audio_rec.is_muted if audio_rec else False
    audio_recording = audio_rec.is_recording if audio_rec else False

    if pipeline:
        stats = dict(pipeline.stats)
        stats["mic_muted"] = mic_muted
        stats["audio_recording"] = audio_recording
        stats["audio_warning"] = audio_rec.warning if audio_rec else None
        return stats

    return {
        "state": "idle",
        "session_id": None,
        "uptime_seconds": 0.0,
        "frames_processed": 0,
        "events_detected": 0,
        "steps_count": 0,
        "mic_muted": mic_muted,
        "audio_recording": audio_recording,
    }


@router.post("/mute")
async def toggle_mic_mute(req: MuteMeetingRequest):
    """Toggle microphone mute in real time so surrounding voice is strictly blocked when muted."""
    audio_rec: Optional[LiveAudioRecorder] = _SESSION_STATE.get("audio_recorder")
    if audio_rec and audio_rec.is_recording:
        res_muted = audio_rec.set_muted(req.muted)
        logger.info(f"[ACTION] Microphone mute state toggled -> Muted: {res_muted}")
        return {"status": "ok", "muted": res_muted}
    return {"status": "no_active_recorder", "muted": req.muted}


@router.post("/stop")
async def stop_meeting():
    """Stop active meeting recording, finalize screen steps, and finalize audio recording."""
    pipeline = _SESSION_STATE.get("pipeline")
    if not pipeline or pipeline.state != LivePipeline.STATE_RECORDING:
        logger.warning("[WARNING] Stop meeting called but pipeline is not recording.")
        return {"status": "not_recording", "session_id": None}

    session_id = _SESSION_STATE.get("active_session_id", "unknown")
    logger.info(f"[START] Stopping meeting session: {session_id}...")
    try:
        report = pipeline.stop()

        # Finalize automated background audio recording
        audio_rec: Optional[LiveAudioRecorder] = _SESSION_STATE.get("audio_recorder")
        if audio_rec:
            try:
                audio_rec.stop_recording()
            except Exception as e:
                logger.error(f"[WARNING] Error finalizing audio recording for {session_id}: {e}")

        steps_count = len(report.get("steps", []))
        duration = report.get("duration_seconds", 0.0)
        logger.info(
            f"[SUCCESS] Meeting session {session_id} stopped successfully: "
            f"{steps_count} visual steps captured across {duration:.1f}s."
        )

        return {
            "status": "completed",
            "session_id": session_id,
            "steps_count": steps_count,
            "duration_seconds": duration,
        }
    except Exception as e:
        logger.exception(f"[FAILED] Error stopping meeting session {session_id}: {e}")
        raise HTTPException(status_code=500, detail="Stopping the meeting failed")
    finally:
        _allow_system_sleep()


_MAX_AUDIO_BYTES = 500 * 1024 * 1024  # 500 MB

@router.post("/audio/{session_id}")
@router.post("/{session_id}/audio")
async def upload_session_audio(session_id: str, file: UploadFile = File(...)):
    """Receive live audio recording (WAV, WebM, MP3) for Voxtral 4B transcription."""
    base_dir = Path(_SESSION_STATE["output_dir"]).resolve()
    session_dir = (base_dir / session_id).resolve()
    if not session_dir.is_relative_to(base_dir):
        raise HTTPException(status_code=400, detail="Invalid session ID")
    session_dir.mkdir(parents=True, exist_ok=True)

    filename = file.filename or "audio.wav"
    ext = Path(filename).suffix.lower() or ".wav"
    save_path = session_dir / f"audio{ext}"

    try:
        content = await file.read()
        if len(content) > _MAX_AUDIO_BYTES:
            raise HTTPException(status_code=413, detail="Audio file too large")
        await asyncio.to_thread(save_path.write_bytes, content)
        logger.info(f"Saved session audio to {save_path} ({len(content)} bytes)")
        return {"status": "uploaded", "session_id": session_id, "audio_path": str(save_path)}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to save audio for {session_id}: {e}")
        raise HTTPException(status_code=500, detail="Audio upload failed")


@router.post("/summarize")
async def summarize_meeting(req: SummarizeMeetingRequest):
    """Run multimodal Gemini 2.5 Flash / Ollama summarization and generate DeskMate PDF."""
    session_id = req.session_id or _SESSION_STATE.get("active_session_id")
    if not session_id:
        raise HTTPException(status_code=400, detail="No session_id provided or active.")

    if "/" in session_id or "\\" in session_id or ".." in session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID")

    output_dir = Path(_SESSION_STATE["output_dir"])
    report_file = output_dir / f"session_{session_id}.json"
    session_dir = output_dir / session_id

    if not report_file.exists():
        exporter: MeetingExportService = _SESSION_STATE["export_service"]
        recovered = await asyncio.to_thread(exporter.recover_session_report, session_id)
        if recovered is None:
            raise HTTPException(
                status_code=404,
                detail="This meeting's data was not found on disk, so it can't be summarized.",
            )

    t_start = time.time()
    logger.info(f"[START] Summarization requested for session: {session_id}")

    try:
        report_data = await asyncio.to_thread(
            lambda: json.loads(report_file.read_text(encoding="utf-8"))
        )

        steps = report_data.get("steps", [])
        logger.info(f"[STAGE 1/4] Session {session_id} data loaded: {len(steps)} visual steps found.")

        # Stage 1: Audio Prep & Normalization Telemetry
        await meeting_ws_manager.broadcast({
            "type": "post_processing_telemetry",
            "session_id": session_id,
            "stage": "audio_prep",
            "stage_index": 1,
            "total_stages": 4,
            "progress": 0.20,
            "title": "Audio Normalization",
            "detail": "Flushing PCM buffer and converting stream to 16kHz mono WAV...",
        })

        # Check for recorded audio (wav, webm, mp3, m4a)
        audio_path = None
        for cand in ["audio.wav", "audio.webm", "audio.mp3", "audio.m4a"]:
            p = session_dir / cand
            if p.exists():
                audio_path = str(p)
                break

        summarizer: MeetingSummarizer = _SESSION_STATE["summarizer"]
        gemini_key = (req.gemini_api_key or "").strip() or summarizer.gemini_api_key

        transcript_data: Optional[dict[str, Any]] = None
        if audio_path and Path(audio_path).exists():
            logger.info(f"[STAGE 1/4] Audio recording detected ({Path(audio_path).name}). Normalizing and transcribing...")
            # Stage 2: Voxtral 4B Diarization Telemetry
            await meeting_ws_manager.broadcast({
                "type": "post_processing_telemetry",
                "session_id": session_id,
                "stage": "transcription",
                "stage_index": 2,
                "total_stages": 4,
                "progress": 0.45,
                "title": "Voxtral 4B Diarization",
                "detail": "Transcribing speech and translating it into English...",
            })
            try:
                t_trans = time.time()
                extractor = AudioExtractor()
                normalized_path = await asyncio.to_thread(extractor.extract_and_normalize, audio_path)
                logger.info(f"[STAGE 1/4] Audio normalized to 16kHz -> {normalized_path}")
                voxtral: VoxtralSpeechEngine = _SESSION_STATE["voxtral"]
                chunker = ChunkedTranscriber(voxtral)
                transcript_data = await chunker.transcribe_long_file(normalized_path)
                has_speech = bool(transcript_data.get("segments") or transcript_data.get("full_transcript"))
                if not has_speech and gemini_key:
                    logger.info("[STAGE 1/4] Local speech engine yielded no segments; attempting Gemini cloud transcription fallback...")
                    gemini_transcript = await asyncio.to_thread(
                        summarizer.transcribe_audio_with_gemini, normalized_path, gemini_key
                    )
                    if gemini_transcript:
                        transcript_data = gemini_transcript
                        has_speech = bool(gemini_transcript.get("segments"))
                if not has_speech and not transcript_data.get("reason"):
                    transcript_data["status"] = "unavailable"
                    transcript_data["reason"] = "No speech was detected in the recording."
                if has_speech:
                    # Any spoken language -> English, so screen, PDF and email all read in English.
                    transcript_data = await asyncio.to_thread(
                        summarizer.translate_transcript_to_english, transcript_data, gemini_key
                    )
                    segments_count = len(transcript_data.get("segments", []))
                    logger.info(
                        f"[STAGE 1/4] Speech transcription & translation complete in {time.time() - t_trans:.1f}s "
                        f"({segments_count} segments)."
                    )
                else:
                    logger.warning(f"[STAGE 1/4 WARNING] Audio processed but no speech detected: {transcript_data.get('reason')}")
            except Exception as audio_err:
                logger.exception(f"[STAGE 1/4 FAILED] Audio transcription failed for {session_id}: {audio_err}")
                transcript_data = {
                    "full_transcript": "",
                    "segments": [],
                    "status": "unavailable",
                    "reason": "Audio could not be processed, so the report uses screen activity only.",
                }
        else:
            logger.info(f"[STAGE 1/4] No audio file present for session {session_id}. Synthesizing from visual steps only.")
            transcript_data = {
                "full_transcript": "",
                "segments": [],
                "status": "unavailable",
                "reason": "No audio was recorded for this meeting. Check Microphone and Screen Recording permission.",
            }

        # Stage 3: Multimodal Reasoning & Visual Synthesis Telemetry
        try:
            if gemini_key:
                active_engine = f"Gemini ({summarizer.gemini_model})"
            else:
                resolved_model = await asyncio.to_thread(summarizer._resolve_available_ollama_model)
                active_engine = f"Ollama ({resolved_model})"
        except Exception:
            active_engine = "Local AI"

        logger.info(f"[STAGE 2/4] Multimodal reasoning synthesis starting via {active_engine}...")
        t_synth = time.time()

        await meeting_ws_manager.broadcast({
            "type": "post_processing_telemetry",
            "session_id": session_id,
            "stage": "vision_synthesis",
            "stage_index": 3,
            "total_stages": 4,
            "progress": 0.70,
            "title": "Multimodal Synthesis",
            "detail": f"Fusing screen OCR and visual timeline via {active_engine}...",
        })

        loop = asyncio.get_running_loop()
        summary_md, important_steps, step_desc, custom_fields_res = await loop.run_in_executor(
            None,
            lambda: summarizer.summarize_meeting(
                steps,
                transcript_data,
                req.custom_fields,
                gemini_api_key=gemini_key,
            ),
        )
        synth_elapsed = time.time() - t_synth
        logger.info(
            f"[STAGE 2/4] Multimodal reasoning synthesis complete in {synth_elapsed:.1f}s "
            f"(Important Steps: {len(important_steps)}, Custom Fields: {len(custom_fields_res)})."
        )

        # Stage 4: PDF Report Compilation Telemetry
        pdf_path = str(session_dir / f"deskmate_report_{session_id}.pdf")
        logger.info(f"[STAGE 3/4] Compiling executive PDF report -> {pdf_path}...")
        t_pdf = time.time()

        await meeting_ws_manager.broadcast({
            "type": "post_processing_telemetry",
            "session_id": session_id,
            "stage": "pdf_compilation",
            "stage_index": 4,
            "total_stages": 4,
            "progress": 0.90,
            "title": "PDF Compilation",
            "detail": "Rendering high-resolution vector PDF report with redacted host UI...",
        })

        pdf_gen: MeetingPDFGenerator = _SESSION_STATE["pdf_generator"]
        pdf_ok = await loop.run_in_executor(
            None,
            lambda: pdf_gen.generate_report(
                session_id=session_id,
                summary_text=summary_md,
                steps=steps,
                important_step_ids=important_steps,
                step_descriptions=step_desc,
                output_pdf_path=pdf_path,
                specific_fields=req.custom_fields,
                specific_fields_analysis=custom_fields_res,
                transcript_data=transcript_data,
            ),
        )

        if pdf_ok and Path(pdf_path).exists():
            pdf_size_kb = Path(pdf_path).stat().st_size / 1024
            logger.info(f"[STAGE 3/4] Executive PDF report compiled successfully in {time.time() - t_pdf:.1f}s ({pdf_size_kb:.1f} KB).")
        else:
            logger.warning("[STAGE 3/4 WARNING] PDF generator reported failure or output file missing.")

        # Stage 5: Completed Telemetry
        await meeting_ws_manager.broadcast({
            "type": "post_processing_telemetry",
            "session_id": session_id,
            "stage": "completed",
            "stage_index": 4,
            "total_stages": 4,
            "progress": 1.0,
            "title": "Executive Briefing Ready",
            "detail": "Report generated with decisions, action items, and audit trail.",
        })

        meeting_title = extract_meeting_title(summary_md)

        # Update session report with summary
        if meeting_title:
            report_data["title"] = meeting_title
        elif not report_data.get("title") or str(report_data.get("title")).lower() in ("untitled", "meeting session"):
            report_data["title"] = f"Meeting Session {session_id}"
        report_data["summary"] = summary_md
        report_data["important_steps"] = important_steps
        report_data["step_descriptions"] = step_desc
        report_data["custom_fields"] = custom_fields_res
        report_data["transcript"] = transcript_data
        report_data["pdf_path"] = pdf_path if pdf_ok else None

        # Stamp the exact time the PDF was generated so the email can reflect it accurately
        if pdf_ok:
            report_data["pdf_generated_at"] = datetime.now().astimezone().isoformat()

        logger.info(f"[STAGE 4/4] Saving finalized meeting metadata to {report_file.name}...")
        await asyncio.to_thread(
            lambda: report_file.write_text(json.dumps(report_data, indent=2, default=str), encoding="utf-8")
        )

        # Automated retention: purge raw screenshot JPG frames if requested
        if req.purge_raw_assets_after:
            exporter: MeetingExportService = _SESSION_STATE["export_service"]
            await asyncio.to_thread(exporter.purge_raw_assets, session_id)
            logger.info(f"[ACTION] Purged raw screenshot assets for session {session_id} to conserve disk space.")

        # Auto-clean older sessions beyond 10
        await asyncio.to_thread(_SESSION_STATE["export_service"].cleanup_old_sessions, max_keep=MAX_RETAINED_SESSIONS)

        total_elapsed = time.time() - t_start
        logger.info(
            f"[SUCCESS] Summarization pipeline completed for session {session_id} in {total_elapsed:.1f}s! "
            f"Title: \"{meeting_title or 'Untitled'}\" | Important Steps: {len(important_steps)} | PDF: {'Yes' if pdf_ok else 'No'}"
        )

        return {
            "session_id": session_id,
            "title": meeting_title or None,
            "summary": summary_md,
            "important_steps": important_steps,
            "step_descriptions": step_desc,
            "custom_fields": custom_fields_res,
            "transcript": transcript_data,
            "steps": steps,
            "pdf_generated": pdf_ok,
            "pdf_url": f"/api/meeting/pdf/{session_id}" if pdf_ok else None,
        }
    except NothingToSummarizeError as e:
        logger.warning(f"[FAILED] Summarization impossible for session {session_id}: {e}")
        raise HTTPException(status_code=422, detail=str(e))
    except SummarizationUnavailableError as e:
        logger.error(f"[FAILED] AI Summarization unavailable for session {session_id}: {e}")
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception(f"[FAILED] Summarization pipeline failed for session {session_id}: {e}")
        raise HTTPException(
            status_code=500,
            detail="Summarization failed. Your recording is saved, so you can retry from this screen.",
        )


@router.get("/asset/{session_id}/{filename}")
async def get_session_asset(session_id: str, filename: str):
    """Serve session screenshot assets for interactive UI previews."""
    if "/" in filename or "\\" in filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    base_dir = Path(_SESSION_STATE["output_dir"]).resolve()
    session_dir = base_dir / session_id
    app_support_dir = (
        Path.home()
        / "Library"
        / "Application Support"
        / "DeskMate"
        / "output"
        / "sessions"
        / session_id
    )
    cand_paths = [
        session_dir / "assets" / filename,
        session_dir / filename,
        app_support_dir / "assets" / filename,
        app_support_dir / filename,
    ]
    for p in cand_paths:
        if p.exists() and p.is_file():
            media_type = "image/png" if filename.lower().endswith(".png") else "image/jpeg"
            return FileResponse(str(p), media_type=media_type)
    raise HTTPException(status_code=404, detail="Asset not found")


@router.api_route("/pdf/{session_id}", methods=["GET", "HEAD"])
async def download_meeting_pdf(session_id: str):
    """Stream DeskMate-branded executive PDF report for inline preview or download."""
    if "/" in session_id or "\\" in session_id or ".." in session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID")
    output_dir = Path(_SESSION_STATE["output_dir"])
    pdf_path = output_dir / session_id / f"deskmate_report_{session_id}.pdf"
    if not pdf_path.exists():
        app_support_pdf = (
            Path.home()
            / "Library"
            / "Application Support"
            / "DeskMate"
            / "output"
            / "sessions"
            / session_id
            / f"deskmate_report_{session_id}.pdf"
        )
        if app_support_pdf.exists():
            pdf_path = app_support_pdf
    if pdf_path.exists():
        return FileResponse(
            str(pdf_path),
            media_type="application/pdf",
            content_disposition_type="inline",
            filename=f"DeskMate_Meeting_Report_{session_id}.pdf",
        )
    raise HTTPException(status_code=404, detail="Meeting PDF not found. Please summarize first.")


@router.post("/export-drive")
async def export_meeting_to_drive(req: ExportDriveRequest):
    """Upload generated meeting PDF to Google Drive."""
    logger.info(f"[START] Exporting meeting report to Google Drive for session {req.session_id} (Folder: '{req.folder_name}')")
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None,
        exporter.upload_to_drive,
        req.session_id,
        req.folder_name,
    )
    if result.get("status") == "error":
        err_msg = result.get("message", "Upload failed")
        logger.error(f"[FAILED] Google Drive export failed for session {req.session_id}: {err_msg}")
        raise HTTPException(status_code=500, detail=err_msg)
    logger.info(f"[SUCCESS] Meeting report exported to Google Drive for session {req.session_id} -> File ID: {result.get('file_id')}")
    return result


@router.post("/send-email")
async def send_meeting_email(req: SendEmailRequest):
    """Email executive meeting summary and attached PDF via Gmail."""
    logger.info(f"[START] Sending meeting email for session {req.session_id} to '{req.to_email}' (Subject: '{req.subject}')")
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None,
        lambda: exporter.send_email_with_pdf(
            session_id=req.session_id,
            to_email=req.to_email,
            subject=req.subject,
            cc_email=req.cc_email,
            summary_text=None,
            user_name=req.user_name,
            pdf_name=req.pdf_name,
            designation=req.designation,
            sender_email=req.sender_email,
        ),
    )
    if result.get("status") == "error":
        err_msg = result.get("message", "Email failed")
        logger.error(f"[FAILED] Email delivery failed for session {req.session_id}: {err_msg}")
        raise HTTPException(status_code=500, detail=err_msg)
    logger.info(f"[SUCCESS] Email delivered successfully for session {req.session_id} to '{req.to_email}'.")
    return result


@router.post("/cleanup")
async def cleanup_sessions(req: CleanupSessionsRequest):
    """Perform disk cleanup and enforce session retention."""
    logger.info(f"[ACTION] Manual session cleanup requested (max_keep: {req.max_keep})")
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    result = await asyncio.to_thread(exporter.cleanup_old_sessions, max_keep=req.max_keep)
    return result


@router.post("/sync-tasks")
async def sync_action_items_to_tasks(req: SyncTasksRequest):
    """Save extracted meeting action items into DeskMate's SQLite tasks database."""
    items_count = len(req.action_items)
    logger.info(f"[START] Syncing {items_count} action items to tasks database for session {req.session_id}")
    try:
        saved_count = 0
        for item in req.action_items:
            clean_title = re.sub(r'^\s*[-*•]\s*', '', str(item).strip())
            clean_title = re.sub(r'\*{0,2}\[(ACTION ITEM|HIGH PRIORITY|IMPORTANT|TODO|TASK)\]\*{0,2}', '', clean_title, flags=re.IGNORECASE)
            clean_title = clean_title.replace("**", "").replace("*", "").strip()
            if clean_title:
                res = await asyncio.to_thread(
                    db_add_task,
                    title=f"[Meeting {req.session_id}] {clean_title}",
                    priority="high",
                )
                if res and (res.get("id") or res.get("status") == "success"):
                    saved_count += 1

        logger.info(f"[SUCCESS] Created {saved_count}/{items_count} SQLite tasks for session {req.session_id}.")
        return {"status": "synced", "tasks_created": saved_count}
    except Exception as e:
        logger.exception(f"[FAILED] Failed to sync action items to tasks: {e}")
        raise HTTPException(status_code=500, detail="Task sync failed")


@router.get("/sessions")
async def get_saved_sessions():
    """Retrieve metadata list of all locally stored meeting sessions (up to 10 retained)."""
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    sessions = await asyncio.to_thread(exporter.list_sessions)
    return {"status": "ok", "sessions": sessions, "count": len(sessions)}


@router.get("/session/{session_id}")
async def get_session_details(session_id: str):
    """Retrieve complete report JSON for a specific meeting session to restore in UI."""
    if "/" in session_id or "\\" in session_id or ".." in session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID")
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    data = await asyncio.to_thread(exporter.get_session_data, session_id)
    if not data:
        raise HTTPException(status_code=404, detail="Session report not found")
    return {"status": "ok", "session": data}


@router.delete("/session/{session_id}")
async def delete_saved_session(session_id: str):
    """Permanently delete a meeting session and all its disk files."""
    if "/" in session_id or "\\" in session_id or ".." in session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID")
    logger.info(f"[START] Deleting session {session_id} and all on-disk artifacts...")
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    res = await asyncio.to_thread(exporter.delete_session, session_id)
    if res.get("status") == "error":
        logger.error(f"[FAILED] Failed to delete session {session_id}: {res.get('message')}")
        raise HTTPException(status_code=500, detail="Deletion failed")
    logger.info(f"[SUCCESS] Session {session_id} deleted successfully.")
    return res


# Plural alias router (/api/meetings) to support plural endpoint queries gracefully
plural_router = APIRouter(prefix="/api/meetings", tags=["meetings_alias"])


@plural_router.get("/sessions")
async def get_saved_sessions_alias():
    return await get_saved_sessions()


@plural_router.get("/session/{session_id}")
async def get_session_details_alias(session_id: str):
    return await get_session_details(session_id)


@plural_router.get("/status")
async def get_meeting_status_alias():
    return await get_meeting_status()



