#!/usr/bin/env python3
"""Regenerate docs/achievements.md and docs/achievement-icon-prompts.md.

Both files claim to be generated from the source rather than written by hand,
and that claim is only worth anything if regenerating them is one command. Run
this after adding, removing or renaming an achievement:

    python3 desktop/tools/gen-achievement-docs.py

Everything except the icon subjects is read out of
`desktop/src/achievements/achievementcatalog.cpp` and
`desktop/qml/theme/translations.js`. The subjects live in SUBJECTS below, since
there is nowhere in the code they could be derived from — a new achievement
needs a line there or the script stops and says which one is missing.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "desktop/src/achievements/achievementcatalog.cpp"
TRANSLATIONS = ROOT / "desktop/qml/theme/translations.js"
DOCS = ROOT / "docs"

# What each icon should depict. The only content here that is not in the source.
SUBJECTS = {
    "library_10": "three books leaning together on one short wall shelf, the first gap on a new shelf",
    "library_25": "a single shelf filled end to end, one volume tipped out of line",
    "library_50": "two stacked shelves packed solid, a couple of books laid flat on top",
    "library_100": "a tall four-shelf bookcase, every shelf full, seen straight on",
    "library_250": "a wall of bookcases seen head on, running past the edges of the frame",
    "library_500": "a bookcase with a doorway cut through it, books continuing into the room beyond",
    "library_1000": "a column of stacked books standing in for a structural pillar, a ceiling beam resting on top of it",
    "read_1": "one closed book with a ribbon bookmark hanging from the very last page",
    "read_5": "five closed books in a neat stack, ribbon trailing from the top one",
    "read_10": "a stack of ten books, the top one sitting slightly askew",
    "read_25": "a leaning stack tall enough to bow, a small laurel sprig resting against it",
    "read_50": "two book stacks side by side with a hanging medal between them",
    "read_100": "a laurel wreath encircling a single closed book, Roman in feel",
    "read_250": "a bookworm curling through the pages of a tall stack, head emerging at the top",
    "year_12": "a calendar page whose grid squares are tiny book spines, twelve of them marked",
    "year_24": "a calendar page with two book spines filling each row",
    "year_52": "a ring of fifty-two week marks encircling one open book",
    "pages_1000": "a thick stack of loose paper sheets, edges slightly uneven",
    "pages_10000": "a paper stack with loose sheets lifting off the top and drifting away",
    "pages_50000": "a towering ream of paper bowing under its own weight",
    "pages_100000": "a mountain of paper, sheets cascading down one side like a slope",
    "series_1": "three matched book spines in a row, joined by one continuous band across them",
    "series_5": "five matched spine sets arranged in a row, linked by a chain motif",
    "series_10": "interlocking jigsaw pieces whose faces are book spines, the last piece dropping in",
    "genres_5": "five books of visibly different shapes and thicknesses fanned out",
    "genres_10": "a colour wheel built from book spines radiating from the centre",
    "genres_20": "a globe whose surface is made of open book pages",
    "streak_7": "a small steady flame above an open book, seven tally marks beneath",
    "streak_30": "a taller flame above an open book with a crescent moon behind it",
    "streak_100": "a flame held inside a struck badge or coin",
    "streak_365": "a flame at the centre of a ring split between sun rays and moon phases",
    "reread_1": "a closed book with one circular return arrow sweeping around it",
    "reread_5": "a book with several arrows orbiting it at different radii",
    "rated_25": "a closed book with a row of stars settling onto its cover",
    "notes_10": "a quill resting on a bookmark that carries a large quotation mark",
    "notes_100": "a fat bound commonplace book overflowing with slips of paper wedged between pages",
}

RULES = {
    "LibrarySize": "Books in the library, whatever their status.",
    "BooksRead": "Books whose status is `read`.",
    "BooksReadThisYear": "Finished with an end date inside the current calendar year.",
    "PagesRead": "Page counts summed over finished books.",
    "SeriesCompleted": "Series of more than one book where every part is read.",
    "GenresRead": "Distinct genres among finished books.",
    "LongestStreak": "Longest run of consecutive days carrying a reading session.",
    "Rereads": "Every finish past the first, summed across the library.",
    "BooksRated": "Finished books that carry a rating.",
    "NotesTaken": "Favourite quotes and highlights, together.",
}

NOTES = {
    "The shelf": "Owning, not reading — these fire on acquisition, so they are the first thing a new user meets.",
    "Books finished": "The spine of the set. Seven steps from one book to two hundred and fifty.",
    "Books finished this year": "Resets every January. The only family that can become unreachable and come back.",
    "Pages": "Volume rather than count — a long book weighs more here than a short one.",
    "Series": "Completion. A series of one does not count.",
    "Breadth": "Range instead of depth, counted on distinct genres among finished books.",
    "Habit": "Consecutive reading days, from a week to a full year.",
    "Revisiting": "Rereads. The rarest family in an ordinary library.",
    "Keeping records": "Using the app's own apparatus — ratings, quotes, highlights.",
}

ENTRY = re.compile(
    r'\{\s*QStringLiteral\("([a-z0-9_]+)"\),\s*Metric::(\w+),\s*(\d+),\s*'
    r'QStringLiteral\("([^"]+)"\),\s*QStringLiteral\("([^"]+)"\),\s*PLACEHOLDER\s*\}',
    re.S,
)

STYLE_BLOCK = """You are producing one icon from a set of {n} for a desktop reading-tracker application called BookWorm. Every icon in the set must look like it came from the same hand, so the style block below is fixed and must be followed exactly.

