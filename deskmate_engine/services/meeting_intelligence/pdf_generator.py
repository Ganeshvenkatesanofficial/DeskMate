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

from services.meeting_intelligence import config

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

# ── Page Constants ────────────────────────────────────────────────────────────
_LEFT_MARGIN = 15
_RIGHT_MARGIN = 15
_CONTENT_WIDTH = 210 - _LEFT_MARGIN - _RIGHT_MARGIN   # 180mm
_IMG_WIDTH = 170
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
# Steps whose title/description mention these are DeskMate's own UI, not meeting content.
_HOST_APP_TERMS = (
    "deskmate", "deskmate live", "meeting scribe", "recording dashboard",
    "start meeting", "stop meeting", "end meeting", "mission control", "app switcher",
)


def _resolve_screenshot_path(asset_rel_path: str) -> Optional[str]:
    """Robust screenshot resolution across dev workspace and macOS Application Support."""
    if not asset_rel_path:
        return None

    p = Path(asset_rel_path)
    if p.is_absolute() and p.exists():
        return str(p)

    candidates = [
        Path(config.OUTPUT_DIR) / asset_rel_path,
        Path(config.OUTPUT_DIR) / "live_sessions" / asset_rel_path,
        Path(asset_rel_path),
        Path.cwd() / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / "sessions" / asset_rel_path,
        Path.home() / "Library" / "Application Support" / "DeskMate" / "output" / "sessions" / asset_rel_path,
        Path.home() / "AppData" / "Roaming" / "DeskMate" / asset_rel_path,
        Path.home() / "AppData" / "Roaming" / "DeskMate" / "sessions" / asset_rel_path,
    ]

    for prefix in ["output/sessions/", "sessions/", "live_sessions/", "output/"]:
        if asset_rel_path.startswith(prefix):
            stripped = asset_rel_path[len(prefix):]
            candidates.append(Path.home() / "Library" / "Application Support" / "DeskMate" / "sessions" / stripped)
            candidates.append(Path(config.OUTPUT_DIR) / stripped)

    for cand in candidates:
        try:
            if cand.exists() and cand.is_file():
                return str(cand.resolve())
        except Exception:
            pass
    return None


