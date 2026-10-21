"""
services.meeting_intelligence.export_service — Google Workspace Exporter & Session Retention
=============================================================================================
Provides automated cloud synchronization and disk retention for DeskMate Meeting Intelligence:
  1. Google Drive Upload: Uploads executive PDFs to a "DeskMate Meetings" folder.
  2. Gmail Dispatch: Composes and sends email with executive summary and attached PDF.
  3. Session Retention & Cleanup: Auto-purges older sessions or raw intermediate frames.
"""

from __future__ import annotations

import base64
import json
import logging
from pathlib import Path
import shutil
from datetime import datetime
from email.mime.image import MIMEImage
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any, Optional

from services.meeting_intelligence.email_template import (
    parse_meeting_summary,
    resolve_proper_pdf_name,
    generate_meeting_email_html,
    generate_meeting_email_text,
)

logger = logging.getLogger("deskmate.export_service")


def _resolve_logo_path() -> Optional[Path]:
    base = Path(__file__).resolve().parent
    candidates = [
        base / ".." / ".." / ".." / "deskmate_app" / "assets" / "app_icon.png",
        base / ".." / ".." / "deskmate_app" / "assets" / "app_icon.png",
        Path("deskmate_app/assets/app_icon.png").resolve(),
        Path("../deskmate_app/assets/app_icon.png").resolve(),
    ]
    for p in candidates:
        if p.exists():
            return p.resolve()
    return None


def _friendly_google_error(err: Exception, action: str) -> str:
    """Turn Google client/OAuth exceptions into a message the user can act on."""
    text = str(err)
    lowered = text.lower()
    if isinstance(err, FileNotFoundError) or "credentials.json" in lowered:
        return (
            f"Google account is not connected, so the report could not be {action}. "
            "Open Settings > Google Workspace OAuth, add your Client ID and Secret, then try again."
        )
    if "access_denied" in lowered or "403" in lowered:
        return (
            f"Google blocked the request, so the report could not be {action}. "
            "Add your Gmail address as a Test user in Google Cloud Console > Google Auth Platform > Audience, then try again."
        )
    if "invalid_grant" in lowered or "token" in lowered and "expired" in lowered:
        return f"Your Google sign-in expired, so the report could not be {action}. Try again and sign in when the browser opens."
    return f"The report could not be {action} because Google returned an error. Check your internet connection and try again."


