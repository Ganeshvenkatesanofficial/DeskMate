"""
services.meeting_intelligence.pdf_generator — Production Executive PDF Layout Engine
===================================================================================
DeskMate branded PDF generator (fpdf2).
Compiles executive markdown summaries, key visual interaction moments, dynamic user
requirements, and action items into a report with Primer typography and #6A35F5 palette.
"""

import os
import re
import hashlib
import logging
import datetime
from pathlib import Path
from typing import Optional, Any
from fpdf import FPDF

from services.meeting_intelligence.step_utils import (
    GENERIC_STEP_SUMMARIES,
    clean_dynamic_sections,
    fallback_step_description,
    is_host_ui_step,
    readable_step_title,
    resolve_screenshot_path,
    spoken_quotes_near,
)

logger = logging.getLogger("deskmate.pdf_generator")

# ── DeskMate AI Color Palette (GitHub Primer Purple & Dark Slate) ────────────
_DESKMATE_PRIMARY = (106, 53, 245)      # #6A35F5 — Signature DeskMate Purple
_DESKMATE_DEEP = (22, 27, 34)           # #161B22 — GitHub Primer Dark Slate
_DESKMATE_DARK = (13, 17, 23)           # #0D1117 — Dark Heading Text
_WHITE = (255, 255, 255)
_BODY_TEXT = (55, 65, 81)               # #374151 — Crisp Charcoal Body Text
_MUTED_TEXT = (107, 114, 128)           # #6B7280 — Muted Secondary Text
_LIGHT_BG = (245, 243, 255)             # #F5F3FF — Light Lavender Tint Background
_CARD_BG = (249, 250, 251)              # #F9FAFB — Clean Neutral Card Background
_DIVIDER = (226, 232, 240)              # #E2E8F0 — Subtle Divider
_WARNING = (217, 119, 6)                # #D97706 — Amber / Important Note
_URGENT = (220, 38, 38)                 # #DC2626 — Critical / High Priority Red
_CONTEXT_ACCENT = (14, 116, 144)        # #0E7490 — Informational Teal for Context References

# ── Page Constants ────────────────────────────────────────────────────────────
_LEFT_MARGIN = 15
_RIGHT_MARGIN = 15
_CONTENT_WIDTH = 210 - _LEFT_MARGIN - _RIGHT_MARGIN   # 180mm
_IMG_WIDTH = 138                                      # Balanced, elegant screenshot width (avoids pushing entire cards to new pages)
_MAX_IMG_HEIGHT = 76.0                                # Max image height cap to ensure 2 cards fit per page
_IMG_X = _LEFT_MARGIN + (_CONTENT_WIDTH - _IMG_WIDTH) / 2


def _resolve_logo_path() -> str:
    """Find DeskMate light theme brand logo across development and packaged application paths."""
    candidates = [
        Path(__file__).resolve().parent / "static" / "deskmate_logo.png",
        Path.home() / "Library" / "Application Support" / "DeskMate" / "static" / "deskmate_logo.png",
        Path(__file__).resolve().parent.parent.parent.parent / "deskmate_app" / "assets" / "app_icon_light.png",
        Path("deskmate_app/assets/app_icon_light.png").resolve(),
        Path(__file__).resolve().parent.parent.parent.parent / "deskmate_app" / "assets" / "app_icon.png",
        Path("deskmate_app/assets/app_icon.png").resolve(),
        Path.home() / "AppData" / "Roaming" / "DeskMate" / "static" / "deskmate_logo.png",
    ]
    for p in candidates:
        try:
            if p.exists() and p.is_file():
                return str(p.resolve())
        except Exception:
            pass
    return ""


_LOGO_PATH = _resolve_logo_path()

# Core PDF fonts are Latin-1 only; map common Unicode punctuation instead of dropping it.
_UNICODE_MAP = str.maketrans({
    "\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"',
    "\u2013": "-", "\u2014": "-", "\u2026": "...",
    "\u2192": "->", "\u2190": "<-", "\u2194": "<->",
    "\u2022": "-", "\u2023": "-", "\u25cf": "-", "\u25cb": "o",
    "\u2713": "[x]", "\u2714": "[x]", "\u2717": "[ ]", "\u2718": "[ ]",
    "\u00a0": " ", "\u200b": "", "\u200c": "", "\u200d": "", "\ufeff": "", "\u00ad": "",
    "\u2032": "'", "\u2033": '"',
    "\u20b9": "INR", "\u20ac": "EUR", "\u2122": "(TM)",
    "\u2248": "~", "\u2260": "!=", "\u2264": "<=", "\u2265": ">=", "\u221e": "inf",
})


_EXTRA_SPACES = re.compile(r"[ \t]{2,}")


def _to_pdf_text(text: Any) -> str:
    """Any value -> text the core PDF fonts can draw (unsupported scripts such as Tamil are dropped)."""
    if text is None:
        return ""
    latin = str(text).translate(_UNICODE_MAP).encode("latin-1", "ignore").decode("latin-1")
    return _EXTRA_SPACES.sub(" ", latin)


# Lowest y (mm) content may reach before a manual page break.
_PAGE_BOTTOM_Y = 270
# How the summarizer marks researched context inside a step description (see the prompt).
_CONTEXT_KINDS = r"(?:Context Reference|Domain Context|Technical Context)"
_CONTEXT_PATTERNS = (
    re.compile(r"\[" + _CONTEXT_KINDS + r":\s*(.*?)\]", re.IGNORECASE | re.DOTALL),
    re.compile(r"\*\*\[" + _CONTEXT_KINDS + r"\]\*\*:\s*(.*)", re.IGNORECASE | re.DOTALL),
    re.compile(r"\*\(" + _CONTEXT_KINDS + r":\s*(.*?)\)\*", re.IGNORECASE | re.DOTALL),
)
_CONTEXT_LABELS = ("CONTEXT REFERENCE", "TECHNICAL CONTEXT", "DOMAIN CONTEXT", "EXTERNAL CONTEXT")
# Top and bottom padding (mm) inside the description card under each screenshot.
_DESC_BOX_PADDING = 4.0