class MeetingReportPDF(FPDF):
    """Custom FPDF layout with rich DeskMate AI branding on every page."""

    def normalize_text(self, text: str) -> str:
        # Single choke point: no caller can crash the PDF with unsupported characters.
        return super().normalize_text(_to_pdf_text(text))

    def header(self):
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

            # Drop steps that show DeskMate's own recording UI
            filtered_important_step_ids = []
            for sid in [str(x) for x in (important_step_ids or [])]:
                desc = self._find_step_description(sid, step_descriptions).lower()
                title = self._find_step_title(sid, step_descriptions, "").lower()
                if any(term in desc or term in title for term in _HOST_APP_TERMS):
                    logger.info(f"Programmatically filtering out step {sid} because it refers to host app UI.")
                    continue
                filtered_important_step_ids.append(sid)
            important_step_ids = filtered_important_step_ids

            pdf = MeetingReportPDF()
            pdf.alias_nb_pages()
            pdf.set_left_margin(_LEFT_MARGIN)
            pdf.set_right_margin(_RIGHT_MARGIN)
            pdf.add_page()
            pdf.set_auto_page_break(auto=True, margin=22)

            # ─── Metadata block ──────────────────────────────────────────
            self._render_metadata_block(pdf, session_id, steps, important_step_ids)

            # ─── Executive Summary ───────────────────────────────────────
            self._render_section_header(pdf, 'Executive Summary & Analysis')
            self._render_markdown_body(pdf, summary_text)
            pdf.ln(6)

            # ─── Key Visual Moments ──────────────────────────────────────
            if steps and important_step_ids:
                # Force a page break if the header and first screenshot card won't fit on the current page
                first_card_h = self._get_first_card_height(pdf, steps, important_step_ids, step_descriptions)
                if pdf.get_y() + 25 + first_card_h > _PAGE_BOTTOM_Y:
                    pdf.add_page()
                self._render_section_header(pdf, 'Key Visual Interaction Moments')
                self._render_screenshots(pdf, steps, important_step_ids, step_descriptions)

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
                            first_card_h = self._get_first_card_height(pdf, steps, str_relevant_steps, step_descriptions)
                            if pdf.get_y() + 14 + first_card_h > _PAGE_BOTTOM_Y:
                                pdf.add_page()

                            pdf.ln(4)
                            pdf.set_font('Helvetica', 'B', 10.5)
                            pdf.set_text_color(*_DESKMATE_DEEP)
                            pdf.set_x(_LEFT_MARGIN)
                            pdf.cell(_CONTENT_WIDTH, 6, "Relevant Visual Evidence", 0, 1)
                            pdf.ln(4)

                            self._render_screenshots(pdf, steps, str_relevant_steps, step_descriptions)

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
        pdf.ln(5)

        y = pdf.get_y()

        # Background highlight strip
        pdf.set_fill_color(*_LIGHT_BG)
        pdf.rect(_LEFT_MARGIN, y, _CONTENT_WIDTH, 10, 'F')

        # Left accent bar (DeskMate primary purple)
        pdf.set_fill_color(*_DESKMATE_PRIMARY)
        pdf.rect(_LEFT_MARGIN, y, 4, 10, 'F')

        # Title text
        pdf.set_xy(_LEFT_MARGIN + 8, y + 1)
        pdf.set_font('Helvetica', 'B', 13)
        pdf.set_text_color(*_DESKMATE_DEEP)
        pdf.cell(_CONTENT_WIDTH - 12, 8, title, 0, 1)

        pdf.ln(4)

        # Decorative divider — primary purple thin line + subtle divider
        pdf.set_fill_color(*_DESKMATE_PRIMARY)
        pdf.rect(_LEFT_MARGIN, pdf.get_y(), 40, 0.6, 'F')
        pdf.set_fill_color(*_DIVIDER)
        pdf.rect(_LEFT_MARGIN + 40, pdf.get_y(), _CONTENT_WIDTH - 40, 0.3, 'F')
        pdf.ln(5)

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
                else:
                    pdf.set_text_color(*_DESKMATE_DARK)
            else:
                pdf.set_font('Helvetica', '', font_size)
                pdf.set_text_color(*_BODY_TEXT)
            pdf.write(5, self._make_safe(part))

    def _render_markdown_body(self, pdf, text):
        """Parse and render Markdown text into styled PDF content."""
        pdf.set_text_color(*_BODY_TEXT)

        for original_line in (text or "").split('\n'):
            line = original_line.strip()
            if not line:
                pdf.ln(3)
                continue

            # Determine indentation levels for nested lists based on original line leading spaces
            stripped_left = original_line.lstrip()
            indent_spaces = len(original_line) - len(stripped_left)
            level = 1
            if indent_spaces >= 6:
                level = 3
            elif indent_spaces >= 2:
                level = 2

            # H1 headers
            if line.startswith('# '):
                self._render_sub_header(pdf, line[2:], level=2)
            # H2 headers
            elif line.startswith('## '):
                self._render_sub_header(pdf, line[3:], level=2)
            # H3 headers
            elif line.startswith('### '):
                self._render_sub_header(pdf, line[4:], level=3)
            # H4 headers
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

    def _render_bullet(self, pdf, text, level=1):
        """Render a styled bullet point with inline bold formatting support."""
        indent = 6 * level
        bullet_w = 5
        text_x = _LEFT_MARGIN + indent + bullet_w
        text_width = _CONTENT_WIDTH - indent - bullet_w

        # Check height and add page if it doesn't fit on the current page
        bullet_h = self._get_text_height(pdf, text, font_size=9.5, width=text_width)
        if pdf.get_y() + bullet_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.set_x(_LEFT_MARGIN + indent)
        # Choose bullet character based on level
        bullet_char = chr(149)  # Level 1: round bullet (•)
        if level == 2:
            bullet_char = chr(183)  # Level 2: middle dot (·)
        elif level >= 3:
            bullet_char = chr(150)  # Level 3: en dash (–)

        pdf.set_font('Helvetica', '', 9.5)
        pdf.set_text_color(*_DESKMATE_PRIMARY)
        pdf.cell(bullet_w, 5, bullet_char, 0, 0)

        # Temp change left margin for wrap
        old_margin = pdf.l_margin
        pdf.set_left_margin(text_x)

        # Write formatted text
        self._write_formatted_text(pdf, text, font_size=9.5)

        # Reset margin
        pdf.set_left_margin(old_margin)
        pdf.ln(6)

    def _render_numbered_item(self, pdf, number, text, level=1):
        """Render a numbered list item with branded number and inline bold support."""
        indent = 6 * level
        num_w = 8
        text_x = _LEFT_MARGIN + indent + num_w
        text_width = _CONTENT_WIDTH - indent - num_w

        # Check height and add page if it doesn't fit on the current page
        item_h = self._get_text_height(pdf, text, font_size=9.5, width=text_width)
        if pdf.get_y() + item_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.set_x(_LEFT_MARGIN + indent)
        # Number in primary purple
        pdf.set_font('Helvetica', 'B', 9.5)
        pdf.set_text_color(*_DESKMATE_PRIMARY)
        pdf.cell(num_w, 5, f"{number}.", 0, 0)

        # Temp change left margin for wrap
        old_margin = pdf.l_margin
        pdf.set_left_margin(text_x)

        # Write formatted text
        self._write_formatted_text(pdf, text, font_size=9.5)

        # Reset margin
        pdf.set_left_margin(old_margin)
        pdf.ln(6)

    def _render_rich_paragraph(self, pdf, text, font_size=9.5):
        """Render a paragraph with inline bold formatting support."""
        # Check height and add page if it doesn't fit on the current page
        para_h = self._get_text_height(pdf, text, font_size=font_size, width=_CONTENT_WIDTH)
        if pdf.get_y() + para_h > _PAGE_BOTTOM_Y:
            pdf.add_page()

        pdf.set_x(_LEFT_MARGIN)
        self._write_formatted_text(pdf, text, font_size=font_size)
        pdf.ln(7)

    # ── Screenshots section ───────────────────────────────────────────────

    def _render_screenshots(self, pdf, steps, important_step_ids, step_descriptions=None):
        """Render deduplicated screenshots with rich step cards."""
        if step_descriptions is None:
            step_descriptions = {}

        # Normalize step IDs for matching
        normalized_ids = set()
        for sid in important_step_ids:
            match = re.search(r'\d+', str(sid))
            if match:
                normalized_ids.add(int(match.group()))

        rendered_count = 0
        rendered_hashes = set()

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

            full_img_path = _resolve_screenshot_path(asset_rel_path)
            if not full_img_path or not os.path.exists(full_img_path):
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
            card_height = self._calculate_step_card_height(pdf, step, step_descriptions)
            if pdf.get_y() + card_height > _PAGE_BOTTOM_Y:
                pdf.add_page()

            # ── Step card ─────────────────────────────────────────────
            card_y = pdf.get_y()

            # Card background
            pdf.set_fill_color(*_CARD_BG)
            pdf.rect(_LEFT_MARGIN, card_y, _CONTENT_WIDTH, 12, 'F')

            # Left accent bar in DeskMate primary purple
            pdf.set_fill_color(*_DESKMATE_PRIMARY)
            pdf.rect(_LEFT_MARGIN, card_y, 3, 12, 'F')

            # Step badge (pill)
            pdf.set_y(card_y + 3)
            pdf.set_x(_LEFT_MARGIN + 7)
            pdf.set_fill_color(*_DESKMATE_PRIMARY)
            badge_text = f" Moment {step_id_val} "
            badge_w = pdf.get_string_width(badge_text) + 8
            pdf.set_font('Helvetica', 'B', 8.5)
            pdf.set_text_color(*_WHITE)
            pdf.cell(badge_w, 6, badge_text, 0, 0, 'C', fill=True)

            # Step summary/title text & Timestamp
            raw_summary = step.get("summary", "")
            title = self._find_step_title(step_id_val, step_descriptions, raw_summary)
            safe_title = self._make_safe(title)

            step_ts = step.get("timestamp") or (actions[0].get("timestamp") if actions else "00:00")
            title_w = _CONTENT_WIDTH - badge_w - 38

            pdf.set_x(_LEFT_MARGIN + 7 + badge_w + 4)
            pdf.set_font('Helvetica', 'B', 9.5)
            pdf.set_text_color(*_DESKMATE_DARK)
            pdf.cell(title_w, 6, safe_title, 0, 0)

            # Exact moment timestamp on right of step header card
            pdf.set_font('Helvetica', 'B', 8.5)
            pdf.set_text_color(*_MUTED_TEXT)
            pdf.cell(24, 6, f"[{step_ts}]", 0, 1, 'R')

            pdf.set_y(card_y + 14)

            # ── Image — bordered and centered ─────────────────────────
            try:
                img_y = pdf.get_y()
                pdf.set_draw_color(*_DIVIDER)
                pdf.set_line_width(0.3)

                pdf.image(full_img_path, x=_IMG_X, w=_IMG_WIDTH)

                # Draw hairline border after image is placed
                img_h = pdf.get_y() - img_y
                pdf.rect(_IMG_X - 0.5, img_y - 0.5, _IMG_WIDTH + 1, img_h + 1)

                pdf.ln(3)
                rendered_count += 1
            except Exception as img_err:
                logger.error(f"Failed to embed screenshot {full_img_path}: {img_err}")
                continue

            # ── Description below screenshot ──────────────────────────
            description = self._find_step_description(step_id_val, step_descriptions)
            if description:
                self._render_step_description(pdf, description, timestamp_str=step_ts)

            pdf.ln(10)

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

    def _find_step_title(self, step_id_val, step_descriptions: dict, default_summary: str) -> str:
        meta = self._lookup_step_meta(step_id_val, step_descriptions)
        if isinstance(meta, dict) and meta.get("title"):
            return str(meta["title"])
        return self._clean_fallback_title(default_summary)

    def _clean_fallback_title(self, summary: str) -> str:
        """Clean raw technical step summary text into a user-friendly generic title."""
        if not summary:
            return "Screen Presentation"
        if "unclassified" in summary.lower() or "ui_interaction" in summary.lower() or "observed_interaction" in summary.lower():
            return "Screen Interaction"
        return re.sub(r'^Step\s+\d+:\s*', '', summary)

    def _calculate_step_card_height(self, pdf, step: dict, step_descriptions: dict) -> float:
        """Calculate the total height (in mm) required to render a step card (header, image, description)."""
        header_h = 12
        spacing_h = 14 + 3 + 10

        # Image height
        actions = step.get("actions", [])
        asset_rel_path = step.get("screenshot_path") or next(
            (a.get("asset_path") for a in actions if a.get("asset_path")), None
        )
        rendered_img_h = 95.6  # Default 16:9 aspect ratio height for 170mm width

        if asset_rel_path:
            full_img_path = _resolve_screenshot_path(asset_rel_path)
            if full_img_path and os.path.exists(full_img_path):
                try:
                    import cv2
                    img = cv2.imread(full_img_path)
                    if img is not None:
                        h_px, w_px = img.shape[:2]
                        rendered_img_h = _IMG_WIDTH * (h_px / w_px)
                except Exception:
                    pass

        # Description box height
        step_id_val = step.get("step_id", 0)
        description = self._find_step_description(step_id_val, step_descriptions)
        box_height = 0
        if description:
            safe_desc = self._make_safe(description)
            text_for_height = safe_desc.replace('**', '')

            current_font = pdf.font_family
            current_style = pdf.font_style
            current_size = pdf.font_size_pt

            pdf.set_font('Helvetica', '', 8.5)
            try:
                text_height = pdf.multi_cell(
                    w=_IMG_WIDTH - 14,
                    h=4.5,
                    text=text_for_height,
                    dry_run=True,
                    output='HEIGHT'
                )
                box_height = 5 + text_height + 8
            except Exception:
                box_height = 30

            pdf.set_font(current_font, current_style, current_size)

        return header_h + rendered_img_h + box_height + spacing_h

    def _get_first_card_height(self, pdf, steps: list, important_step_ids: list, step_descriptions: dict) -> float:
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

            full_img_path = _resolve_screenshot_path(asset_rel_path)
            if full_img_path and os.path.exists(full_img_path):
                return self._calculate_step_card_height(pdf, step, step_descriptions)

        return 0.0

    def _render_step_description(self, pdf, description: str, timestamp_str: str = ""):
        """Render a premium description card below a screenshot with inline bold support."""
        desc_x = _IMG_X
        desc_w = _IMG_WIDTH
        safe_desc = self._make_safe(description)

        text_for_height = safe_desc.replace('**', '')
        pdf.set_font('Helvetica', '', 8.5)
        text_height = pdf.multi_cell(
            w=desc_w - 14,
            h=4.5,
            text=text_for_height,
            dry_run=True,
            output='HEIGHT'
        )
        label_height = 5
        padding = 8
        box_height = label_height + text_height + padding

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

        # "What happened" label with timestamp
        label_text = f"WHAT HAPPENED AT [{timestamp_str}]" if timestamp_str else "WHAT HAPPENED"
        pdf.set_y(desc_y + 2.5)
        pdf.set_x(desc_x + 7)
        pdf.set_font('Helvetica', 'B', 8)
        pdf.set_text_color(*_DESKMATE_PRIMARY)
        pdf.cell(desc_w - 14, label_height, label_text, 0, 1)

        # Description text
        pdf.set_y(desc_y + 2.5 + label_height + 1)
        pdf.set_x(desc_x + 7)

        old_l_margin = pdf.l_margin
        old_r_margin = pdf.r_margin
        pdf.set_left_margin(desc_x + 7)
        pdf.set_right_margin(210 - (desc_x + desc_w - 7))

        self._write_formatted_text(pdf, description, font_size=8.5)

        pdf.set_left_margin(old_l_margin)
        pdf.set_right_margin(old_r_margin)
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