class MeetingExportService:
    """
    Handles Google Drive upload, Gmail mailing with attached PDF,
    and automatic local asset retention.
    """

    def __init__(self, output_dir: str = "output/sessions", max_retained_sessions: int = 10):
        self.output_dir = Path(output_dir)
        self.max_retained_sessions = max_retained_sessions

    def _get_google_service(self, api: str, version: str) -> Any:
        """Obtain authenticated Google API service using DeskMate's shared Google sign-in."""
        from services.personal_assistant.tools import _google_service
        return _google_service(api, version)

    def upload_to_drive(
        self,
        session_id: str,
        folder_name: str = "DeskMate Meetings",
    ) -> dict[str, Any]:
        """
        Uploads the generated meeting PDF to the user's Google Drive.
        Creates a 'DeskMate Meetings' folder if one does not exist.
        """
        session_id = self._safe_session_id(session_id)
        session_dir = self.output_dir / session_id
        pdf_path = session_dir / f"deskmate_report_{session_id}.pdf"

        if not pdf_path.exists():
            return {
                "status": "error",
                "message": "PDF report not found. Please summarize first.",
            }

        try:
            from googleapiclient.http import MediaFileUpload

            svc = self._get_google_service("drive", "v3")

            # 1. Locate or create destination folder
            folder_id = None
            q = f"name = '{folder_name}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
            res = svc.files().list(q=q, fields="files(id, name)").execute()
            folders = res.get("files", [])

            if folders:
                folder_id = folders[0]["id"]
            else:
                folder_meta = {
                    "name": folder_name,
                    "mimeType": "application/vnd.google-apps.folder",
                }
                new_folder = svc.files().create(body=folder_meta, fields="id").execute()
                folder_id = new_folder.get("id")

            # 2. Upload PDF
            file_title = f"DeskMate_Report_{session_id}.pdf"
            file_meta: dict[str, Any] = {"name": file_title}
            if folder_id:
                file_meta["parents"] = [folder_id]

            media = MediaFileUpload(str(pdf_path), mimetype="application/pdf", resumable=True)
            uploaded = (
                svc.files()
                .create(
                    body=file_meta,
                    media_body=media,
                    fields="id, name, webViewLink, webContentLink",
                )
                .execute()
            )

            logger.info(f"PDF uploaded to Google Drive. ID: {uploaded.get('id')}")
            return {
                "status": "success",
                "file_id": uploaded.get("id"),
                "file_name": uploaded.get("name"),
                "view_link": uploaded.get("webViewLink"),
                "download_link": uploaded.get("webContentLink"),
                "folder_name": folder_name,
            }

        except Exception as e:
            logger.exception(f"Failed to upload to Google Drive: {e}")
            return {"status": "error", "message": _friendly_google_error(e, "saved to Google Drive")}

    def send_email_with_pdf(
        self,
        session_id: str,
        to_email: str,
        subject: Optional[str] = None,
        cc_email: Optional[str] = None,
        summary_text: Optional[str] = None,
        user_name: Optional[str] = None,
        pdf_name: Optional[str] = None,
        designation: Optional[str] = None,
        sender_email: Optional[str] = None,
    ) -> dict[str, Any]:
        """
        Sends an email with a high-end, responsive HTML template, structured meeting
        debrief, creator & open-source branding, and an attached, properly-named PDF.
        """
        session_id = self._safe_session_id(session_id)
        session_dir = self.output_dir / session_id
        pdf_path = session_dir / f"deskmate_report_{session_id}.pdf"
        report_path = self.output_dir / f"session_{session_id}.json"

        if not pdf_path.exists():
            return {
                "status": "error",
                "message": "PDF not found. Run summarization first.",
            }

        # 1. Retrieve session data and summary text
        session_data: dict[str, Any] = {}
        if report_path.exists():
            try:
                session_data = json.loads(report_path.read_text(encoding="utf-8"))
            except Exception as e:
                logger.debug(f"Failed to read summary from report {report_path}: {e}")

        body_text = summary_text or session_data.get("summary", "")
        if not body_text:
            body_text = "Please find attached the DeskMate Executive Meeting Intelligence Report."

        try:
            svc = self._get_google_service("gmail", "v1")

            # 2. Resolve Authenticated User Email, Display Name & Designation
            user_email = (sender_email or "").strip()
            user_display_name = (user_name or "").strip()
            user_designation = (designation or "").strip()

            # Attempt to query user profile from Gmail API if email not provided
            if not user_email:
                try:
                    profile = svc.users().getProfile(userId="me").execute()
                    if profile and profile.get("emailAddress"):
                        user_email = profile.get("emailAddress", "")
                except Exception as e:
                    logger.debug(f"Could not retrieve Gmail profile: {e}")

            # Attempt to query sendAs settings for primary email and display name if missing
            if not user_display_name or not user_email:
                try:
                    send_as_resp = svc.users().settings().sendAs().list(userId="me").execute()
                    send_as_list = send_as_resp.get("sendAs", [])
                    for entry in send_as_list:
                        if entry.get("isPrimary") or entry.get("isDefault"):
                            if not user_email:
                                user_email = entry.get("sendAsEmail", "")
                            if not user_display_name and entry.get("displayName"):
                                user_display_name = entry.get("displayName", "")
                            break
                    if not user_email and send_as_list:
                        user_email = send_as_list[0].get("sendAsEmail", "")
                    if not user_display_name and send_as_list and send_as_list[0].get("displayName"):
                        user_display_name = send_as_list[0].get("displayName", "")
                except Exception as e:
                    logger.debug(f"Could not retrieve Gmail sendAs settings: {e}")

            # Fallback for display name if still unknown
            if not user_display_name:
                import getpass
                try:
                    user_display_name = getpass.getuser().replace(".", " ").title()
                except Exception:
                    user_display_name = "DeskMate User"

            # 3. Parse Meeting Content & Determine Clean, Proper PDF Name
            meeting_content = parse_meeting_summary(body_text, session_data)
            proper_pdf_filename = resolve_proper_pdf_name(session_id, pdf_name, subject)

            # 4. Generate Responsive HTML Body & Structured Plain-Text Fallback
            html_body = generate_meeting_email_html(
                session_id=session_id,
                user_name=user_display_name,
                user_email=user_email,
                content=meeting_content,
                pdf_filename=proper_pdf_filename,
                designation=user_designation,
            )
            plain_body = generate_meeting_email_text(
                session_id=session_id,
                user_name=user_display_name,
                user_email=user_email,
                content=meeting_content,
                pdf_filename=proper_pdf_filename,
                designation=user_designation,
            )

            # 5. Build Multipart Email Message
            # Root container: multipart/mixed
            msg = MIMEMultipart("mixed")
            msg["To"] = to_email
            email_subject = subject or f"[DeskMate Intelligence] {meeting_content.title}"
            msg["Subject"] = email_subject

            # Configure From & Reply-To with user email, designation and display name
            sender_label = f"{user_display_name} ({user_designation})" if user_designation else user_display_name
            if user_email:
                if sender_label:
                    msg["From"] = f'"{sender_label}" <{user_email}>'
                    msg["Reply-To"] = f'"{user_display_name}" <{user_email}>'
                else:
                    msg["From"] = user_email
                    msg["Reply-To"] = user_email
            elif sender_label:
                msg["From"] = sender_label

            if cc_email:
                msg["Cc"] = cc_email

            # Related container: multipart/related (contains alternative text/html + inline CID logo)
            related_part = MIMEMultipart("related")

            # Alternative container: multipart/alternative
            alt_part = MIMEMultipart("alternative")
            alt_part.attach(MIMEText(plain_body, "plain", "utf-8"))
            alt_part.attach(MIMEText(html_body, "html", "utf-8"))
            related_part.attach(alt_part)

            # Attach inline DeskMate logo (CID: deskmate_logo)
            logo_path = _resolve_logo_path()
            if logo_path and logo_path.exists():
                try:
                    logo_bytes = logo_path.read_bytes()
                    img_part = MIMEImage(logo_bytes, _subtype="png")
                    img_part.add_header("Content-ID", "<deskmate_logo>")
                    img_part.add_header("Content-Disposition", "inline", filename="app_icon.png")
                    related_part.attach(img_part)
                except Exception as e:
                    logger.debug(f"Failed to attach inline logo image: {e}")

            msg.attach(related_part)

            # 6. Attach PDF Report with proper, professional filename
            pdf_data = pdf_path.read_bytes()
            pdf_part = MIMEApplication(pdf_data, _subtype="pdf")
            pdf_part.add_header(
                "Content-Disposition",
                "attachment",
                filename=proper_pdf_filename,
            )
            msg.attach(pdf_part)

            # 7. Dispatch via Gmail API
            raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
            sent = svc.users().messages().send(userId="me", body={"raw": raw}).execute()

            logger.info(
                f"Email sent successfully with PDF '{proper_pdf_filename}' attached. Message ID: {sent.get('id')}"
            )
            return {
                "status": "success",
                "message_id": sent.get("id"),
                "recipient": to_email,
                "sender": f'"{sender_label}" <{user_email}>' if user_email else sender_label,
                "pdf_name": proper_pdf_filename,
                "subject": email_subject,
            }

        except Exception as e:
            logger.exception(f"Failed to send email with PDF: {e}")
            return {"status": "error", "message": _friendly_google_error(e, "emailed")}

    def cleanup_old_sessions(self, max_keep: Optional[int] = None) -> dict[str, Any]:
        """
        Retention policy: cleans up older session assets to save disk space.
        Retains the latest `max_keep` sessions.
        """
        max_keep = max_keep or self.max_retained_sessions
        if not self.output_dir.exists():
            return {"status": "ok", "deleted_count": 0}

        try:
            # Find all session directories
            session_dirs = []
            for item in self.output_dir.iterdir():
                if item.is_dir() and not item.name.startswith("."):
                    mtime = item.stat().st_mtime
                    session_dirs.append((mtime, item, item.name))

            # Sort oldest first
            session_dirs.sort(key=lambda x: x[0])

            deleted_count = 0
            if len(session_dirs) > max_keep:
                to_delete = session_dirs[: len(session_dirs) - max_keep]
                for _, s_path, s_name in to_delete:
                    try:
                        shutil.rmtree(s_path, ignore_errors=True)
                        json_file = self.output_dir / f"session_{s_name}.json"
                        if json_file.exists():
                            json_file.unlink()
                        deleted_count += 1
                        logger.info(f"Auto-cleaned old session: {s_name}")
                    except Exception as err:
                        logger.warning(f"Failed to delete session {s_name}: {err}")

            return {"status": "ok", "deleted_count": deleted_count, "retained_count": len(session_dirs) - deleted_count}
        except Exception as e:
            logger.error(f"Error during session retention cleanup: {e}")
            return {"status": "error", "message": str(e)}

    def purge_raw_assets(self, session_id: str) -> bool:
        """
        Preserves UI step screenshots (event_*.jpg) so they remain viewable in DeskMate's
        interactive gallery and step inspection modal. Older sessions are purged
        by cleanup_old_sessions.
        """
        logger.info(f"Retaining step screenshots for session: {session_id} (disk managed by retention policy)")
        return True

    @staticmethod
    def _safe_session_id(session_id: str) -> str:
        """Strip path separators to prevent directory traversal."""
        return session_id.replace("/", "").replace("\\", "").replace("..", "").replace("\0", "")

    def delete_session(self, session_id: str) -> dict[str, Any]:
        """
        Permanently deletes a single session directory, all its screenshot frames,
        audio files, PDF report, and session report JSON from local disk.
        """
        try:
            session_id = self._safe_session_id(session_id)
            if not session_id:
                return {"status": "error", "message": "Invalid session ID", "session_id": session_id}
            session_dir = self.output_dir / session_id
            json_file = self.output_dir / f"session_{session_id}.json"

            deleted_dir = False
            deleted_json = False

            if session_dir.exists() and session_dir.is_dir():
                shutil.rmtree(session_dir, ignore_errors=True)
                deleted_dir = True

            if json_file.exists() and json_file.is_file():
                json_file.unlink(missing_ok=True)
                deleted_json = True

            logger.info(f"Deleted meeting session {session_id}: dir={deleted_dir}, json={deleted_json}")
            return {
                "status": "success",
                "session_id": session_id,
                "deleted_directory": deleted_dir,
                "deleted_json": deleted_json,
            }
        except Exception as e:
            logger.exception(f"Failed to delete session {session_id}: {e}")
            return {"status": "error", "message": str(e), "session_id": session_id}

    def get_session_data(self, session_id: str) -> Optional[dict[str, Any]]:
        """
        Retrieves the complete report JSON for a given session.
        """
        session_id = self._safe_session_id(session_id)
        if not session_id:
            return None
        json_file = self.output_dir / f"session_{session_id}.json"
        if not json_file.exists():
            return None

        try:
            with open(json_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            data["session_id"] = session_id
            return data
        except Exception as e:
            logger.error(f"Failed to read session file {json_file}: {e}")
            return None

    def list_sessions(self) -> list[dict[str, Any]]:
        """
        Lists all locally stored meeting sessions sorted newest to oldest.
        Gathers session metadata (title, preview, speaker count, pdf availability).
        """
        if not self.output_dir.exists():
            return []

        sessions: dict[str, dict[str, Any]] = {}

        # 1. Inspect all session_<id>.json report files
        for json_file in self.output_dir.glob("session_*.json"):
            try:
                sid = json_file.stem.replace("session_", "")
                mtime = json_file.stat().st_mtime
                with open(json_file, "r", encoding="utf-8") as f:
                    data = json.load(f)

                custom_fields = data.get("custom_fields") or {}
                topic = custom_fields.get("meeting_topic") or data.get("topic") or data.get("title")

                summary = str(data.get("summary") or "")
                dt_obj = datetime.fromtimestamp(mtime)
                formatted_dt = dt_obj.strftime("%b %d, %Y • %I:%M %p")

                # Extract first meaningful headline or topic for title
                lines = [l.strip().lstrip("#").strip() for l in summary.split("\n") if l.strip()]
                first_meaningful_line = ""
                for line in lines:
                    clean = line.replace("*", "").strip()
                    if clean and not clean.lower().startswith(("meeting summary", "executive summary", "summary:", "overview")):
                        first_meaningful_line = clean
                        break

                if topic and str(topic).strip():
                    title = str(topic).strip()
                elif first_meaningful_line and len(first_meaningful_line) < 80:
                    title = first_meaningful_line
                else:
                    title = f"Meeting • {dt_obj.strftime('%b %d, %Y at %I:%M %p')}"

                preview = summary.replace("#", "").replace("*", "").strip()
                if len(preview) > 160:
                    preview = preview[:160].rstrip() + "..."
                elif not preview:
                    preview = "Recorded meeting session with visual slides and speech transcript."

                transcript = data.get("transcript") or {}
                segments = transcript.get("segments") or []
                unique_speakers = {
                    s.get("speaker") for s in segments if isinstance(s, dict) and s.get("speaker")
                }

                session_dir = self.output_dir / sid
                has_pdf = (session_dir / f"deskmate_report_{sid}.pdf").exists()
                has_audio = (session_dir / "audio.wav").exists() or (session_dir / "meeting_audio.wav").exists()

                sessions[sid] = {
                    "session_id": sid,
                    "title": title,
                    "summary_preview": preview,
                    "created_at": formatted_dt,
                    "timestamp": mtime,
                    "has_summary": bool(summary),
                    "has_pdf": has_pdf,
                    "has_audio": has_audio,
                    "steps_count": len(data.get("steps") or data.get("important_steps") or []),
                    "speakers_count": len(unique_speakers),
                    "dialogue_turns": len(segments),
                }
            except Exception as e:
                logger.warning(f"Error reading session JSON {json_file}: {e}")

        # 2. Inspect session directories without corresponding JSON (if any)
        for item in self.output_dir.iterdir():
            if item.is_dir() and not item.name.startswith("."):
                sid = item.name
                if sid not in sessions:
                    mtime = item.stat().st_mtime
                    has_pdf = (item / f"deskmate_report_{sid}.pdf").exists()
                    has_audio = (item / "audio.wav").exists() or (item / "meeting_audio.wav").exists()
                    sessions[sid] = {
                        "session_id": sid,
                        "title": f"Meeting • {datetime.fromtimestamp(mtime).strftime('%b %d, %Y at %I:%M %p')}",
                        "summary_preview": "Recorded meeting session with visual slides and audio transcript.",
                        "created_at": datetime.fromtimestamp(mtime).strftime("%b %d, %Y • %I:%M %p"),
                        "timestamp": mtime,
                        "has_summary": False,
                        "has_pdf": has_pdf,
                        "has_audio": has_audio,
                        "steps_count": 0,
                        "speakers_count": 0,
                        "dialogue_turns": 0,
                    }

        # Sort newest first
        sorted_list = sorted(sessions.values(), key=lambda s: s.get("timestamp", 0), reverse=True)
        return sorted_list

