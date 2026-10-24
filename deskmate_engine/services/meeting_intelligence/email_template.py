"""
services.meeting_intelligence.email_template — DeskMate Executive Email Template Engine
========================================================================================
Generates responsive, branded HTML & Plain-Text emails for meeting reports with:
- Author / Sender attribution ({user_name} <{user_email}>)
- DeskMate AI branding with embedded CID logo
- Structured executive meeting debrief (Overview, Key Decisions, Action Items)
- Attached properly-named PDF callout
- Open-source attribution & Creator LinkedIn profile badge (Ganesh Venkatesan)
"""

from __future__ import annotations

import html
import logging
import os
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional

from services.meeting_intelligence.step_utils import humanize_speaker_tags
from services.meeting_intelligence.summarizer import extract_meeting_title

logger = logging.getLogger("deskmate.meeting.email_template")


LINKEDIN_PROFILE_URL = "https://www.linkedin.com/in/ganesh-venkatesan-3a4516256/"
GITHUB_REPO_URL = "https://github.com/Ganeshvenkatesanofficial/DeskMate"
# The email's summary is the AI's executive overview, cut at a sentence end to this many words.
SUMMARY_MAX_WORDS = 60
NO_SUMMARY_TEXT = "The full meeting report is attached as a PDF."


@dataclass
class StructuredMeetingContent:
    title: str
    overview: str
    brief: str = ""
    overview_bullets: list[str] = field(default_factory=list)
    decisions: list[str] = field(default_factory=list)
    action_items: list[str] = field(default_factory=list)
    highlights: list[str] = field(default_factory=list)
    date_str: str = ""
    time_str: str = ""
    duration_str: str = ""
    steps_count: int = 0


def _clean_markdown_text(text: str) -> str:
    """Strip aggressive markdown formatting while preserving readable text."""
    if not text:
        return ""
    # Strip bold asterisks
    cleaned = re.sub(r"\*\*(.*?)\*\*", r"\1", text)
    cleaned = re.sub(r"\*(.*?)\*", r"\1", cleaned)
    # Strip backticks
    cleaned = re.sub(r"`(.*?)`", r"\1", cleaned)
    # Strip bullet indicators at start of lines
    cleaned = re.sub(r"^\s*[-*•]\s*", "", cleaned)
    return humanize_speaker_tags(cleaned).strip()


def _concise_summary(text: str) -> str:
    """The first sentences of `text` up to SUMMARY_MAX_WORDS words. Adds no words of its own."""
    kept: list[str] = []
    count = 0
    for sentence in re.split(r"(?<=[.!?])\s+", (text or "").strip()):
        words = len(sentence.split())
        if kept and count + words > SUMMARY_MAX_WORDS:
            break
        kept.append(sentence)
        count += words
    words = " ".join(kept).split()
    if len(words) > SUMMARY_MAX_WORDS:  # one very long first sentence
        return " ".join(words[:SUMMARY_MAX_WORDS]).rstrip(",;:- ") + "..."
    return " ".join(words)


