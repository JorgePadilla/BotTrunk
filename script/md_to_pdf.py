#!/usr/bin/env python3
"""Render one of our markdown docs as a PDF that looks like the site.

A small deliberate subset of markdown — headings, paragraphs, fenced code,
tables, lists, rules, `code`, **bold**, <links> — because the docs are written
in that subset and a general markdown engine would be a dependency we do not
need. Usage: script/md_to_pdf.py docs/funding-an-agent.md docs/out.pdf
"""
import html
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (HRFlowable, ListFlowable, ListItem, PageBreak,
                                Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle)

INK = colors.HexColor("#171717")
MUTED = colors.HexColor("#666666")
HAIRLINE = colors.HexColor("#e5e5e5")
WASH = colors.HexColor("#fafafa")

# reportlab's built-in fonts are WinAnsi; these three are all we use outside it.
SUBS = {"—": "—", "–": "–", "…": "..."}

S = {
    "title": ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=22, leading=27, textColor=INK, spaceAfter=14),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=14, leading=18, textColor=INK, spaceBefore=20, spaceAfter=8),
    "h3": ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=11.5, leading=15, textColor=INK, spaceBefore=14, spaceAfter=6),
    "body": ParagraphStyle("body", fontName="Helvetica", fontSize=10, leading=15.5, textColor=INK, alignment=TA_LEFT, spaceAfter=9),
    "cell": ParagraphStyle("cell", fontName="Helvetica", fontSize=9, leading=13, textColor=INK),
    "cellhead": ParagraphStyle("cellhead", fontName="Helvetica-Bold", fontSize=9, leading=13, textColor=MUTED),
    "code": ParagraphStyle("code", fontName="Courier", fontSize=8.8, leading=13, textColor=INK, backColor=WASH,
                           borderColor=HAIRLINE, borderWidth=0.5, borderPadding=8, spaceBefore=4, spaceAfter=12),
    "footer": ParagraphStyle("footer", fontName="Helvetica", fontSize=8.5, leading=12, textColor=MUTED),
}


def inline(text):
    """`code`, **bold**, *italic*, <links> and entity-safety, in that order."""
    for src, dst in SUBS.items():
        text = text.replace(src, dst)
    text = html.escape(text)
    text = re.sub(r"`([^`]+)`", r'<font face="Courier" size="9">\1</font>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![*\w])\*([^*]+)\*(?![*\w])", r"<i>\1</i>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<link href="\2" color="#171717"><u>\1</u></link>', text)
    text = re.sub(r"&lt;(https?://[^&]+)&gt;", r'<link href="\1" color="#171717"><u>\1</u></link>', text)
    return text


def table(rows):
    head, body = rows[0], rows[1:]
    data = [[Paragraph(inline(c), S["cellhead"]) for c in head]]
    data += [[Paragraph(inline(c), S["cell"]) for c in r] for r in body]
    widths = column_widths(head)
    t = Table(data, colWidths=widths, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("LINEBELOW", (0, 0), (-1, -1), 0.5, HAIRLINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (0, -1), 0),
        ("RIGHTPADDING", (-1, 0), (-1, -1), 0),
    ]))
    return t


def column_widths(head):
    usable = 6.5 * inch
    n = len(head)
    if n == 2:
        return [usable * 0.34, usable * 0.66]
    if n == 3:
        return [usable * 0.2, usable * 0.22, usable * 0.58]
    return [usable / n] * n


def convert(md_path, pdf_path):
    lines = open(md_path, encoding="utf-8").read().split("\n")
    flow, i = [], 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("```"):
            block, i = [], i + 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i])
                i += 1
            body = "<br/>".join(html.escape(b).replace(" ", "&nbsp;") or "&nbsp;" for b in block)
            flow.append(Paragraph(body, S["code"]))
        elif line.startswith("| ") and i + 1 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= set("-: "):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not set("".join(cells)) <= set("-: "):
                    rows.append(cells)
                i += 1
            flow.extend([table(rows), Spacer(1, 12)])
            continue
        elif line.startswith("# "):
            flow.append(Paragraph(inline(line[2:]), S["title"]))
        elif line.startswith("## "):
            flow.append(Paragraph(inline(line[3:]), S["h2"]))
        elif line.startswith("### "):
            flow.append(Paragraph(inline(line[4:]), S["h3"]))
        elif line.strip() == "---":
            flow.extend([Spacer(1, 6), HRFlowable(width="100%", color=HAIRLINE, thickness=0.5), Spacer(1, 10)])
        elif re.match(r"^\s*[-*] |^\s*\d+\. ", line):
            items = []
            bullet = "1" if re.match(r"^\s*\d+\. ", line) else "bullet"
            while i < len(lines) and re.match(r"^\s*([-*]|\d+\.) ", lines[i]):
                text = re.sub(r"^\s*([-*]|\d+\.)\s+", "", lines[i])
                # A wrapped bullet continues on an indented line that is not
                # itself a new bullet; two spaces is enough, which is how these
                # docs are written.
                while (i + 1 < len(lines) and re.match(r"^\s{2,}\S", lines[i + 1])
                       and not re.match(r"^\s*([-*]|\d+\.)\s", lines[i + 1])):
                    i += 1
                    text += " " + lines[i].strip()
                items.append(ListItem(Paragraph(inline(text), S["body"]), leftIndent=16))
                i += 1
            flow.append(ListFlowable(items, bulletType=bullet, bulletFontSize=9, leftIndent=14, bulletColor=MUTED))
            continue
        elif line.strip():
            para, buf = [], []
            while i < len(lines) and lines[i].strip() and not lines[i].startswith(("#", "|", "```", "- ", "* ")):
                buf.append(lines[i].strip())
                i += 1
            para = " ".join(buf)
            style = S["footer"] if para.startswith(("Full setup", "Protocol,", "Package:")) else S["body"]
            flow.append(Paragraph(inline(para), style))
            continue

        i += 1

    doc = SimpleDocTemplate(pdf_path, pagesize=LETTER, title="Funding an agent to buy on BotTrunk",
                            author="BotTrunk", leftMargin=inch, rightMargin=inch, topMargin=0.9 * inch, bottomMargin=0.9 * inch)
    doc.build(flow, onLaterPages=stamp, onFirstPage=stamp)
    print(f"wrote {pdf_path}")


def stamp(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(inch, 0.6 * inch, "bottrunk.com")
    canvas.drawRightString(7.5 * inch, 0.6 * inch, str(doc.page))
    canvas.restoreState()


if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2])
