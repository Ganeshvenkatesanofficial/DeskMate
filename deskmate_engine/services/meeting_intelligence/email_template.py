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
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Optional


LINKEDIN_PROFILE_URL = "https://www.linkedin.com/in/ganesh-venkatesan-3a4516256/"
GITHUB_REPO_URL = "https://github.com/Ganeshvenkatesanofficial/DeskMate"


@dataclass
class StructuredMeetingContent:
    title: str
    overview: str
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
    return cleaned.strip()


def parse_meeting_summary(
    summary_text: str,
    session_data: Optional[dict[str, Any]] = None,
) -> StructuredMeetingContent:
    """
    Parses DeskMate meeting summary markdown and session data into structured sections.
    """
    session_data = session_data or {}
    session_id = session_data.get("session_id", "")

    # 1. Parse Date and Time from session_id or start_time
    date_str = ""
    time_str = ""
    if session_id and len(session_id) >= 15 and "_" in session_id:
        try:
            dt = datetime.strptime(session_id[:15], "%Y%m%d_%H%M%S")
            date_str = dt.strftime("%B %d, %Y")
            time_str = dt.strftime("%I:%M %p")
        except Exception:
            pass

    if not date_str and session_data.get("start_time"):
        try:
            dt = datetime.fromtimestamp(float(session_data["start_time"]))
            date_str = dt.strftime("%B %d, %Y")
            time_str = dt.strftime("%I:%M %p")
        except Exception:
            pass

    if not date_str:
        now = datetime.now()
        date_str = now.strftime("%B %d, %Y")
        time_str = now.strftime("%I:%M %p")

    # 2. Parse Duration
    duration_sec = float(session_data.get("duration_seconds", 0.0))
    if duration_sec > 0:
        mins = int(duration_sec // 60)
        secs = int(duration_sec % 60)
        duration_str = f"{mins}m {secs}s" if mins > 0 else f"{secs}s"
    else:
        duration_str = "Completed"

    steps_count = session_data.get("total_steps") or len(session_data.get("steps", []))

    # 3. Parse Markdown Sections
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
            if "overview" in sec_title or "summary" in sec_title:
                current_section = "overview"
            elif "decision" in sec_title or "outcome" in sec_title or "accomplish" in sec_title:
                current_section = "decisions"
            elif "action" in sec_title or "next step" in sec_title or "todo" in sec_title:
                current_section = "actions"
            elif "highlight" in sec_title or "parameter" in sec_title:
                current_section = "highlights"
            elif "timeline" in sec_title or "detail" in sec_title:
                current_section = "timeline"
            else:
                current_section = "other"
            continue

        if not line_stripped:
            continue

        # Check for explicit action item tags anywhere in the text
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

    # 4. Synthesize 2 to 3 concise, high-standard executive bullet points
    # First check if overview_lines already contained bullet-style points
    raw_bullets = [
        _clean_markdown_text(l)
        for l in overview_lines
        if re.match(r"^[-*•\d\.]\s*", l) and _clean_markdown_text(l)
    ]

    if not raw_bullets:
        # Split overview paragraph into complete sentences
        full_overview = " ".join(
            _clean_markdown_text(l) for l in overview_lines if not l.startswith("#")
        ).strip()
        if full_overview:
            sentences = re.split(r"(?<=[.!?])\s+", full_overview)
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

    # If still empty or 1 point, ensure 2-3 standard points
    if not raw_bullets:
        raw_bullets = [
            "Conducted session covering core workflow parameters, system demonstrations, and key milestone deliverables.",
            "Cross-referenced on-screen visual audit trails with spoken discussion to catalog decisions and assigned action items.",
        ]
    elif len(raw_bullets) == 1:
        raw_bullets.append(
            "Refer to the attached high-resolution DeskMate PDF report for full visual OCR evidence and chronological step audit."
        )

    # Strictly limit to 2 or 3 high-standard points
    overview_bullets = raw_bullets[:3]
    overview_text = " ".join(overview_bullets)

    title = f"Executive Meeting Intelligence Brief — {date_str}"

    return StructuredMeetingContent(
        title=title,
        overview=overview_text,
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
    display_user = html.escape(user_name or "DeskMate User")
    display_email = html.escape(user_email or "")
    display_designation = html.escape((designation or "Lead Analyst & Contributor").strip())
    display_date = html.escape(content.date_str)
    display_time = html.escape(content.time_str)
    display_duration = html.escape(content.duration_str)
    display_overview = html.escape(content.overview)
    display_pdf_name = html.escape(pdf_filename)

    user_initial = (display_user[0] if display_user else "D").upper()

    # Format 2 to 3 pointed overview bullets HTML
    overview_bullets = content.overview_bullets if content.overview_bullets else [content.overview]
    overview_items_html = "".join(
        f'<li style="margin-bottom:8px; line-height:1.5; color:#334155;">{html.escape(bullet)}</li>'
        for bullet in overview_bullets[:3]
    )

    # Format decisions HTML
    decisions_html = ""
    if content.decisions:
        items = "".join(
            f'<li style="margin-bottom:8px; line-height:1.5; color:#334155;">{html.escape(d)}</li>'
            for d in content.decisions[:6]
        )
        decisions_html = f"""
        <div style="margin-top:24px; padding:18px 20px; background-color:#F8FAFC; border:1px solid #E2E8F0; border-radius:10px;">
          <div style="font-size:14px; font-weight:700; color:#1E293B; margin-bottom:12px; display:flex; align-items:center;">
            <span style="display:inline-block; width:8px; height:8px; background-color:#10B981; border-radius:50%; margin-right:8px;"></span>
            Key Decisions & Highlights
          </div>
          <ul style="margin:0; padding-left:20px; font-size:13px;">
            {items}
          </ul>
        </div>
        """

    # Format action items HTML
    actions_html = ""
    if content.action_items:
        items = ""
        for a in content.action_items[:6]:
            tag_badge = ""
            upper = a.upper()
            if "HIGH PRIORITY" in upper or "URGENT" in upper:
                tag_badge = '<span style="display:inline-block; background-color:#FEE2E2; color:#DC2626; font-size:10px; font-weight:700; padding:2px 6px; border-radius:4px; margin-right:6px; letter-spacing:0.5px;">HIGH PRIORITY</span>'
            elif "IMPORTANT" in upper:
                tag_badge = '<span style="display:inline-block; background-color:#FEF3C7; color:#D97706; font-size:10px; font-weight:700; padding:2px 6px; border-radius:4px; margin-right:6px; letter-spacing:0.5px;">IMPORTANT</span>'
            else:
                tag_badge = '<span style="display:inline-block; background-color:#EDE9FE; color:#6A35F5; font-size:10px; font-weight:700; padding:2px 6px; border-radius:4px; margin-right:6px; letter-spacing:0.5px;">ACTION ITEM</span>'

            # Clean any leftover raw bracket text in body
            clean_body = re.sub(r"\[(ACTION ITEM|HIGH PRIORITY|IMPORTANT|TODO|TASK)\]", "", a, flags=re.IGNORECASE).strip()
            items += f"""
            <div style="padding:10px 12px; margin-bottom:8px; background-color:#FFFFFF; border:1px solid #E2E8F0; border-radius:8px; font-size:13px; line-height:1.4; color:#1E293B;">
              {tag_badge} {html.escape(clean_body)}
            </div>
            """

        actions_html = f"""
        <div style="margin-top:20px; padding:18px 20px; background-color:#FAF5FF; border:1px solid #E9D5FF; border-radius:10px;">
          <div style="font-size:14px; font-weight:700; color:#581C87; margin-bottom:12px; display:flex; align-items:center;">
            <span style="display:inline-block; width:8px; height:8px; background-color:#8B5CF6; border-radius:50%; margin-right:8px;"></span>
            Action Items & Next Steps
          </div>
          {items}
        </div>
        """

    author_subline = f'<span style="color:#64748B;">({display_email})</span>' if display_email else ""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>DeskMate AI — Executive Meeting Report</title>
</head>
<body style="margin:0; padding:0; background-color:#F1F5F9; font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; -webkit-font-smoothing:antialiased; color:#0F172A;">
  <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="background-color:#F1F5F9; padding:24px 12px;">
    <tr>
      <td align="center">
        <!-- Main Card Container -->
        <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="max-width:620px; background-color:#FFFFFF; border-radius:14px; overflow:hidden; border:1px solid #E2E8F0; box-shadow:0 4px 12px rgba(15, 23, 42, 0.05);">
          
          <!-- DeskMate Purple Header Bar -->
          <tr>
            <td style="background-color:#0D1117; padding:24px 28px; border-bottom:3px solid #6A35F5;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td valign="middle" style="width:48px;">
                    <img src="cid:deskmate_logo" width="44" height="44" alt="DeskMate Logo" style="display:block; border-radius:10px; border:0; outline:none; background:#161B22;" />
                  </td>
                  <td valign="middle" style="padding-left:14px;">
                    <div style="font-size:19px; font-weight:800; color:#FFFFFF; letter-spacing:-0.3px; line-height:1.2;">
                      DeskMate <span style="color:#8E61FF;">AI</span>
                    </div>
                    <div style="font-size:12px; color:#94A3B8; margin-top:2px;">
                      Autonomous Meeting Intelligence &amp; Desktop Copilot
                    </div>
                  </td>
                  <td align="right" valign="middle">
                    <span style="display:inline-block; background:rgba(106, 53, 245, 0.2); color:#C4B5FD; font-size:10px; font-weight:700; letter-spacing:0.8px; text-transform:uppercase; padding:4px 10px; border-radius:999px; border:1px solid rgba(142, 97, 255, 0.4);">
                      Open Source
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Meeting Metadata Banner -->
          <tr>
            <td style="background-color:#F8FAFC; padding:16px 28px; border-bottom:1px solid #E2E8F0;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td valign="top" style="font-size:12px; color:#64748B;">
                    <strong style="color:#1E293B;">Prepared By:</strong> {display_user} &bull; <span style="color:#6A35F5; font-weight:600;">{display_designation}</span> {author_subline}
                  </td>
                  <td align="right" valign="top" style="font-size:12px; color:#64748B;">
                    📅 {display_date} &bull; ⏱️ {display_duration}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Content Body -->
          <tr>
            <td style="padding:28px;">
              <!-- Title -->
              <div style="font-size:18px; font-weight:700; color:#0F172A; margin-bottom:16px; line-height:1.3;">
                Executive Meeting Intelligence Brief
              </div>

              <!-- Executive Overview Callout (Crisp 2-3 Pointed Bullets) -->
              <div style="background-color:#F5F3FF; border-left:4px solid #6A35F5; padding:16px 18px; border-radius:0 10px 10px 0; margin-bottom:16px;">
                <div style="font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.8px; color:#6A35F5; margin-bottom:10px;">
                  Executive Summary (Key Takeaways)
                </div>
                <ul style="margin:0; padding-left:20px; font-size:13.5px; line-height:1.55; color:#334155;">
                  {overview_items_html}
                </ul>
              </div>

              <!-- Key Decisions -->
              {decisions_html}

              <!-- Action Items -->
              {actions_html}

              <!-- Sender Designation & Signature Card -->
              <div style="margin-top:24px; padding:14px 18px; background-color:#F8FAFC; border:1px solid #E2E8F0; border-radius:10px;">
                <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                  <tr>
                    <td valign="middle" style="width:42px;">
                      <div style="width:36px; height:36px; border-radius:50%; background-color:#6A35F5; color:#FFFFFF; font-weight:700; font-size:14px; text-align:center; line-height:36px;">
                        {user_initial}
                      </div>
                    </td>
                    <td valign="middle" style="padding-left:10px;">
                      <div style="font-size:10.5px; font-weight:700; color:#64748B; text-transform:uppercase; letter-spacing:0.5px;">Dispatched with DeskMate AI by</div>
                      <div style="font-size:13.5px; font-weight:700; color:#0F172A; margin-top:2px;">
                        {display_user} <span style="font-size:12px; font-weight:600; color:#6A35F5;">&bull; {display_designation}</span>
                      </div>
                      <div style="font-size:11.5px; color:#64748B; margin-top:1px;">{display_email}</div>
                    </td>
                  </tr>
                </table>
              </div>

              <!-- Attachment Callout Card -->
              <div style="margin-top:18px; padding:16px 18px; background-color:#F8FAFC; border:1px dashed #CBD5E1; border-radius:10px;">
                <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                  <tr>
                    <td valign="middle" style="width:36px; font-size:24px;">
                      📎
                    </td>
                    <td valign="middle" style="padding-left:10px;">
                      <div style="font-size:13px; font-weight:700; color:#0F172A;">
                        Attached PDF Report: <span style="color:#6A35F5;">{display_pdf_name}</span>
                      </div>
                      <div style="font-size:12px; color:#64748B; margin-top:2px;">
                        Contains high-resolution screen OCR captures, step chronology, and full visual audit trail.
                      </div>
                    </td>
                  </tr>
                </table>
              </div>

            </td>
          </tr>

          <!-- Branding & Open Source Footer -->
          <tr>
            <td style="background-color:#0D1117; padding:24px 28px; border-top:1px solid #1E293B;">
              <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0">
                <tr>
                  <td valign="top" style="color:#94A3B8; font-size:12px; line-height:1.5;">
                    <div style="color:#FFFFFF; font-weight:700; font-size:13px; margin-bottom:4px;">
                      DeskMate AI &bull; Open Source Desktop Intelligence
                    </div>
                    <div>
                      Built with &#x2764;&#xfe0f; by <strong style="color:#F1F5F9;">Ganesh Venkatesan</strong>.
                    </div>
                    <div style="margin-top:6px; font-size:11px; color:#64748B;">
                      Zero cloud telemetry &bull; Local intelligence &bull; Sent via authenticated Google Workspace.
                    </div>
                  </td>
                  <td align="right" valign="middle" style="padding-left:16px;">
                    <a href="{LINKEDIN_PROFILE_URL}" target="_blank" style="display:inline-block; background-color:#0A66C2; color:#FFFFFF; text-decoration:none; padding:8px 14px; border-radius:6px; font-size:12px; font-weight:600; font-family:sans-serif; white-space:nowrap;">
                      Connect on LinkedIn &rarr;
                    </a>
                  </td>
                </tr>
              </table>
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
    Builds a clean, beautifully aligned plain-text version of the email.
    """
    display_desig = f" ({designation})" if designation else ""
    author = f"{user_name}{display_desig} <{user_email}>" if user_email else f"{user_name}{display_desig}"

    decisions_block = ""
    if content.decisions:
        decisions_block = "\nKEY DECISIONS & HIGHLIGHTS\n" + "-" * 40 + "\n"
        for d in content.decisions:
            decisions_block += f"• {d}\n"

    actions_block = ""
    if content.action_items:
        actions_block = "\nACTION ITEMS & NEXT STEPS\n" + "-" * 40 + "\n"
        for a in content.action_items:
            actions_block += f"• {a}\n"

    overview_bullets = content.overview_bullets if content.overview_bullets else [content.overview]
    overview_block = "".join(f"• {b}\n" for b in overview_bullets[:3])

    return f"""============================================================
DESKMATE AI — EXECUTIVE MEETING REPORT
============================================================
Prepared By: {author}
Designation: {designation or 'Lead Contributor'}
Date:        {content.date_str} ({content.time_str})
Duration:    {content.duration_str}
Attachment:  {pdf_filename}
============================================================

EXECUTIVE SUMMARY (KEY TAKEAWAYS)
------------------------------------------------------------
{overview_block}{decisions_block}{actions_block}
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
LinkedIn: {LINKEDIN_PROFILE_URL}
GitHub:   {GITHUB_REPO_URL}

Generated via DeskMate AI Meeting Scribe.
"""