def parse_meeting_summary(
    summary_text: str,
    session_data: Optional[dict[str, Any]] = None,
) -> StructuredMeetingContent:
    """
    Parses DeskMate meeting summary markdown and session data into structured sections.
    """
    session_data = session_data or {}
    session_id = session_data.get("session_id", "")

    def _fmt_time(dt_aware: datetime) -> str:
        try:
            return dt_aware.strftime("%-I:%M %p %Z").strip()
        except Exception:
            return dt_aware.strftime("%I:%M %p %Z").lstrip("0").strip()

    now = datetime.now().astimezone()

    # 1. Resolve the time to display — use the exact PDF generation timestamp if available,
    #    then fall back to the PDF file's mtime, then to the current time.
    time_str = ""
    if session_data.get("pdf_generated_at"):
        try:
            pdf_dt = datetime.fromisoformat(session_data["pdf_generated_at"]).astimezone()
            time_str = _fmt_time(pdf_dt)
        except Exception:
            pass

    if not time_str and session_data.get("pdf_path"):
        try:
            pdf_mtime = os.path.getmtime(session_data["pdf_path"])
            pdf_dt = datetime.fromtimestamp(pdf_mtime).astimezone()
            time_str = _fmt_time(pdf_dt)
        except Exception:
            pass

    if not time_str:
        time_str = _fmt_time(now)

    # 2. Parse Date from session_id or start_time, falling back to current date
    date_str = ""
    if session_id and len(session_id) >= 8:
        try:
            dt = datetime.strptime(session_id[:8], "%Y%m%d")
            date_str = dt.strftime("%B %d, %Y")
        except Exception:
            pass

    if not date_str and session_data.get("start_time"):
        try:
            dt = datetime.fromtimestamp(float(session_data["start_time"])).astimezone()
            date_str = dt.strftime("%B %d, %Y")
        except Exception:
            pass

    if not date_str:
        date_str = now.strftime("%B %d, %Y")

    # 3. Parse Duration
    duration_sec = float(session_data.get("duration_seconds", 0.0))
    if duration_sec > 0:
        mins = int(duration_sec // 60)
        secs = int(duration_sec % 60)
        duration_str = f"{mins}m {secs}s" if mins > 0 else f"{secs}s"
    else:
        duration_str = "Completed"

    steps_count = session_data.get("total_steps") or len(session_data.get("steps", []))

    # 4. Parse Markdown Sections
    overview_lines: list[str] = []
    decisions_lines: list[str] = []
    action_item_lines: list[str] = []
    highlight_lines: list[str] = []

    lines = (summary_text or "").strip().splitlines()
    current_section = "overview"

    header_re = re.compile(r"^#{1,4}\s+(.*)", re.IGNORECASE)

    for line in lines:
        line_stripped = line.strip()
        m = header_re.match(line_stripped)
        if m:
            sec_title = m.group(1).lower()
            if "timeline" in sec_title or "detailed action" in sec_title:
                current_section = "timeline"
            elif "overview" in sec_title or "summary" in sec_title:
                current_section = "overview"
            elif "decision" in sec_title or "outcome" in sec_title or "accomplish" in sec_title:
                current_section = "decisions"
            elif "action" in sec_title or "next step" in sec_title or "todo" in sec_title:
                current_section = "actions"
            else:
                current_section = "highlights"
            continue

        if not line_stripped or current_section == "timeline":
            continue

        # Check for explicit action item tags anywhere in the text (never in timeline)
        if re.search(r"\[ACTION ITEM\]|\[HIGH PRIORITY\]|\[IMPORTANT\]", line, re.IGNORECASE):
            action_item_lines.append(line_stripped)
            continue

        if current_section == "overview":
            overview_lines.append(line_stripped)
        elif current_section == "decisions":
            decisions_lines.append(line_stripped)
        elif current_section == "actions":
            action_item_lines.append(line_stripped)
        elif current_section == "highlights":
            highlight_lines.append(line_stripped)

    # Format decisions list
    clean_decisions = []
    for d in decisions_lines:
        c = _clean_markdown_text(d)
        if c:
            clean_decisions.append(c)

    # Format action items
    clean_actions = []
    for a in action_item_lines:
        c = _clean_markdown_text(a)
        if c:
            clean_actions.append(c)

    clean_highlights = [
        _clean_markdown_text(h) for h in highlight_lines if _clean_markdown_text(h)
    ]

    # 5. Extract narrative summary and detailed highlighted key points
    paragraph_parts = []
    bullet_parts = []
    for line in overview_lines:
        clean_l = _clean_markdown_text(line)
        if not clean_l or clean_l.startswith("#"):
            continue
        if re.match(r"^[-*•\d\.]\s*", line.strip()):
            bullet_parts.append(clean_l)
        else:
            paragraph_parts.append(clean_l)

    raw_paragraph = " ".join(paragraph_parts).strip()
    raw_bullets = bullet_parts

    if not raw_bullets and raw_paragraph:
        sentences = re.split(r"(?<=[.!?])\s+", raw_paragraph)
        raw_bullets = [s.strip() for s in sentences if len(s.strip()) > 15]

    # If still fewer than 2 points, pull high-value signals from decisions or highlights
    if len(raw_bullets) < 2 and clean_decisions:
        for d in clean_decisions:
            if d not in raw_bullets:
                raw_bullets.append(d)
            if len(raw_bullets) >= 2:
                break

    if len(raw_bullets) < 2 and clean_highlights:
        for h in clean_highlights:
            if h not in raw_bullets:
                raw_bullets.append(h)
            if len(raw_bullets) >= 2:
                break

    # Dynamically limit detailed bullets up to 5 key points
    overview_bullets = raw_bullets[:5]
    overview_text = raw_paragraph or " ".join(overview_bullets)
    concise_summary = _concise_summary(overview_text)

    meeting_title = str(session_data.get("title") or "").strip() or extract_meeting_title(summary_text)

    title = meeting_title if meeting_title else f"Executive Meeting Intelligence Brief — {date_str}"

    logger.info(
        f"[TEMPLATE] Parsed meeting content: title='{title}', "
        f"{len(clean_decisions)} decisions, {len(clean_actions)} actions, {len(clean_highlights)} highlights."
    )

    return StructuredMeetingContent(
        title=title,
        overview=overview_text,
        brief=concise_summary,
        overview_bullets=overview_bullets,
        decisions=clean_decisions,
        action_items=clean_actions,
        highlights=clean_highlights,
        date_str=date_str,
        time_str=time_str,
        duration_str=duration_str,
        steps_count=steps_count,
    )


def resolve_proper_pdf_name(
    session_id: str,
    custom_pdf_name: Optional[str] = None,
    subject: Optional[str] = None,
) -> str:
    """
    Produces a clean, professional, human-readable filename for the PDF attachment.
    Example: 'DeskMate_Meeting_Executive_Summary_2026-10-20.pdf'
    """
    if custom_pdf_name and custom_pdf_name.strip():
        name = custom_pdf_name.strip()
        if not name.lower().endswith(".pdf"):
            name += ".pdf"
        return re.sub(r"[^a-zA-Z0-9_\-\.]", "_", name)

    # Parse date component
    date_part = ""
    if session_id and len(session_id) >= 8:
        try:
            # session_id like '20261020_094536'
            raw_date = session_id[:8]
            date_part = f"{raw_date[:4]}-{raw_date[4:6]}-{raw_date[6:8]}"
        except Exception:
            date_part = session_id
    else:
        date_part = datetime.now().strftime("%Y-%m-%d")

    # If subject provides a useful topic
    topic_slug = ""
    if subject:
        clean_sub = re.sub(r"\[.*?\]", "", subject)  # Strip bracketed tags
        clean_sub = re.sub(r"[^a-zA-Z0-9\s]", "", clean_sub).strip()
        words = [w for w in clean_sub.split() if w.lower() not in {"deskmate", "intelligence", "meeting", "report", "summary"}]
        if words:
            topic_slug = "_".join(words[:4]).title()

    if topic_slug:
        return f"DeskMate_{topic_slug}_{date_part}.pdf"
    return f"DeskMate_Executive_Meeting_Report_{date_part}.pdf"


def generate_meeting_email_html(
    session_id: str,
    user_name: str,
    user_email: str,
    content: StructuredMeetingContent,
    pdf_filename: str,
    designation: Optional[str] = None,
) -> str:
    """
    Builds a high-end, responsive HTML email template for DeskMate with dynamic
    meeting debrief, author designation, creator branding, and proper PDF attachment.
    """
    logger.info(
        f"[TEMPLATE] Generating HTML email template for session {session_id} "
        f"(Author: '{user_name}', Title: '{content.title}', PDF: '{pdf_filename}')"
    )
    display_user = html.escape(user_name or "DeskMate User")
    display_email = html.escape(user_email or "")
    display_date = html.escape(content.date_str)
    display_time = html.escape(content.time_str)
    display_pdf_name = html.escape(pdf_filename)
    user_initial = (display_user[0] if display_user else "D").upper()
    display_title = html.escape(content.title or "Executive Meeting Intelligence Brief")
    display_brief = html.escape(content.brief or content.overview or NO_SUMMARY_TEXT)

    designation_html = (
        f"""<tr>
                              <td style="color:#64748B; font-weight:600; padding-right:10px; white-space:nowrap; vertical-align:top; padding-top:2px;">Designation:</td>
                              <td style="color:#334155; font-weight:500; vertical-align:top; padding-top:2px;">{html.escape(designation.strip())}</td>
                            </tr>"""
        if designation and designation.strip()
        else ""
    )
    email_html = (
        f"""<tr>
                              <td style="color:#64748B; font-weight:600; padding-right:10px; white-space:nowrap; vertical-align:top; padding-top:2px;">Email:</td>
                              <td style="color:#334155; font-weight:500; vertical-align:top; padding-top:2px;">{display_email}</td>
                            </tr>"""
        if display_email
        else ""
    )

    return f"""<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="color-scheme" content="light" />
  <meta name="supported-color-schemes" content="light" />
  <title>DeskMate AI &mdash; Executive Meeting Report</title>
  <!--[if mso]>
  <noscript>
    <xml><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings></xml>
  </noscript>
  <![endif]-->
  <style>
    @media only screen and (max-width: 620px) {{
      .email-wrapper {{ padding: 12px 8px !important; }}
      .main-card {{ border-radius: 10px !important; }}
      .header-cell {{ padding: 20px 18px !important; }}
      .meta-cell {{ padding: 12px 18px !important; }}
      .body-cell {{ padding: 22px 18px !important; }}
      .footer-cell {{ padding: 20px 18px !important; }}
      .logo-img {{ width: 36px !important; height: 36px !important; }}
      .brand-name {{ font-size: 17px !important; }}
      .meta-row td {{ display: block !important; width: 100% !important; }}
      .meta-date {{ text-align: left !important; margin-top: 6px !important; }}
      .footer-left {{ display: block !important; width: 100% !important; margin-bottom: 16px !important; }}
      .footer-right {{ display: block !important; width: 100% !important; text-align: left !important; }}
      .footer-btn {{ display: block !important; width: 100% !important; box-sizing: border-box !important; margin-bottom: 8px !important; }}
    }}
  </style>
</head>
<body style="margin:0; padding:0; background-color:#EEF2F7; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; -webkit-font-smoothing:antialiased; mso-line-height-rule:exactly;">

  <!-- Outer wrapper -->
  <table class="email-wrapper" role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#EEF2F7; padding:32px 16px;">
    <tr>
      <td align="center">

        <!-- ===== MAIN CARD ===== -->
        <table class="main-card" role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width:600px; background-color:#FFFFFF; border-radius:16px; overflow:hidden; border:1px solid #D1D9E6; box-shadow:0 8px 32px rgba(15,23,42,0.08);">

          <!-- ─── HEADER ─── -->
          <tr>
            <td class="header-cell" style="background-color:#0D1117; padding:26px 32px; border-bottom:3px solid #7C3AED;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <!-- Logo -->
                  <td valign="middle" style="width:50px;">
                    <img class="logo-img" src="cid:deskmate_logo" width="44" height="44" alt="DeskMate" style="display:block; border-radius:10px; border:0; outline:none; background-color:#161B22;" />
                  </td>
                  <!-- Brand -->
                  <td valign="middle" style="padding-left:14px;">
                    <div class="brand-name" style="font-size:20px; font-weight:800; color:#FFFFFF; letter-spacing:-0.4px; line-height:1.15; mso-line-height-rule:exactly;">
                      Desk<span style="color:#A78BFA;">Mate</span> <span style="color:#7C3AED;">AI</span>
                    </div>
                    <div style="font-size:11.5px; color:#8B98A8; margin-top:3px; letter-spacing:0.1px;">
                      Autonomous Meeting Intelligence &amp; Desktop Copilot
                    </div>
                  </td>
                  <!-- Badge -->
                  <td align="right" valign="middle" style="padding-left:10px; white-space:nowrap;">
                    <span style="display:inline-block; background:rgba(124,58,237,0.18); color:#C4B5FD; font-size:10px; font-weight:700; letter-spacing:1px; text-transform:uppercase; padding:5px 12px; border-radius:999px; border:1px solid rgba(167,139,250,0.35);">Open Source</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ─── META BANNER (DATE & TIME) ─── -->
          <tr>
            <td class="meta-cell" style="background-color:#F7F9FC; padding:12px 32px; border-bottom:1px solid #E4E9F0;">
              <table class="meta-row" role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td valign="middle" style="font-size:12px; color:#64748B; line-height:1.5;">
                    <strong style="color:#1E293B; font-weight:700;">Date:</strong>&nbsp;<span style="color:#334155;">{display_date}</span>
                  </td>
                  <td class="meta-date" align="right" valign="middle" style="font-size:12px; color:#64748B; white-space:nowrap; line-height:1.5;">
                    <strong style="color:#1E293B; font-weight:700;">Time:</strong>&nbsp;<span style="color:#334155;">{display_time}</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ─── BODY ─── -->
          <tr>
            <td class="body-cell" style="padding:32px 32px 28px 32px; background-color:#FFFFFF;">

              <!-- Eyebrow label -->
              <div style="font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:1.2px; color:#7C3AED; margin-bottom:10px;">
                &#9679;&nbsp;&nbsp;Executive Meeting Report
              </div>

              <!-- Meeting title -->
              <h1 style="margin:0 0 24px 0; font-size:20px; font-weight:800; color:#0F172A; line-height:1.3; letter-spacing:-0.3px; border-bottom:2px solid #F1F5F9; padding-bottom:16px;">
                {display_title}
              </h1>

              <!-- Summary card -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin-bottom:28px;">
                <tr>
                  <td style="background-color:#F5F3FF; border-left:4px solid #7C3AED; border-radius:0 12px 12px 0; padding:18px 22px;">
                    <!-- Label -->
                    <div style="font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:1px; color:#7C3AED; margin-bottom:10px;">
                      Overall Meeting Summary
                    </div>
                    <!-- Summary text -->
                    <p style="margin:0; font-size:14px; line-height:1.7; color:#1E293B; font-weight:500;">
                      {display_brief}
                    </p>
                  </td>
                </tr>
              </table>

              <!-- Divider -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin-bottom:24px;">
                <tr><td style="border-top:1px solid #F1F5F9; font-size:0; line-height:0;">&nbsp;</td></tr>
              </table>

              <!-- Banner 1: Sender / Dispatch signature card -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#F8FAFC; border:1px solid #E2E8F0; border-radius:12px; margin-bottom:16px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                      <tr>
                        <!-- Avatar -->
                        <td valign="top" style="width:40px;">
                          <div style="width:40px; height:40px; border-radius:10px; background-color:#EDE9FE; color:#7C3AED; font-weight:800; font-size:16px; text-align:center; line-height:40px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; border:1px solid rgba(124,58,237,0.18);">
                            {user_initial}
                          </div>
                        </td>
                        <!-- Details -->
                        <td valign="top" style="padding-left:16px;">
                          <div style="font-size:10.5px; font-weight:700; color:#7C3AED; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:6px;">
                            Dispatched via DeskMate AI
                          </div>
                          <table role="presentation" border="0" cellspacing="0" cellpadding="0" style="font-size:12.5px; line-height:1.5;">
                            <tr>
                              <td style="color:#64748B; font-weight:600; padding-right:10px; white-space:nowrap; vertical-align:top;">Sender:</td>
                              <td style="color:#0F172A; font-weight:700; vertical-align:top;">{display_user}</td>
                            </tr>
                            {designation_html}
                            {email_html}
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Banner 2: PDF attachment callout -->
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#F8FAFC; border:1px solid #E2E8F0; border-radius:12px;">
                <tr>
                  <td style="padding:18px 20px;">
                    <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                      <tr>
                        <!-- Icon -->
                        <td valign="top" style="width:40px;">
                          <div style="width:40px; height:40px; border-radius:10px; background-color:#EDE9FE; color:#7C3AED; font-weight:700; font-size:18px; text-align:center; line-height:40px; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; border:1px solid rgba(124,58,237,0.18);">
                            &#128206;
                          </div>
                        </td>
                        <!-- Details -->
                        <td valign="top" style="padding-left:16px;">
                          <div style="font-size:10.5px; font-weight:700; color:#7C3AED; text-transform:uppercase; letter-spacing:0.8px; margin-bottom:6px;">
                            Attached PDF Report
                          </div>
                          <table role="presentation" border="0" cellspacing="0" cellpadding="0" style="font-size:12.5px; line-height:1.5;">
                            <tr>
                              <td style="color:#64748B; font-weight:600; padding-right:10px; white-space:nowrap; vertical-align:top;">File:</td>
                              <td style="color:#0F172A; font-weight:700; vertical-align:top; word-break:break-all;">{display_pdf_name}</td>
                            </tr>
                            <tr>
                              <td style="color:#64748B; font-weight:600; padding-right:10px; white-space:nowrap; vertical-align:top; padding-top:2px;">Details:</td>
                              <td style="color:#334155; font-weight:500; vertical-align:top; padding-top:2px;">Includes screen captures, step chronology, OCR content, and full visual audit trail.</td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

            </td>
          </tr>

          <!-- ─── FOOTER ─── -->
          <tr>
            <td class="footer-cell" style="background-color:#0D1117; padding:26px 32px; border-top:1px solid #1C2433;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <!-- Left: branding & attribution -->
                  <td class="footer-left" valign="middle" style="color:#8B98A8; font-size:12px; line-height:1.6;">
                    <div style="color:#F1F5F9; font-weight:800; font-size:13.5px; letter-spacing:-0.2px; margin-bottom:5px;">
                      DeskMate <span style="color:#A78BFA;">AI</span>
                    </div>
                    <div style="color:#8B98A8; font-size:11.5px; margin-bottom:8px;">
                      Open Source Autonomous Meeting Intelligence
                    </div>
                    <div style="color:#64748B; font-size:11px; margin-bottom:10px;">
                      Built with &#10084;&#65039; by&nbsp;<span style="color:#C4B5FD; font-weight:700;">Ganesh Venkatesan</span>
                    </div>
                    <div style="font-size:11px; color:#4B5563;">
                      Zero cloud telemetry &bull; Local processing &bull; Google Workspace secured
                    </div>
                  </td>
                  <!-- Right: CTA buttons -->
                  <td class="footer-right" align="right" valign="middle" style="padding-left:20px; white-space:nowrap;">
                    <!-- GitHub button -->
                    <a class="footer-btn" href="{GITHUB_REPO_URL}" target="_blank" style="display:inline-block; width:184px; box-sizing:border-box; background-color:#1C2433; color:#C4B5FD; text-decoration:none; padding:10px 14px; border-radius:8px; font-size:12px; font-weight:700; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; border:1px solid #374151; text-align:center; line-height:16px; vertical-align:middle; white-space:nowrap; margin-bottom:8px;">
                      <svg width="14" height="14" viewBox="0 0 16 16" fill="#C4B5FD" style="vertical-align:-2px; margin-right:6px; display:inline-block;" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path></svg>GitHub Repo &rarr;
                    </a>
                    <br />
                    <!-- LinkedIn button -->
                    <a class="footer-btn" href="{LINKEDIN_PROFILE_URL}" target="_blank" style="display:inline-block; width:184px; box-sizing:border-box; background-color:#0A66C2; color:#FFFFFF; text-decoration:none; padding:10px 14px; border-radius:8px; font-size:12px; font-weight:700; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; border:1px solid #0A66C2; text-align:center; line-height:16px; vertical-align:middle; white-space:nowrap;">
                      <svg width="14" height="14" viewBox="0 0 16 16" fill="#FFFFFF" style="vertical-align:-2px; margin-right:6px; display:inline-block;" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M0 1.146C0 .513.526 0 1.175 0h13.65C15.474 0 16 .513 16 1.146v13.708c0 .633-.526 1.146-1.175 1.146H1.175C.526 16 0 15.487 0 14.854V1.146zm4.943 12.248V6.169H2.542v7.225h2.401zm-1.2-8.212c.837 0 1.358-.554 1.358-1.248-.015-.709-.52-1.248-1.342-1.248-.822 0-1.359.54-1.359 1.248 0 .694.521 1.248 1.327 1.248h.016zm4.908 8.212V9.359c0-.216.016-.432.08-.586.173-.431.568-.878 1.232-.878.869 0 1.216.662 1.216 1.634v3.865h2.401V9.25c0-2.22-1.184-3.252-2.764-3.252-1.274 0-1.845.7-2.165 1.193v.025h-.016a5.54 5.54 0 0 1 .016-.025V6.169h-2.4c.03.678 0 7.225 0 7.225h2.4z"></path></svg>Connect on LinkedIn &rarr;
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

        </table>
        <!-- /MAIN CARD -->

        <!-- Fine print -->
        <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width:600px; margin-top:14px;">
          <tr>
            <td style="text-align:center; font-size:10.5px; color:#94A3B8; line-height:1.6; padding:0 16px;">
              This email was generated and dispatched automatically by <strong>DeskMate AI Meeting Scribe</strong>.<br />
              Report and attachments are intended solely for the addressed recipient.
            </td>
          </tr>
        </table>

      </td>
    </tr>
  </table>

</body>
</html>
"""


def generate_meeting_email_text(
    session_id: str,
    user_name: str,
    user_email: str,
    content: StructuredMeetingContent,
    pdf_filename: str,
    designation: Optional[str] = None,
) -> str:
    """
    Builds a clean, beautifully aligned plain-text version of the email containing only
    the short overall meeting summary.
    """
    logger.info(f"[TEMPLATE] Generating plain-text email fallback for session {session_id}")
    summary_text = (content.brief or content.overview or NO_SUMMARY_TEXT).strip()
    date_display = content.date_str
    time_display = content.time_str
    email_line = f"\nEmail:       {user_email}" if user_email else ""
    designation_line = f"\nDesignation: {designation.strip()}" if designation and designation.strip() else ""

    return f"""============================================================
DESKMATE AI — EXECUTIVE MEETING REPORT
============================================================
Date:        {date_display}
Time:        {time_display}
Duration:    {content.duration_str}
Attachment:  {pdf_filename}
============================================================

OVERALL MEETING SUMMARY
------------------------------------------------------------
{summary_text}

============================================================
DISPATCH DETAILS
============================================================
Sender:      {user_name or 'DeskMate User'}{designation_line}{email_line}
Dispatched automatically via DeskMate AI Meeting Scribe.

============================================================
ATTACHED REPORT
============================================================
The complete visual audit report, high-resolution slide/screen OCR
captures, and complete discussion chronology have been attached:
File: {pdf_filename}

============================================================
DESKMATE AI — OPEN SOURCE MEETING INTELLIGENCE
============================================================
Built with passion by Ganesh Venkatesan.
GitHub:   {GITHUB_REPO_URL}
LinkedIn: {LINKEDIN_PROFILE_URL}

Generated via DeskMate AI Meeting Scribe.
"""
