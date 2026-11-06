"""
services.folder_agent.extract — Turn files into indexable text segments
=======================================================================
``extract(path)`` returns the readable text of a file as segments (one per
PDF page, one for everything else) plus the indexing ``kind``. Pictures are
read with DeskMate's zero-download native OCR (Apple Vision on macOS,
Windows.Media.Ocr on Windows), so screenshots and scanned receipts become
searchable without a vision model.

Also hosts the lightweight entity extractor the Canvas uses to link files
that mention the same people, organisations and places.
"""

from __future__ import annotations

import re
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from services.folder_agent.fs_service import file_kind

MAX_TEXT_BYTES = 4 * 1024 * 1024        # plain text / code cap
MAX_PDF_BYTES = 200 * 1024 * 1024
MAX_PDF_PAGES = 400
MAX_IMAGE_BYTES = 40 * 1024 * 1024
MAX_SEGMENT_CHARS = 400_000

TEXT_EXTS = set(
    ".txt .md .mdx .mdc .adoc .markdown .rst .log .csv .tsv .json .yaml .yml .toml .xml .ini .cfg .conf .tex .rtf .org "
    ".py .js .ts .tsx .jsx .mjs .cjs .dart .java .kt .swift .go .rs .c .h .cpp .hpp .cs .rb .php .sh .zsh "
    ".bash .ps1 .html .htm .css .scss .sass .vue .svelte .sql .lua .r .scala .ex .exs .hs .pl .sol .graphql "
    ".ipynb .srt .vtt".split()
)
OCR_EXTS = {".png", ".jpg", ".jpeg", ".heic", ".webp", ".tiff", ".tif", ".bmp", ".gif"}
DOC_EXTS = {".pdf", ".docx"}
SUPPORTED_EXTS = TEXT_EXTS | OCR_EXTS | DOC_EXTS


@dataclass
class Segment:
    text: str
    page: int | None = None


@dataclass
class Extraction:
    kind: str
    segments: list[Segment] = field(default_factory=list)
    skipped_reason: str | None = None

    @property
    def text(self) -> str:
        return "\n\n".join(s.text for s in self.segments)


def is_supported(path: Path) -> bool:
    return path.suffix.lower() in SUPPORTED_EXTS


def extract(path: Path) -> Extraction:
    from services.file_copilot.tools import is_secret_path

    ext = path.suffix.lower()
    kind = file_kind(ext)
    if is_secret_path(path):
        return Extraction(kind, skipped_reason="secret")
    size = path.stat().st_size
    if ext == ".pdf":
        if size > MAX_PDF_BYTES:
            return Extraction(kind, skipped_reason="too large")
        return Extraction(kind, _pdf_segments(path))
    if ext == ".docx":
        return Extraction("document", [Segment(docx_text(path))])
    if ext in OCR_EXTS:
        if size > MAX_IMAGE_BYTES:
            return Extraction(kind, skipped_reason="too large")
        return Extraction("image", [Segment(_ocr_text(path))])
    if ext in TEXT_EXTS:
        if size > MAX_TEXT_BYTES:
            return Extraction(kind, skipped_reason="too large")
        with open(path, "rb") as f:
            raw = f.read(MAX_TEXT_BYTES)
        if b"\x00" in raw[:4096]:
            return Extraction(kind, skipped_reason="binary")
        text = raw.decode("utf-8", errors="replace")
        if ext == ".ipynb":
            text = _notebook_text(text)
        return Extraction(kind, [Segment(text[:MAX_SEGMENT_CHARS])])
    return Extraction(kind, skipped_reason="unsupported")


def _pdf_segments(path: Path) -> list[Segment]:
    import pypdf

    reader = pypdf.PdfReader(str(path))
    segments = []
    for i, page in enumerate(reader.pages[:MAX_PDF_PAGES]):
        try:
            text = page.extract_text() or ""
        except Exception:
            text = ""
        if text.strip():
            segments.append(Segment(text, page=i + 1))
    return segments


_DOCX_PARA = re.compile(r"</w:p>")
_XML_TAG = re.compile(r"<[^>]+>")


