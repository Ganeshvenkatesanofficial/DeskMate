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
import os
from pathlib import Path
import re
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from pydantic import BaseModel

from core.database import db_add_task
from .ws_meeting_agent import meeting_ws_manager
from services.meeting_intelligence import (
    ScreenCapture,
    LivePipeline,
    VoxtralSpeechEngine,
    AudioExtractor,
    ChunkedTranscriber,
    MeetingSummarizer,
    MeetingPDFGenerator,
    MeetingExportService,
)
from services.meeting_intelligence.transcriber.live_audio_recorder import LiveAudioRecorder

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
    "export_service": MeetingExportService(),
    "active_session_id": None,
    "output_dir": SESSIONS_OUTPUT_DIR,
}


class StartMeetingRequest(BaseModel):
    monitor: int = 1
    fps: float = DEFAULT_SCREEN_FPS


class SummarizeMeetingRequest(BaseModel):
    session_id: Optional[str] = None
    custom_fields: Optional[List[Dict[str, str]]] = None
    purge_raw_assets_after: bool = False


class SyncTasksRequest(BaseModel):
    session_id: str
    action_items: List[str]


class ExportDriveRequest(BaseModel):
    session_id: str
    folder_name: str = "DeskMate Meetings"


class SendEmailRequest(BaseModel):
    session_id: str
    to_email: str
    subject: Optional[str] = None
    cc_email: Optional[str] = None


class CleanupSessionsRequest(BaseModel):
    max_keep: int = 10


class MuteMeetingRequest(BaseModel):
    muted: bool