class MeetingReportPDF(FPDF):
    """Custom FPDF layout with rich DeskMate AI branding on every page."""

    def normalize_text(self, text: str) -> str:
        # Single choke point: no caller can crash the PDF with unsupported characters.
        return super().normalize_text(_to_pdf_text(text))

    def header(self):
        # ─── Solid Pure White Page Canvas ─────────────────────────────
        # Guarantees opaque white paper background across all PDF viewers,
        # print drivers, and operating system dark mode themes.
        self.set_fill_color(*_WHITE)
        self.rect(0, 0, 210, 297, 'F')

        # ─── Sleek minimal header on all pages ────────────────────────
        logo_path = _LOGO_PATH
        if logo_path:
            try:
                # DeskMate Logo icon on the left (medium size, 11mm wide)
                self.image(logo_path, x=_LEFT_MARGIN, y=4.5, w=11)
                self.set_font('Helvetica', 'B', 11)
                self.set_text_color(*_DESKMATE_PRIMARY)
                self.set_xy(_LEFT_MARGIN + 13, 7.5)
                self.cell(40, 5, 'DeskMate AI', 0, 0, 'L')
            except Exception:
                self.set_font('Helvetica', 'B', 11)
                self.set_text_color(*_DESKMATE_PRIMARY)
                self.set_xy(_LEFT_MARGIN, 7.5)
                self.cell(40, 5, 'DeskMate AI', 0, 0, 'L')
        else:
            self.set_font('Helvetica', 'B', 11)
            self.set_text_color(*_DESKMATE_PRIMARY)
            self.set_xy(_LEFT_MARGIN, 7.5)
            self.cell(40, 5, 'DeskMate AI', 0, 0, 'L')

        # Header Title on the right
        self.set_font('Helvetica', 'B', 12)
        self.set_text_color(*_DESKMATE_DEEP)
        self.set_xy(_LEFT_MARGIN, 7.5)
        self.cell(_CONTENT_WIDTH, 5, 'Meeting Intelligence Report', 0, 0, 'R')

        # Thin accent line below header in DeskMate signature purple
        self.set_fill_color(*_DESKMATE_PRIMARY)
        self.rect(_LEFT_MARGIN, 18.5, _CONTENT_WIDTH, 0.4, 'F')

        # Reset body cursor
        self.set_y(23)
        self.set_text_color(*_BODY_TEXT)

    def footer(self):
        self.set_y(-16)

        # ─── Thin accent line above footer ───────────────────────────
        self.set_fill_color(*_DIVIDER)
        self.rect(_LEFT_MARGIN, self.get_y() - 2, _CONTENT_WIDTH, 0.4, 'F')

        self.set_font('Helvetica', '', 7.5)
        self.set_text_color(*_MUTED_TEXT)
        self.cell(90, 10, f'Page {self.page_no()}/{{nb}}', 0, 0, 'L')
        self.set_font('Helvetica', 'I', 7.5)
        self.cell(90, 10, 'Generated by DeskMate AI  |  Meeting Intelligence', 0, 0, 'R')