STYLE — identical for every icon in the set:
- Flat vector illustration. Bold, solid, filled shapes. No gradients, no photorealism, no 3D rendering, no bevels, no glossy highlights.
- Fully transparent background. Nothing behind the subject — no circle, no plate, no card, no backdrop.
- No drop shadow cast onto the background. The icon will be composited over three different app themes and a shadow would only work on one of them.
- Palette: a violet accent (#7C5CE0) as the lead colour, a warm brass (#C99A3F) for emphasis, a deep ink (#241F33) for structure and weight, and one soft parchment (#EFE9DC) for paper surfaces. Use these four; add at most one further hue if the subject genuinely needs it.
- Every shape must be legible at 56 x 56 pixels. No line thinner than 6px at 256 x 256. No fine hatching, no small internal detail, no texture.
- Strong readable silhouette. The same artwork is shown at 28% opacity when the achievement is locked, so the shape alone has to carry it.
- Centred, symmetrical weight, with roughly 12% clear margin on all four sides.
- Absolutely no text, letters, numbers, digits, words or lettering of any kind anywhere in the image. Book spines and covers must be blank.
- Front-on or very slightly three-quarter view. Consistent across the set.

OUTPUT: a single 256 x 256 PNG with an alpha channel.

SUBJECT for this icon:"""


def load():
    """Every achievement, in catalogue order, with its Polish strings attached."""
    src = CATALOG.read_text()
    js = TRANSLATIONS.read_text()

    polish = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*:\s*\n?\s*"((?:[^"\\]|\\.)*)"', js):
        polish.setdefault(m.group(1), m.group(2))

    # The `// ── Name ──` comments are the family headings, and their position in
    # the file is what assigns each entry to one.
    headings = {m.start(): m.group(1) for m in re.finditer(r"//\s*──\s*(.+?)\s*─", src)}

    out, current = [], None
    for m in ENTRY.finditer(src):
        for pos in sorted(headings):
            if pos < m.start():
                current = headings[pos]
        out.append({
            "key": m.group(1), "metric": m.group(2), "threshold": int(m.group(3)),
            "title": m.group(4), "titlePl": polish.get(m.group(4), ""),
            "desc": m.group(5), "descPl": polish.get(m.group(5), ""),
            "group": current,
        })
    return out


def check(entries):
    """Stop on anything that would produce a quietly wrong document."""
    problems = []
    for e in entries:
        if not e["titlePl"]:
            problems.append(f'{e["key"]}: no Polish title for "{e["title"]}"')
        if not e["descPl"]:
            problems.append(f'{e["key"]}: no Polish description for "{e["desc"]}"')
        if e["key"] not in SUBJECTS:
            problems.append(f'{e["key"]}: no icon subject — add one to SUBJECTS in this script')
        if e["metric"] not in RULES:
            problems.append(f'{e["key"]}: metric {e["metric"]} has no rule text')
        if e["group"] not in NOTES:
            problems.append(f'{e["key"]}: family "{e["group"]}" has no note')

    known = {e["key"] for e in entries}
    for key in SUBJECTS:
        if key not in known:
            problems.append(f"{key}: subject with no achievement — stale entry in SUBJECTS?")

    if problems:
        print("Cannot generate:", file=sys.stderr)
        for p in problems:
            print("  -", p, file=sys.stderr)
        sys.exit(1)


def reference(entries, families):
    n = len(entries)
    out = [f"""# Achievements

Every achievement in BookWorm, with the name it shows in both languages, the rule
that unlocks it, and the filename its artwork has to take.

**Generated, not written by hand.** Run
`python3 desktop/tools/gen-achievement-docs.py` after changing the catalogue. The
definitions live in
[`desktop/src/achievements/achievementcatalog.cpp`](../desktop/src/achievements/achievementcatalog.cpp)
and the Polish strings in
[`desktop/qml/theme/translations.js`](../desktop/qml/theme/translations.js).

{n} achievements across {len(families)} families. Artwork prompts for all of them are in
[`achievement-icon-prompts.md`](achievement-icon-prompts.md).

## Artwork specification

| | |
| --- | --- |
| Format | PNG with transparency |
| Source size | 256 x 256 |
| Displayed at | 56 x 56, in both the notification panel and the list |
| Corners | square — the app rounds and crops |
| Filename | exactly the `Filename` column below |
| Location | `desktop/src/img/achievements/` |

Two constraints that decide how the art should be drawn:

- The icon sits on **whichever of three themes the user picked** — minimalist dark,
  minimalist light, or classic. A shape that relies on a pale background disappears in
  one of them.
- A locked achievement shows the **same artwork at 28% opacity**, not a different
  picture. The silhouette has to stay recognisable when it is barely there.

Both argue for solid shapes over fine linework.

## Wiring one up

1. Drop the PNG into `desktop/src/img/achievements/`.
2. Add it to `RESOURCES` in `desktop/CMakeLists.txt`. A file on disk but missing from
   that list is not compiled into the `qrc:` and is **silently absent** at runtime — no
   error, no picture.
3. In `achievementcatalog.cpp`, replace that row's `PLACEHOLDER` with
   `QStringLiteral("qrc:/qt/qml/BookWorm/src/img/achievements/<key>.png")`.
4. Reconfigure CMake — the resource list changed — then rebuild.

**Partial sets are fine.** Every definition points at the placeholder today, so icons can
land one at a time; an achievement without its own artwork keeps showing the placeholder
rather than breaking.

---
"""]
    for family in families:
        members = [e for e in entries if e["group"] == family]
        out.append(f"## {family}\n")
        out.append(f"{NOTES[family]}\n")
        for metric in dict.fromkeys(m["metric"] for m in members):
            out.append(f"- `{metric}` — {RULES[metric]}")
        out.append("")
        out.append("| Filename | Title | Tytuł | Description | Opis | Target |")
        out.append("| --- | --- | --- | --- | --- | ---: |")
        for e in members:
            out.append(
                f'| `{e["key"]}.png` | {e["title"]} | {e["titlePl"]} '
                f'| {e["desc"]} | {e["descPl"]} | {e["threshold"]:,} |'
            )
        out.append("")
    return "\n".join(out)


def prompts(entries, families):
    n = len(entries)
    out = [f"""# Achievement icon prompts

Ready to paste into an image model, one icon at a time. The **style block is fixed** and
must go in verbatim with every request — generating {n} icons across separate calls is
where a set falls apart, and repeating the style word for word is the only thing holding
them together.

Work through one family at a time rather than in catalogue order. A family shares a visual
motif, so consecutive generations reinforce each other; jumping between families invites
drift. If the model supports it, feed a finished icon back in as a style reference for the
next one in the same family.

Filenames matter: save each result as the name given above its prompt. See
[`achievements.md`](achievements.md) for what each achievement means and how to wire the
file in.

**Generated** — run `python3 desktop/tools/gen-achievement-docs.py` after changing the
catalogue. Icon subjects live in `SUBJECTS` in that script.

---

## The style block

Paste this before every subject line.

```text
{STYLE_BLOCK.format(n=n)}
```

---

## The {n} subjects
"""]
    for family in families:
        out.append(f"### {family}\n")
        for e in [x for x in entries if x["group"] == family]:
            out.append(f'**`{e["key"]}.png`** — {e["title"]} · *{e["titlePl"]}*  ')
            out.append(f'<sub>{e["desc"]}</sub>\n')
            out.append("```text")
            out.append(SUBJECTS[e["key"]][0].upper() + SUBJECTS[e["key"]][1:] + ".")
            out.append("```\n")

    out.append("""---

## If the set drifts

Separate generations wander even with an identical style block. Three things that help,
in the order worth trying:

1. **Regenerate the outlier, not the set.** One icon that came back glossy or off-palette
   is cheaper to redo than to match everything else to it.
2. **Name the reference explicitly.** Append to the style block: *"Match the flat fill
   weight, palette and line thickness of the attached image exactly."* and attach an icon
   you are happy with.
3. **Ask for a family in one image.** A 2x3 or 1x4 sheet generated in a single call is far
   more internally consistent than the same icons generated separately — then cut it up.
   Say *"a grid of N icons on one transparent background, evenly spaced, no labels"*.

A whole family redrawn is still only three to seven icons.
""")
    return "\n".join(out)


def main():
    entries = load()
    check(entries)
    families = list(dict.fromkeys(e["group"] for e in entries))

    (DOCS / "achievements.md").write_text(reference(entries, families))
    (DOCS / "achievement-icon-prompts.md").write_text(prompts(entries, families))

    # Handy for anything else that wants the catalogue as data.
    print(json.dumps({"count": len(entries), "families": families}, indent=1))


if __name__ == "__main__":
    main()
