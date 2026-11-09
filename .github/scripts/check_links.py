# SPDX-License-Identifier: AGPL-3.0-only
"""Check relative links, images and heading anchors in every Markdown file.

Anchors follow GitHub's slug rules: lowercase, punctuation removed, spaces turned into hyphens.
External URLs are not fetched; many institutional sites block automated clients.
"""

import pathlib
import re
import sys

SKIP = {".git", "node_modules"}


def slug(heading: str) -> str:
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading.strip())
    h = re.sub(r"[`*]", "", h).lower()
    h = "".join(c for c in h if c.isalnum() or c in " -_")
    return h.replace(" ", "-")


def main() -> int:
    files = [p for p in pathlib.Path(".").rglob("*.md") if not SKIP & set(p.parts)]
    anchors = {}
    for p in files:
        anchors[p.resolve()] = {slug(m) for m in re.findall(r"^#{1,6} (.*)$", p.read_text(encoding="utf-8"), re.M)}
    problems = []
    for p in files:
        text = p.read_text(encoding="utf-8")
        for link in re.findall(r"\]\(([^)\s]+)\)", text) + re.findall(r'src="([^"]+)"', text):
            if link.startswith(("http://", "https://", "mailto:")):
                continue
            path, _, frag = link.partition("#")
            target = (p.parent / path).resolve() if path else p.resolve()
            if not target.exists():
                problems.append(f"{p}: missing file {link}")
            elif frag and target.suffix == ".md" and frag not in anchors.get(target, set()):
                problems.append(f"{p}: missing anchor {link}")
    for line in problems:
        print(line)
    print(f"checked {len(files)} Markdown files, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