class MeetingPDFGenerator:
    """Compiles rich markdown summaries and key screenshots into a premium DeskMate PDF report."""

    def generate_report(
        self,
        session_id: str,
        summary_text: str,
        steps: list,
        important_step_ids: list,
        step_descriptions: dict,
        output_pdf_path: str,
        specific_fields: list = None,
        specific_fields_analysis: dict = None,
        transcript_data: Optional[dict] = None,
    ) -> bool:
        try:
            logger.info(f"Generating DeskMate PDF report for session {session_id}...")

            steps = [s for s in (steps or []) if isinstance(s, dict)]
            step_descriptions = step_descriptions if isinstance(step_descriptions, dict) else {}
            specific_fields = [f for f in (specific_fields or []) if isinstance(f, dict)]
            specific_fields_analysis = specific_fields_analysis if isinstance(specific_fields_analysis, dict) else {}

            pdf = MeetingReportPDF()
            pdf.alias_nb_pages()
            pdf.set_left_margin(_LEFT_MARGIN)
            pdf.set_right_margin(_RIGHT_MARGIN)
            pdf.add_page()
            pdf.set_auto_page_break(auto=True, margin=22)

            # ─── Extract Meeting Title & Clean Summary ────────────────────
            raw_s = (summary_text or "").strip()
            # Strip markdown code fences or JSON wrapper artifacts
            if raw_s.startswith("```"):
                raw_s = re.sub(r"^```(?:json|markdown)?\s*", "", raw_s).strip()
                raw_s = re.sub(r"\s*```$", "", raw_s).strip()
            raw_s = re.sub(r'^\s*\{\s*"SUMMARY":\s*', "", raw_s).strip()
            raw_s = re.sub(r'^\s*"SUMMARY":\s*', "", raw_s).strip()

            # Strip delimiters like ===SUMMARY=== or ### SUMMARY or SUMMARY
            raw_s = re.sub(
                r"^(?:={3,}\s*SUMMARY\s*={3,}|#{1,4}\s*SUMMARY\s*|SUMMARY\s*:?\s*)\n*",
                "",
                raw_s,
                flags=re.IGNORECASE,
            ).strip()

            title_match = re.search(r"^#{1,3}\s+(.*?)$", raw_s, re.MULTILINE)
            raw_title_matched = title_match.group(1).strip() if title_match else ""
            doc_title = re.sub(r"[*_`#]", "", raw_title_matched).strip() if raw_title_matched else "Executive Meeting Intelligence Report"
            doc_title = re.sub(r"^(?:meeting\s+title|title|topic)\s*:\s*", "", doc_title, flags=re.IGNORECASE).strip()
            if not doc_title or doc_title.lower().startswith(("summary", "untitled", "executive meeting")):
                doc_title = "Executive Meeting Intelligence Report"

            if raw_title_matched and doc_title != "Executive Meeting Intelligence Report":
                clean_summary = re.sub(r"^#{1,3}\s+" + re.escape(raw_title_matched) + r"\s*\n*", "", raw_s, flags=re.MULTILINE).strip()
            else:
                clean_summary = re.sub(r"^#{1,3}\s+.*?\n+", "", raw_s, count=1).strip()

            # Dynamically prune any section with empty body or boilerplate ('None', 'N/A', 'Not discussed')
            clean_summary = clean_dynamic_sections(clean_summary)

            # ─── Hero Title Block ─────────────────────────────────────────
            pdf.set_y(24)
            pdf.set_font('Helvetica', 'B', 17)
            pdf.set_text_color(*_DESKMATE_DARK)
            pdf.multi_cell(_CONTENT_WIDTH, 7.5, self._make_safe(doc_title))
            pdf.ln(3)

            # ─── Metadata block ──────────────────────────────────────────
            self._render_metadata_block(pdf, session_id, steps, important_step_ids)

            # ─── Executive Summary ───────────────────────────────────────
            self._render_section_header(pdf, 'Executive Summary & Analysis')
            self._render_markdown_body(pdf, clean_summary)
            pdf.ln(4)

            # ─── Key Visual Moments ──────────────────────────────────────
            if steps:
                first_card_h = self._get_first_card_height(
                    pdf, steps, important_step_ids, step_descriptions, transcript_data=transcript_data
                )
                rem_h = _PAGE_BOTTOM_Y - pdf.get_y()
                # If there's less space than needed for header + first card, or if page is already past mid-point (>145mm),
                # start the visual moments section cleanly at the top of the next page to avoid awkward blank gaps
                if rem_h < (16 + first_card_h) and pdf.get_y() > 145:
                    pdf.add_page()
                self._render_section_header(pdf, 'Key Visual Interaction Moments')
                self._render_screenshots(
                    pdf, steps, important_step_ids, step_descriptions, transcript_data=transcript_data, session_id=session_id
                )

            # ─── Dynamic Specific Fields (Custom User Requirements) ──────
            if specific_fields and specific_fields_analysis:
                for sf in specific_fields:
                    name = str(sf.get("name") or "")
                    instruction = str(sf.get("instruction") or "")

                    # Fetch analysis content
                    analysis_data = specific_fields_analysis.get(name)
                    if not analysis_data:
                        # Fallback case-insensitive
                        analysis_data = next(
                            (v for k, v in specific_fields_analysis.items() if str(k).lower() == name.lower()), None
                        )

                    if not analysis_data:
                        continue

                    content = ""
                    relevant_steps = []

                    if isinstance(analysis_data, dict):
                        content = analysis_data.get("content", "")
                        relevant_steps = analysis_data.get("relevant_steps", [])
                    elif isinstance(analysis_data, str):
                        content = analysis_data

                    if not content or not content.strip():
                        continue

                    # Force a page break for each custom field
                    pdf.add_page()

                    # Section Header
                    self._render_section_header(pdf, f"Requested Analysis: {name}")

                    # Render Instruction Context
                    pdf.set_font('Helvetica', 'I', 8.5)
                    pdf.set_text_color(*_MUTED_TEXT)
                    pdf.set_x(_LEFT_MARGIN)
                    pdf.cell(_CONTENT_WIDTH, 5, self._make_safe(f"Instruction: {instruction}"), 0, 1)
                    pdf.ln(4)

                    # Render generated body text
                    self._render_markdown_body(pdf, content)
                    pdf.ln(6)

                    # Render relevant evidence screenshots
                    if relevant_steps:
                        str_relevant_steps = [str(sid).strip() for sid in relevant_steps]

                        has_screenshots = False
                        for step in steps:
                            step_id_val = str(step.get("step_id", ""))
                            if step_id_val in str_relevant_steps or f"step_{step_id_val}" in str_relevant_steps:
                                has_screenshots = True
                                break

                        if has_screenshots:
                            # Force a page break if the header and first screenshot card won't fit together
                            first_card_h = self._get_first_card_height(
                                pdf, steps, str_relevant_steps, step_descriptions, transcript_data=transcript_data
                            )
                            if pdf.get_y() + 14 + first_card_h > _PAGE_BOTTOM_Y:
                                pdf.add_page()

                            pdf.ln(4)
                            pdf.set_font('Helvetica', 'B', 10.5)
                            pdf.set_text_color(*_DESKMATE_DEEP)
                            pdf.set_x(_LEFT_MARGIN)
                            pdf.cell(_CONTENT_WIDTH, 6, "Relevant Visual Evidence", 0, 1)
                            pdf.ln(4)

                            self._render_screenshots(
                                pdf, steps, str_relevant_steps, step_descriptions, transcript_data=transcript_data
                            )

            # Ensure parent output directory exists and save PDF
            Path(output_pdf_path).parent.mkdir(parents=True, exist_ok=True)
            pdf.output(output_pdf_path)
            logger.info(f"Successfully compiled DeskMate PDF report to {output_pdf_path}")
            return True

        except Exception as e:
            logger.exception(f"Failed to compile DeskMate PDF report: {e}")
            return False

    # ── Metadata block ────────────────────────────────────────────────────

    def _render_metadata_block(self, pdf, session_id, steps, important_ids):
        """Render a branded metadata info card."""
        y_start = pdf.get_y()

        # Card background with left accent
        pdf.set_fill_color(*_LIGHT_BG)
        pdf.rect(_LEFT_MARGIN, y_start, _CONTENT_WIDTH, 22, 'F')
        pdf.set_fill_color(*_DESKMATE_PRIMARY)
        pdf.rect(_LEFT_MARGIN, y_start, 3, 22, 'F')

        pdf.set_y(y_start + 3)

        # Row 1: Session ID + Generated timestamp
        pdf.set_x(_LEFT_MARGIN + 8)
        pdf.set_font('Helvetica', 'B', 8.5)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(20, 5, 'SESSION', 0, 0)
        pdf.set_font('Helvetica', '', 9)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.cell(62, 5, session_id, 0, 0)

        pdf.set_font('Helvetica', 'B', 8.5)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(25, 5, 'GENERATED', 0, 0)
        pdf.set_font('Helvetica', '', 9)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.cell(0, 5, datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), 0, 1)

        # Row 2: Moments + Key Moments
        pdf.set_x(_LEFT_MARGIN + 8)
        pdf.set_font('Helvetica', 'B', 8.5)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(20, 5, 'MOMENTS', 0, 0)
        pdf.set_font('Helvetica', '', 9)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.cell(62, 5, str(len(steps)), 0, 0)

        pdf.set_font('Helvetica', 'B', 8.5)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(25, 5, 'KEY MOMENTS', 0, 0)
        pdf.set_font('Helvetica', '', 9)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.cell(0, 5, str(len(important_ids)), 0, 1)

        pdf.ln(8)

    # ── Section header ────────────────────────────────────────────────────

    def _render_section_header(self, pdf, title):
        """Render a rich section header with DeskMate branding."""
        pdf.ln(4)
        y = pdf.get_y()
        if y + 16 > _PAGE_BOTTOM_Y:
            pdf.add_page()
            y = pdf.get_y()

        # Background highlight strip
        pdf.set_fill_color(*_LIGHT_BG)
        pdf.rect(_LEFT_MARGIN, y, _CONTENT_WIDTH, 9, 'F')

        # Left accent bar (DeskMate primary purple)
        pdf.set_fill_color(*_DESKMATE_PRIMARY)
        pdf.rect(_LEFT_MARGIN, y, 3.5, 9, 'F')

        # Title text
        pdf.set_xy(_LEFT_MARGIN + 8, y + 1.2)
        pdf.set_font('Helvetica', 'B', 12)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(_CONTENT_WIDTH - 12, 6.5, title, 0, 1)

        pdf.ln(3)

    def _write_formatted_text(self, pdf, text, font_size=9.5, default_bold=False):
        """Write text with support for inline **bold** formatting and correct word wrapping."""
        parts = re.split(r'\*\*(.*?)\*\*', text)
        for idx, part in enumerate(parts):
            is_bold = (idx % 2 == 1) if not default_bold else (idx % 2 == 0)
            if is_bold:
                pdf.set_font('Helvetica', 'B', font_size)
                part_upper = part.upper()
                if "HIGH PRIORITY" in part_upper or "CRITICAL" in part_upper:
                    pdf.set_text_color(*_URGENT)            # Red accent for warnings/high priorities
                elif "ACTION ITEM" in part_upper or "TO BE CONTINUED" in part_upper:
                    pdf.set_text_color(*_DESKMATE_PRIMARY)   # DeskMate primary purple for action items
                elif "IMPORTANT" in part_upper:
                    pdf.set_text_color(*_WARNING)           # Amber for key points
                elif any(kw in part_upper for kw in _CONTEXT_LABELS):
                    pdf.set_text_color(*_CONTEXT_ACCENT)     # Informational teal for context references
                else:
                    pdf.set_text_color(*_DESKMATE_DARK)
            else:
                pdf.set_font('Helvetica', '', font_size)
                pdf.set_text_color(*_BODY_TEXT)
            pdf.write(5, self._make_safe(part))

    def _render_markdown_body(self, pdf, text):
        """Parse and render Markdown text into styled PDF content."""
        pdf.set_text_color(*_BODY_TEXT)

        raw_lines = (text or "").split('\n')
        stripped_lines = [l.strip() for l in raw_lines]

        for i, original_line in enumerate(raw_lines):
            line = original_line.strip()
            if not line:
                pdf.ln(2.5)
                continue

            # Skip stray delimiter tags or empty title repetitions
            if line.upper() in ("SUMMARY", "### SUMMARY", "## SUMMARY", "# SUMMARY", "===SUMMARY==="):
                continue

            # Determine indentation levels for nested lists based on original line leading spaces
            stripped_left = original_line.lstrip()
            indent_spaces = len(original_line) - len(stripped_left)
            level = 1
            if indent_spaces >= 6:
                level = 3
            elif indent_spaces >= 2:
                level = 2

            # Guard against headers with no content underneath
            if line.startswith(('# ', '## ', '### ', '#### ')):
                header_text = re.sub(r'^#{1,4}\s*', '', line).strip()
                if header_text.upper() in ("SUMMARY", "MEETING SUMMARY"):
                    continue
                has_substantive_body = False
                for next_l in stripped_lines[i + 1:]:
                    if not next_l:
                        continue
                    if next_l.startswith(('# ', '## ', '### ', '#### ')):
                        break
                    clean_check = re.sub(r"^[-*0-9.]+\s*", "", next_l).strip().lower().strip(" .\"'()")
                    if clean_check in ("none", "n/a", "not applicable", "not discussed", "not specified", "none identified", "none discussed", "not mentioned", "[]", "{}"):
                        continue
                    if any(clean_check.startswith(prefix) for prefix in ("none ", "no specific ", "not discussed", "not mentioned")):
                        continue
                    has_substantive_body = True
                    break
                if not has_substantive_body:
                    # Skip empty hanging header with no substantive content
                    continue

                if line.startswith('# '):
                    self._render_sub_header(pdf, line[2:], level=2)
                elif line.startswith('## '):
                    self._render_sub_header(pdf, line[3:], level=2)
                elif line.startswith('### '):
                    self._render_sub_header(pdf, line[4:], level=3)
                elif line.startswith('#### '):
                    self._render_sub_header(pdf, line[5:], level=4)
            # Bullet points
            elif line.startswith('- ') or line.startswith('* '):
                self._render_bullet(pdf, line[2:].strip(), level=level)
            # Numbered list items
            elif re.match(r'^\d+\.\s', line):
                num_match = re.match(r'^(\d+)\.\s(.*)$', line)
                if num_match:
                    self._render_numbered_item(pdf, num_match.group(1), num_match.group(2).strip(), level=level)
            else:
                # Regular paragraph
                self._render_rich_paragraph(pdf, line, font_size=9.5)

    def _render_sub_header(self, pdf, text, level=3):
        """Render a sub-header with DeskMate deep purple/slate color."""
        sizes = {2: 12, 3: 11, 4: 10}
        font_size = sizes.get(level, 11)
        text_w = _CONTENT_WIDTH - 5 if level <= 3 else _CONTENT_WIDTH - 3

        # Check height and add page if it doesn't fit on the current page
        header_h = self._get_text_height(pdf, text, font_size=font_size, width=text_w) + 10
        if pdf.get_y() + header_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.ln(3)
        pdf.set_font('Helvetica', 'B', font_size)
        pdf.set_text_color(*_DESKMATE_DEEP)

        # Small accent dot before header
        if level <= 3:
            pdf.set_x(_LEFT_MARGIN)
            pdf.set_fill_color(*_DESKMATE_PRIMARY)
            dot_y = pdf.get_y() + 2
            pdf.rect(_LEFT_MARGIN, dot_y, 2, 2, 'F')
            pdf.set_x(_LEFT_MARGIN + 5)
        else:
            pdf.set_x(_LEFT_MARGIN + 3)

        safe_text = self._make_safe(text)
        pdf.multi_cell(text_w, 6, safe_text)
        pdf.ln(2)
        pdf.set_font('Helvetica', '', 9.5)
        pdf.set_text_color(*_BODY_TEXT)

    def _render_rich_paragraph(self, pdf, text, font_size=9.5):
        """Render a paragraph with inline bold formatting support using native multi_cell markdown."""
        if not text:
            return
        para_h = self._get_text_height(pdf, text, font_size=font_size, width=_CONTENT_WIDTH)
        if pdf.get_y() + para_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.set_font('Helvetica', '', font_size)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.set_x(_LEFT_MARGIN)
        pdf.multi_cell(_CONTENT_WIDTH, 5.2, self._make_safe(text), markdown=True)
        pdf.ln(2.5)

    def _render_bullet(self, pdf, text, level=1):
        """Render a styled bullet point with inline bold formatting and hanging indent."""
        if not text:
            return
        indent = 4 * level
        bullet_w = 4
        text_w = _CONTENT_WIDTH - indent - bullet_w
        text_x = _LEFT_MARGIN + indent + bullet_w

        bullet_h = self._get_text_height(pdf, text, font_size=9.5, width=text_w)
        if pdf.get_y() + bullet_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        bullet_char = chr(149)  # Level 1: •
        if level == 2:
            bullet_char = chr(183)  # Level 2: ·
        elif level >= 3:
            bullet_char = chr(150)  # Level 3: –

        pdf.set_xy(_LEFT_MARGIN + indent, pdf.get_y())
        pdf.set_font('Helvetica', 'B', 10)
        pdf.set_text_color(*_DESKMATE_PRIMARY)
        pdf.cell(bullet_w, 5.2, bullet_char, 0, 0)

        old_margin = pdf.l_margin
        pdf.set_left_margin(text_x)
        pdf.set_xy(text_x, pdf.get_y())
        pdf.set_font('Helvetica', '', 9.5)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.multi_cell(text_w, 5.2, self._make_safe(text), markdown=True)
        pdf.set_left_margin(old_margin)
        pdf.ln(2)

    def _render_numbered_item(self, pdf, number, text, level=1):
        """Render a numbered list item with branded number, hanging indent, and inline bold support."""
        if not text:
            return
        indent = 4 * level
        num_w = 7
        text_w = _CONTENT_WIDTH - indent - num_w
        text_x = _LEFT_MARGIN + indent + num_w

        item_h = self._get_text_height(pdf, text, font_size=9.5, width=text_w)
        if pdf.get_y() + item_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.set_xy(_LEFT_MARGIN + indent, pdf.get_y())
        pdf.set_font('Helvetica', 'B', 9.5)
        pdf.set_text_color(*_DESKMATE_PRIMARY)
        pdf.cell(num_w, 5.2, f"{number}.", 0, 0)

        old_margin = pdf.l_margin
        pdf.set_left_margin(text_x)
        pdf.set_xy(text_x, pdf.get_y())
        pdf.set_font('Helvetica', '', 9.5)
        pdf.set_text_color(*_BODY_TEXT)
        pdf.multi_cell(text_w, 5.2, self._make_safe(text), markdown=True)
        pdf.set_left_margin(old_margin)
        pdf.ln(2)

    # ── Screenshots section ───────────────────────────────────────────────

    def _render_screenshots(
        self, pdf, steps, important_step_ids, step_descriptions=None, transcript_data=None, session_id=""
    ):
        """Render deduplicated screenshots with rich step cards and synchronized spoken dialogue."""
        if step_descriptions is None:
            step_descriptions = {}

        # Normalize step IDs for matching
        normalized_ids = set()
        for sid in (important_step_ids or []):
            match = re.search(r'\d+', str(sid))
            if match:
                normalized_ids.add(int(match.group()))

        rendered_count = 0
        rendered_hashes = set()

        # Build candidate list of steps to render
        candidates = []
        for step in steps:
            step_id_val = step.get("step_id", 0)
            try:
                step_num = int(re.search(r'\d+', str(step_id_val)).group())
            except Exception:
                step_num = None

            is_important = (
                (step_num is not None and step_num in normalized_ids)
                or str(step_id_val).lower().strip() in [str(s).lower().strip() for s in (important_step_ids or [])]
            )
            if is_important and not is_host_ui_step(step):
                candidates.append(step)

        # Fallback: if fewer than 2 moments selected, backfill with available non-host steps
        if len(candidates) < 2:
            candidate_ids = {s.get("step_id") for s in candidates}
            for step in steps:
                if step.get("step_id") not in candidate_ids and not is_host_ui_step(step):
                    candidates.append(step)
                    if len(candidates) >= 4:
                        break

        # Emergency fallback: if candidates still empty, include any valid steps
        if not candidates and steps:
            candidates = list(steps[:4])

        for step in candidates:
            step_id_val = step.get("step_id", 0)
            actions = step.get("actions", [])
            asset_rel_path = step.get("screenshot_path") or next(
                (a.get("asset_path") for a in actions if a.get("asset_path")), None
            )
            if not asset_rel_path:
                continue

            full_img_path = resolve_screenshot_path(asset_rel_path, session_id=session_id)
            if not full_img_path or not os.path.exists(full_img_path):
                continue

            # Skip any step showing host DeskMate UI or recording screen
            if is_host_ui_step(step):
                continue

            # ── Deduplicate by file hash ──────────────────────────────
            try:
                file_hash = hashlib.md5(Path(full_img_path).read_bytes(), usedforsecurity=False).hexdigest()
                if file_hash in rendered_hashes:
                    logger.debug(f"Skipping duplicate image for step {step_id_val}")
                    continue
                rendered_hashes.add(file_hash)
            except Exception:
                pass

            # Calculate the total height of the current card
            card_height = self._calculate_step_card_height(
                pdf, step, step_descriptions, transcript_data=transcript_data
            )
            if pdf.get_y() + card_height > _PAGE_BOTTOM_Y:
                pdf.add_page()

            # ── Step card ─────────────────────────────────────────────
            card_y = pdf.get_y()

            # Card background
            pdf.set_fill_color(*_CARD_BG)
            pdf.rect(_LEFT_MARGIN, card_y, _CONTENT_WIDTH, 10, 'F')

            # Left accent bar in DeskMate primary purple
            pdf.set_fill_color(*_DESKMATE_PRIMARY)
            pdf.rect(_LEFT_MARGIN, card_y, 3, 10, 'F')

            # Step badge (pill) with sequential Moment 1..N numbering
            moment_index = rendered_count + 1
            pdf.set_y(card_y + 2)
            pdf.set_x(_LEFT_MARGIN + 6)
            pdf.set_fill_color(*_DESKMATE_PRIMARY)
            badge_text = f" Moment {moment_index} "
            badge_w = pdf.get_string_width(badge_text) + 6
            pdf.set_font('Helvetica', 'B', 8)
            pdf.set_text_color(*_WHITE)
            pdf.cell(badge_w, 5.5, badge_text, 0, 0, 'C', fill=True)

            # Step summary/title text & Timestamp
            raw_summary = step.get("summary", "")
            title = self._find_step_title(step_id_val, step_descriptions, raw_summary, step=step)
            safe_title = self._make_safe(title)

            step_ts = step.get("timestamp") or (actions[0].get("timestamp") if actions else "00:00")
            title_w = _CONTENT_WIDTH - badge_w - 38

            # Prevent text from colliding with the timestamp
            max_title_chars = int(title_w / 2.2)
            if len(safe_title) > max_title_chars:
                safe_title = safe_title[:max_title_chars - 3].rstrip() + "..."

            pdf.set_x(_LEFT_MARGIN + 6 + badge_w + 4)
            pdf.set_font('Helvetica', 'B', 9)
            pdf.set_text_color(*_DESKMATE_DARK)
            pdf.cell(title_w, 5.5, safe_title, 0, 0)

            # Exact moment timestamp on right of step header card
            pdf.set_font('Helvetica', 'B', 8)
            pdf.set_text_color(*_MUTED_TEXT)
            pdf.cell(24, 5.5, f"[{step_ts}]", 0, 1, 'R')

            pdf.set_y(card_y + 11.5)

            # ── Image — bordered and centered ─────────────────────────
            try:
                img_y = pdf.get_y()
                pdf.set_draw_color(*_DIVIDER)
                pdf.set_line_width(0.3)

                actual_h = min(_IMG_WIDTH * (9 / 16), _MAX_IMG_HEIGHT)
                if os.path.exists(full_img_path):
                    try:
                        import cv2
                        im_data = cv2.imread(full_img_path)
                        if im_data is not None:
                            h_px, w_px = im_data.shape[:2]
                            actual_h = min(_IMG_WIDTH * (h_px / w_px), _MAX_IMG_HEIGHT)
                    except Exception:
                        pass

                pdf.image(full_img_path, x=_IMG_X, y=img_y, w=_IMG_WIDTH, h=actual_h)

                # Draw hairline border after image is placed
                pdf.rect(_IMG_X - 0.5, img_y - 0.5, _IMG_WIDTH + 1, actual_h + 1)
                pdf.set_y(img_y + actual_h + 2)

                rendered_count += 1
            except Exception as img_err:
                logger.error(f"Failed to embed screenshot {full_img_path}: {img_err}")
                continue

            # ── Description & Audio Transcript below screenshot ──────────
            description, audio_transcript = self._step_card_texts(step, step_descriptions, transcript_data)
            self._render_step_description(
                pdf, description, timestamp_str=step_ts, audio_transcript=audio_transcript
            )

            pdf.ln(5)

        if rendered_count == 0:
            pdf.set_font('Helvetica', 'I', 9)
            pdf.set_text_color(*_MUTED_TEXT)
            pdf.set_x(_LEFT_MARGIN)
            pdf.cell(_CONTENT_WIDTH, 6, 'No screenshots available for the identified key moments.', 0, 1)

    @staticmethod
    def _lookup_step_meta(step_id_val, step_descriptions: dict) -> Any:
        """Step metadata by id, tolerating 'step_3', 'Step 3', '3' style keys."""
        if not step_descriptions:
            return None
        sid = str(step_id_val)
        for key in (sid, f"step_{sid}", f"step {sid}", f"Step {sid}", f"Step_{sid}"):
            if key in step_descriptions:
                return step_descriptions[key]
        match = re.search(r'\d+', sid)
        if match:
            num = int(match.group())
            for key, value in step_descriptions.items():
                key_match = re.search(r'\d+', str(key))
                if key_match and int(key_match.group()) == num:
                    return value
        return None

    def _find_step_description(self, step_id_val, step_descriptions: dict) -> str:
        meta = self._lookup_step_meta(step_id_val, step_descriptions)
        if isinstance(meta, dict):
            return str(meta.get("description") or "")
        return str(meta) if meta is not None else ""

    def _find_step_title(self, step_id_val, step_descriptions: dict, default_summary: str, step: Optional[dict] = None) -> str:
        meta = self._lookup_step_meta(step_id_val, step_descriptions)
        if isinstance(meta, dict) and meta.get("title") and str(meta["title"]).lower() not in GENERIC_STEP_SUMMARIES:
            return str(meta["title"])
        return readable_step_title(default_summary, step=step)

    def _step_card_texts(
        self, step: dict, step_descriptions: dict, transcript_data: Optional[dict] = None
    ) -> tuple[str, str]:
        """(description, spoken quote) for a step card. The summarizer fills both for key moments;
        this also covers steps it did not describe, such as custom-field evidence."""
        step_id_val = step.get("step_id", 0)
        description = self._find_step_description(step_id_val, step_descriptions).strip()
        if not description or description.lower() in GENERIC_STEP_SUMMARIES:
            description = fallback_step_description(step)
        meta = self._lookup_step_meta(step_id_val, step_descriptions)
        quote = str(meta.get("audio_transcript") or "").strip() if isinstance(meta, dict) else ""
        return description, quote or spoken_quotes_near(transcript_data, step)

    @staticmethod
    def _split_action_and_context(description: str) -> tuple[str, str]:
        """(in-meeting action, researched context) — the model marks context as
        [Context Reference: ...], **[Context Reference]**: ... or *(Context Reference: ...)*."""
        text = (description or "").strip()
        for pattern in _CONTEXT_PATTERNS:
            contexts = [m.group(1).strip() for m in pattern.finditer(text)]
            if contexts:
                return pattern.sub("", text).strip(), " ".join(contexts)
        return text, ""

    def _calculate_step_card_height(
        self, pdf, step: dict, step_descriptions: dict, transcript_data: Optional[dict] = None
    ) -> float:
        """Calculate the total height (in mm) required to render a step card (header, image, description, audio)."""
        header_h = 10
        spacing_h = 2 + 5  # Spacing between image/box and bottom margin

        # Image height
        actions = step.get("actions", [])
        asset_rel_path = step.get("screenshot_path") or next(
            (a.get("asset_path") for a in actions if a.get("asset_path")), None
        )
        rendered_img_h = min(_IMG_WIDTH * (9 / 16), _MAX_IMG_HEIGHT)

        if asset_rel_path:
            full_img_path = resolve_screenshot_path(asset_rel_path)
            if full_img_path and os.path.exists(full_img_path):
                try:
                    import cv2
                    img = cv2.imread(full_img_path)
                    if img is not None:
                        h_px, w_px = img.shape[:2]
                        rendered_img_h = min(_IMG_WIDTH * (h_px / w_px), _MAX_IMG_HEIGHT)
                except Exception:
                    pass

        description, audio_transcript = self._step_card_texts(step, step_descriptions, transcript_data)
        action_text, context_text = self._split_action_and_context(description)
        box_height = self._description_box_height(pdf, action_text, context_text, audio_transcript)

        return header_h + rendered_img_h + box_height + spacing_h

    def _get_first_card_height(
        self,
        pdf,
        steps: list,
        important_step_ids: list,
        step_descriptions: dict,
        transcript_data: Optional[dict] = None
    ) -> float:
        """Find the height of the first step card that will actually be rendered."""
        if not steps or not important_step_ids:
            return 0.0

        normalized_ids = set()
        for sid in important_step_ids:
            match = re.search(r'\d+', str(sid))
            if match:
                normalized_ids.add(int(match.group()))

        for step in steps:
            step_id_val = step.get("step_id", 0)
            try:
                step_num = int(re.search(r'\d+', str(step_id_val)).group())
            except Exception:
                step_num = None

            is_important = (
                (step_num is not None and step_num in normalized_ids)
                or str(step_id_val).lower().strip() in [str(s).lower().strip() for s in important_step_ids]
            )
            if not is_important:
                continue

            actions = step.get("actions", [])
            asset_rel_path = step.get("screenshot_path") or next(
                (a.get("asset_path") for a in actions if a.get("asset_path")), None
            )
            if not asset_rel_path:
                continue

            full_img_path = resolve_screenshot_path(asset_rel_path)
            if full_img_path and os.path.exists(full_img_path):
                return self._calculate_step_card_height(
                    pdf, step, step_descriptions, transcript_data=transcript_data
                )

        return 0.0

    @staticmethod
    def _description_box_height(pdf, action_text: str, context_text: str, audio_text: str) -> float:
        """Height (mm) of the card under a screenshot; used to plan page breaks and to draw it."""
        saved_font = (pdf.font_family, pdf.font_style, pdf.font_size_pt)

        def text_height(text: str, style: str, size: float, line_h: float) -> float:
            pdf.set_font('Helvetica', style, size)
            try:
                return pdf.multi_cell(
                    w=_IMG_WIDTH - 14, h=line_h, text=text.replace('**', ''), dry_run=True, output='HEIGHT'
                )
            except Exception:
                return 3 * line_h

        height = 2 * _DESC_BOX_PADDING
        if action_text:
            height += 5.0 + text_height(action_text, '', 8.5, 4.8)
        if context_text:
            height += 8.0 + text_height(context_text, 'I', 8.0, 4.2)
        if audio_text:
            height += 8.0 + text_height(audio_text, 'I', 8.0, 4.2)
        pdf.set_font(*saved_font)
        return height

    def _render_step_description(
        self, pdf, description: str, timestamp_str: str = "", audio_transcript: str = ""
    ):
        """Render a description card below screenshot with visual details and synchronized dialogue."""
        desc_x = _IMG_X
        desc_w = _IMG_WIDTH
        safe_audio = self._make_safe(audio_transcript)
        action_text, context_text = self._split_action_and_context(self._make_safe(description))
        box_height = self._description_box_height(pdf, action_text, context_text, safe_audio)

        desc_y = pdf.get_y()
        if desc_y + box_height > _PAGE_BOTTOM_Y:
            pdf.add_page()
            desc_y = pdf.get_y()

        # Description card background
        pdf.set_fill_color(*_LIGHT_BG)
        pdf.rect(desc_x, desc_y, desc_w, box_height, 'F')

        # Left accent bar — DeskMate deep slate
        pdf.set_fill_color(*_DESKMATE_DEEP)
        pdf.rect(desc_x, desc_y, 3, box_height, 'F')

        curr_y = desc_y + _DESC_BOX_PADDING

        # Visual action description section
        if action_text:
            label_text = f"ACTION & OPERATION PERFORMED [{timestamp_str}]" if timestamp_str else "ACTION & OPERATION PERFORMED"
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', 'B', 8)
            pdf.set_text_color(*_DESKMATE_PRIMARY)
            pdf.cell(desc_w - 14, 5, label_text)

            curr_y += 5.5
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', '', 8.5)
            pdf.set_text_color(*_BODY_TEXT)
            pdf.multi_cell(desc_w - 14, 4.8, action_text, markdown=True)
            curr_y = pdf.get_y() + 3.0

        # Augmented domain/technical context reference (clearly distinguished)
        if context_text:
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', 'B', 7.5)
            pdf.set_text_color(*_CONTEXT_ACCENT)
            pdf.cell(desc_w - 14, 4.5, "TECHNICAL CONTEXT & DOMAIN REFERENCE")

            curr_y = pdf.get_y() + 4.5 + 1.0
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', 'I', 8.0)
            pdf.set_text_color(15, 76, 92)  # Dark teal for clear distinction
            pdf.multi_cell(desc_w - 14, 4.2, context_text, markdown=True)
            curr_y = pdf.get_y() + 3.0

        # Synchronized spoken discussion section - ONLY if safe_audio is present
        if safe_audio:
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', 'B', 7.5)
            pdf.set_text_color(*_DESKMATE_PRIMARY)
            pdf.cell(desc_w - 14, 4.5, "RELEVANT SPEAKER STATEMENTS")

            curr_y = pdf.get_y() + 4.5 + 1.0
            pdf.set_y(curr_y)
            pdf.set_x(desc_x + 7)
            pdf.set_font('Helvetica', 'I', 8.0)
            pdf.set_text_color(*_BODY_TEXT)
            pdf.multi_cell(desc_w - 14, 4.2, safe_audio)

        pdf.set_y(desc_y + box_height)

    # ── Utilities ─────────────────────────────────────────────────────────

    def _get_text_height(self, pdf, text, font_size=9.5, width=_CONTENT_WIDTH):
        """Calculate the height required to render a block of text."""
        if not text:
            return 0.0
        current_font = pdf.font_family
        current_style = pdf.font_style
        current_size = pdf.font_size_pt

        pdf.set_font('Helvetica', '', font_size)
        try:
            clean_text = text.replace('**', '')
            safe_text = self._make_safe(clean_text)
            h = pdf.multi_cell(
                w=width,
                h=5,
                text=safe_text,
                dry_run=True,
                output='HEIGHT'
            )
        except Exception:
            safe_text = self._make_safe(text.replace('**', ''))
            approx_lines = max(1, len(safe_text) / (width * 0.4))
            h = approx_lines * 5

        pdf.set_font(current_font, current_style, current_size)
        return h

    @staticmethod
    def _make_safe(text: str) -> str:
        return _to_pdf_text(text)


# Alias for backward compatibility
PDFGenerator = MeetingPDFGenerator
