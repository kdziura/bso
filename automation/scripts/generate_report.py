#!/usr/bin/env python3

import sys
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from xml.etree import ElementTree

def xml_to_text(xml_file):
    root = ElementTree.parse(xml_file).getroot()
    lines = []
    for result in root.findall(".//result"):
        host = result.findtext("host")
        name = result.findtext("name")
        severity = result.findtext("severity")
        lines.append(f"{host:15} {name:40} Severity: {severity}")
    return lines

def make_pdf(lines, output):
    c = canvas.Canvas(output, pagesize=A4)
    width, height = A4
    y = height - 40
    c.setFont("Helvetica", 10)
    for ln in lines:
        if y < 40:
            c.showPage()
            y = height - 40
        c.drawString(40, y, ln)
        y -= 12
    c.save()

if __name__ == "__main__":
    xml_in, pdf_out = sys.argv[1], sys.argv[2]
    text = xml_to_text(xml_in)
    make_pdf(text, pdf_out)