def docx_text(path: Path) -> str:
    """Text of a .docx without python-docx: paragraphs from word/document.xml."""
    try:
        with zipfile.ZipFile(path) as z:
            xml = z.read("word/document.xml").decode("utf-8", errors="replace")
    except (KeyError, zipfile.BadZipFile, OSError):
        return ""
    xml = xml.replace("<w:tab/>", "\t").replace("<w:br/>", "\n")
    paragraphs = [_XML_TAG.sub("", p) for p in _DOCX_PARA.split(xml)]
    import html

    return "\n".join(html.unescape(p).strip() for p in paragraphs if p.strip())


def _ocr_text(path: Path) -> str:
    try:
        from services.meeting_intelligence.native_screen_ocr import recognize_text

        lines = recognize_text(str(path))
    except Exception:
        lines = []
    return "\n".join(lines)


def _notebook_text(raw: str) -> str:
    import json

    try:
        nb = json.loads(raw)
    except json.JSONDecodeError:
        return raw
    cells = nb.get("cells", [])
    return "\n\n".join("".join(c.get("source", [])) for c in cells if isinstance(c, dict))


# ─── Chunking ────────────────────────────────────────────────────────────────

def chunk_segments(segments: list[Segment], size: int = 1000, overlap: int = 150) -> list[Segment]:
    """Split each segment into ~``size``-char windows, breaking on whitespace."""
    out: list[Segment] = []
    step = max(1, size - overlap)
    for seg in segments:
        text = re.sub(r"[ \t]+", " ", seg.text).strip()
        if not text:
            continue
        i = 0
        while i < len(text):
            end = min(len(text), i + size)
            if end < len(text):
                space = text.rfind(" ", i + step // 2, end)
                if space > i:
                    end = space
            piece = text[i:end].strip()
            if piece:
                out.append(Segment(piece, seg.page))
            if end >= len(text):
                break
            i = max(i + 1, end - overlap)
    return out


# ─── Entities ────────────────────────────────────────────────────────────────

# Proper-noun words are Capitalised (not ALL CAPS: PDF section headers are noise).
_PROPER = re.compile(r"\b([A-Z][a-z][a-zA-Z&'\-]*(?:\s+(?:of\s+|de\s+|van\s+)?[A-Z][a-z][a-zA-Z&'\-]*){1,3})\b")
# 3–5 letter acronyms (AWS, NASA); two-letter ones (OS, UI, GB) are mostly noise.
_ACRONYM = re.compile(r"\b([A-Z]{3,5})\b")
_ENTITY_STOP = {
    "The", "This", "That", "These", "Those", "There", "Then", "When", "Where", "What", "Which", "While",
    "If", "In", "On", "At", "For", "From", "To", "And", "But", "Or", "We", "You", "They", "It", "Our",
    "Your", "Their", "He", "She", "I", "A", "An", "Page", "Table", "Figure", "Section", "Chapter",
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "January", "February",
    "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
}
_ACRONYM_STOP = {"PDF", "HTML", "CSS", "JSON", "HTTP", "HTTPS", "URL", "API", "TODO", "NOTE", "OK", "AM", "PM",
                 "THE", "AND", "FOR", "ID", "UTC", "USD", "EUR", "PNG", "JPG", "SQL", "XML", "CSV",
                 "NOT", "YES", "ALL", "NEW", "END", "TBD", "FAQ", "PS", "CPU", "RAM", "YAML", "TOML"}


def extract_entities(text: str, limit: int = 12) -> dict[str, int]:
    """Named things mentioned at least twice: multi-word proper nouns and acronyms."""
    if not text:
        return {}
    sample = text[:200_000]
    counts: Counter[str] = Counter()
    for m in _PROPER.finditer(sample):
        words = m.group(1).split()
        while words and words[0] in _ENTITY_STOP:
            words = words[1:]
        # A capitalised sentence opener ("Later Acme Corp") isn't part of the name.
        before = sample[max(0, m.start() - 2) : m.start()]
        if len(words) >= 3 and (m.start() == 0 or re.search(r"[.!?\n]\s*$", before)):
            words = words[1:]
        if len(words) >= 2:
            counts[" ".join(words)] += 1
    for m in _ACRONYM.finditer(sample):
        if m.group(1) not in _ACRONYM_STOP:
            counts[m.group(1)] += 1
    return {k: v for k, v in counts.most_common(limit) if v >= 2}
