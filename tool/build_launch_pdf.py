"""Renders the launch docs to a single PDF via headless Chrome.

Chrome rather than a PDF library because it is already on this machine and
its print engine handles the tables, the three scripts and the code blocks
without any of them needing special handling.

    python3 tool/build_launch_pdf.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import markdown

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
SOURCES = [
    "docs/launch/PRODUCTION_LAUNCH.md",
    "docs/launch/STORE_LISTING.md",
]
OUT = "docs/launch/Word-Search-Master-Launch-Pack.pdf"

CSS = """
@page { size: A4; margin: 18mm 16mm; }
body {
  font-family: "Segoe UI", system-ui, sans-serif;
  font-size: 10.5pt; line-height: 1.55; color: #1d2320; max-width: 100%;
}
h1 { font-size: 21pt; color: #121815; border-bottom: 3px solid #E8A33D;
     padding-bottom: 6px; margin-top: 0; page-break-after: avoid; }
h2 { font-size: 15pt; color: #121815; margin-top: 22px;
     border-bottom: 1px solid #dcd6c8; padding-bottom: 3px;
     page-break-after: avoid; }
h3 { font-size: 12pt; color: #3a4340; margin-top: 16px;
     page-break-after: avoid; }
code { background: #f3efe6; padding: 1px 4px; border-radius: 3px;
       font-family: Consolas, monospace; font-size: 9pt; }
pre { background: #121815; color: #f3efe6; padding: 10px 12px;
      border-radius: 5px; overflow-x: auto; page-break-inside: avoid; }
pre code { background: none; color: inherit; font-size: 8.5pt; }
table { border-collapse: collapse; width: 100%; margin: 10px 0;
        page-break-inside: avoid; font-size: 9.5pt; }
th, td { border: 1px solid #d8d2c4; padding: 5px 8px; text-align: left;
         vertical-align: top; }
th { background: #f3efe6; }
blockquote { border-left: 3px solid #E8A33D; margin-left: 0;
             padding-left: 12px; color: #4a534f; }
li { margin: 2px 0; }
hr { border: none; border-top: 1px solid #dcd6c8; margin: 22px 0; }
.page-break { page-break-before: always; }
a { color: #8a5a12; }
"""


def main() -> int:
    if not os.path.exists(CHROME):
        print(f"Chrome not found at {CHROME}", file=sys.stderr)
        return 1

    parts = []
    for i, src in enumerate(SOURCES):
        with open(src, encoding="utf-8") as handle:
            body = markdown.markdown(
                handle.read(),
                extensions=["tables", "fenced_code", "toc"],
            )
        # Each source starts a fresh page, so the pack reads as two chapters
        # rather than one run-on document.
        if i:
            parts.append('<div class="page-break"></div>')
        parts.append(body)

    html = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<style>{CSS}</style></head><body>{''.join(parts)}</body></html>"
    )

    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "launch.html")
        with open(page, "w", encoding="utf-8") as handle:
            handle.write(html)

        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        subprocess.run(
            [
                CHROME,
                "--headless",
                "--disable-gpu",
                "--no-pdf-header-footer",
                f"--print-to-pdf={os.path.abspath(OUT)}",
                f"file:///{page.replace(os.sep, '/')}",
            ],
            check=True,
            capture_output=True,
        )

    size = os.path.getsize(OUT)
    print(f"{OUT}  ({size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
