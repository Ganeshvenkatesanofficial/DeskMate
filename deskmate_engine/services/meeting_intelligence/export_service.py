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
import os
from pathlib import Path
import shutil
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any, Optional

from settings import DRIVE_TOKEN_PATH, GMAIL_TOKEN_PATH

logger = logging.getLogger("deskmate.export_service")


class MeetingExportService:
    """
    Handles Google Drive upload, Gmail mailing with attached PDF,
    and automatic local asset retention.
    """

    def __init__(self, output_dir: str = "output/sessions", max_retained_sessions: int = 15):
        self.output_dir = Path(output_dir)
        self.max_retained_sessions = max_retained_sessions

    def _get_google_service(self, scopes: list[str], token_filename: str, api: str, version: str) -> Any:
        """Obtain authenticated Google API service using DeskMate's OAuth manager."""
        from services.personal_assistant.tools import _google_service
        return _google_service(scopes, token_filename, api, version)

    def upload_to_drive(
        self,
        session_id: str,
        folder_name: str = "DeskMate Meetings",
    ) -> dict[str, Any]:
        """
        Uploads the generated meeting PDF to the user's Google Drive.
        Creates a 'DeskMate Meetings' folder if one does not exist.
        """
        session_dir = self.output_dir / session_id
        pdf_path = session_dir / f"deskmate_report_{session_id}.pdf"

        if not pdf_path.exists():
            return {
                "status": "error",
                "message": f"PDF report not found at {pdf_path}. Please summarize first.",
            }

        try:
            from googleapiclient.http import MediaFileUpload

            svc = self._get_google_service(
                ["https://www.googleapis.com/auth/drive"],
                DRIVE_TOKEN_PATH,
                "drive",
                "v3",
            )

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
            return {"status": "error", "message": str(e)}

    def send_email_with_pdf(
        self,
        session_id: str,
        to_email: str,
        subject: Optional[str] = None,
        cc_email: Optional[str] = None,
        summary_text: Optional[str] = None,
    ) -> dict[str, Any]:
        """
        Sends an email with the executive meeting summary and attached PDF.
        """
        session_dir = self.output_dir / session_id
        pdf_path = session_dir / f"deskmate_report_{session_id}.pdf"
        report_path = self.output_dir / f"session_{session_id}.json"

        if not pdf_path.exists():
            return {
                "status": "error",
                "message": f"PDF not found at {pdf_path}. Run summarization first.",
            }

        # Retrieve summary if not passed
        body_text = summary_text
        if not body_text and report_path.exists():
            try:
                data = json.loads(report_path.read_text(encoding="utf-8"))
                body_text = data.get("summary", "")
            except Exception as e:
                logger.debug(f"Failed to read summary from report {report_path}: {e}")

        if not body_text:
            body_text = "Please find attached the DeskMate Executive Meeting Intelligence Report."

        try:
            svc = self._get_google_service(
                ["https://www.googleapis.com/auth/gmail.send"],
                GMAIL_TOKEN_PATH,
                "gmail",
                "v1",
            )

            # Build multipart email message
            msg = MIMEMultipart()
            msg["To"] = to_email
            msg["Subject"] = subject or f"[DeskMate Intelligence] Meeting Report — {session_id}"
            if cc_email:
                msg["Cc"] = cc_email

            # Clean body
            email_body = f"""Hello,

Here is your executive meeting report generated by DeskMate AI.

============================================================
EXECUTIVE SUMMARY
============================================================

{body_text}

============================================================
Full visual interaction chronology and action item checklist are
attached as a PDF report.

Generated with DeskMate Meeting Scribe.
"""
            msg.attach(MIMEText(email_body, "plain"))

            # Attach PDF
            pdf_data = pdf_path.read_bytes()
            part = MIMEApplication(pdf_data, _subtype="pdf")
            part.add_header(
                "Content-Disposition",
                "attachment",
                filename=f"DeskMate_Meeting_Report_{session_id}.pdf",
            )
            msg.attach(part)

            raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
            sent = svc.users().messages().send(userId="me", body={"raw": raw}).execute()

            logger.info(f"Email sent successfully with PDF attached. Message ID: {sent.get('id')}")
            return {
                "status": "success",
                "message_id": sent.get("id"),
                "recipient": to_email,
            }

        except Exception as e:
            logger.exception(f"Failed to send email with PDF: {e}")
            return {"status": "error", "message": str(e)}

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