@router.post("/start")
async def start_meeting(req: StartMeetingRequest):
    """Start screen capture, live meeting event tracking & background audio recording."""
    try:
        if _SESSION_STATE["pipeline"] and _SESSION_STATE["pipeline"].state == LivePipeline.STATE_RECORDING:
            return {
                "status": "already_running",
                "session_id": _SESSION_STATE["active_session_id"],
            }

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

        # Start automated background audio recording (captures earphones/system & mic)
        audio_rec = LiveAudioRecorder()
        audio_rec.start_recording(session_dir, "audio.wav")
        _SESSION_STATE["audio_recorder"] = audio_rec

        _SESSION_STATE["capture"] = capture
        _SESSION_STATE["pipeline"] = pipeline
        _SESSION_STATE["active_session_id"] = session_id

        return {
            "status": "recording",
            "session_id": session_id,
            "fps": req.fps,
            "monitor": req.monitor,
            "audio_recording": True,
            "mic_muted": False,
        }
    except Exception as e:
        logger.exception(f"Failed to start meeting session: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
        return {"status": "ok", "muted": res_muted}
    return {"status": "no_active_recorder", "muted": req.muted}


@router.post("/stop")
async def stop_meeting():
    """Stop active meeting recording, finalize screen steps, and finalize audio recording."""
    pipeline = _SESSION_STATE.get("pipeline")
    if not pipeline or pipeline.state != LivePipeline.STATE_RECORDING:
        return {"status": "not_recording", "session_id": None}

    try:
        report = pipeline.stop()
        session_id = _SESSION_STATE["active_session_id"]

        # Finalize automated background audio recording
        audio_rec: Optional[LiveAudioRecorder] = _SESSION_STATE.get("audio_recorder")
        if audio_rec:
            try:
                audio_rec.stop_recording()
            except Exception as e:
                logger.error(f"Error finalizing audio recording: {e}")

        return {
            "status": "completed",
            "session_id": session_id,
            "steps_count": len(report.get("steps", [])),
            "duration_seconds": report.get("duration_seconds", 0.0),
        }
    except Exception as e:
        logger.exception(f"Error stopping meeting session: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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

    output_dir = Path(_SESSION_STATE["output_dir"])
    report_file = output_dir / f"session_{session_id}.json"
    session_dir = output_dir / session_id

    if not report_file.exists():
        raise HTTPException(status_code=404, detail=f"Session report not found: {report_file}")

    try:
        report_data = await asyncio.to_thread(
            lambda: json.loads(report_file.read_text(encoding="utf-8"))
        )

        steps = report_data.get("steps", [])

        # Check for recorded audio (wav, webm, mp3, m4a)
        audio_path = None
        for cand in ["audio.wav", "audio.webm", "audio.mp3", "audio.m4a"]:
            p = session_dir / cand
            if p.exists():
                audio_path = str(p)
                break

        transcript_data = None
        if audio_path and Path(audio_path).exists():
            extractor = AudioExtractor()
            normalized_path = extractor.extract_and_normalize(audio_path)
            voxtral = _SESSION_STATE["voxtral"]
            chunker = ChunkedTranscriber(voxtral)
            transcript_data = await chunker.transcribe_long_file(normalized_path)

        # Execute multimodal reasoning in thread pool
        summarizer: MeetingSummarizer = _SESSION_STATE["summarizer"]
        loop = asyncio.get_running_loop()
        summary_md, important_steps, step_desc, custom_fields_res = await loop.run_in_executor(
            None,
            summarizer.summarize_meeting,
            steps,
            transcript_data,
            req.custom_fields,
        )

        # Generate DeskMate branded PDF
        pdf_path = str(session_dir / f"deskmate_report_{session_id}.pdf")
        pdf_gen: MeetingPDFGenerator = _SESSION_STATE["pdf_generator"]
        pdf_ok = await loop.run_in_executor(
            None,
            pdf_gen.generate_report,
            session_id,
            summary_md,
            steps,
            important_steps,
            step_desc,
            pdf_path,
            req.custom_fields,
            custom_fields_res,
        )

        # Update session report with summary
        report_data["summary"] = summary_md
        report_data["important_steps"] = important_steps
        report_data["step_descriptions"] = step_desc
        report_data["custom_fields"] = custom_fields_res
        report_data["pdf_path"] = pdf_path if pdf_ok else None

        await asyncio.to_thread(
            lambda: report_file.write_text(json.dumps(report_data, indent=2, default=str), encoding="utf-8")
        )

        # Automated retention: purge raw screenshot JPG frames if requested
        if req.purge_raw_assets_after:
            exporter: MeetingExportService = _SESSION_STATE["export_service"]
            await asyncio.to_thread(exporter.purge_raw_assets, session_id)

        # Auto-clean older sessions beyond 15
        await asyncio.to_thread(_SESSION_STATE["export_service"].cleanup_old_sessions, max_keep=MAX_RETAINED_SESSIONS)

        return {
            "session_id": session_id,
            "summary": summary_md,
            "important_steps": important_steps,
            "step_descriptions": step_desc,
            "custom_fields": custom_fields_res,
            "transcript": transcript_data,
            "steps": steps,
            "pdf_generated": pdf_ok,
            "pdf_url": f"/api/meeting/pdf/{session_id}" if pdf_ok else None,
        }
    except Exception as e:
        logger.exception(f"Summarization error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/asset/{session_id}/{filename}")
async def get_session_asset(session_id: str, filename: str):
    """Serve session screenshot assets for interactive UI previews."""
    base_dir = Path(_SESSION_STATE["output_dir"]).resolve()
    session_dir = base_dir / session_id
    cand_paths = [
        session_dir / "assets" / filename,
        session_dir / filename,
    ]
    for p in cand_paths:
        resolved = p.resolve()
        if resolved.is_relative_to(base_dir) and resolved.is_file():
            return FileResponse(str(resolved), media_type="image/jpeg")
    raise HTTPException(status_code=404, detail="Asset not found")


@router.get("/pdf/{session_id}")
async def download_meeting_pdf(session_id: str):
    """Stream DeskMate-branded executive PDF report."""
    output_dir = Path(_SESSION_STATE["output_dir"])
    pdf_path = output_dir / session_id / f"deskmate_report_{session_id}.pdf"
    if pdf_path.exists():
        return FileResponse(
            str(pdf_path),
            media_type="application/pdf",
            filename=f"DeskMate_Meeting_Report_{session_id}.pdf",
        )
    raise HTTPException(status_code=404, detail="Meeting PDF not found. Please summarize first.")


@router.post("/export-drive")
async def export_meeting_to_drive(req: ExportDriveRequest):
    """Upload generated meeting PDF to Google Drive."""
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None,
        exporter.upload_to_drive,
        req.session_id,
        req.folder_name,
    )
    if result.get("status") == "error":
        raise HTTPException(status_code=500, detail=result.get("message", "Upload failed"))
    return result


@router.post("/send-email")
async def send_meeting_email(req: SendEmailRequest):
    """Email executive meeting summary and attached PDF via Gmail."""
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    loop = asyncio.get_running_loop()
    result = await loop.run_in_executor(
        None,
        exporter.send_email_with_pdf,
        req.session_id,
        req.to_email,
        req.subject,
        req.cc_email,
    )
    if result.get("status") == "error":
        raise HTTPException(status_code=500, detail=result.get("message", "Email failed"))
    return result


@router.post("/cleanup")
async def cleanup_sessions(req: CleanupSessionsRequest):
    """Perform disk cleanup and enforce session retention."""
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    result = await asyncio.to_thread(exporter.cleanup_old_sessions, max_keep=req.max_keep)
    return result


@router.post("/sync-tasks")
async def sync_action_items_to_tasks(req: SyncTasksRequest):
    """Save extracted meeting action items into DeskMate's SQLite tasks database."""
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

        return {"status": "synced", "tasks_created": saved_count}
    except Exception as e:
        logger.exception(f"Failed to sync action items to tasks: {e}")
        raise HTTPException(status_code=500, detail=str(e))


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
    exporter: MeetingExportService = _SESSION_STATE["export_service"]
    res = await asyncio.to_thread(exporter.delete_session, session_id)
    if res.get("status") == "error":
        raise HTTPException(status_code=500, detail="Deletion failed")
    return res


