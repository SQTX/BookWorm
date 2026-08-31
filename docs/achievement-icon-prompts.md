# Achievement icon prompts

Ready to paste into an image model, one icon at a time. The **style block is fixed** and
must go in verbatim with every request — generating 35 icons across separate calls is
where a set falls apart, and repeating the style word for word is the only thing holding
them together.

Work through one family at a time rather than in catalogue order. A family shares a visual
motif, so consecutive generations reinforce each other; jumping between families invites
drift. If the model supports it, feed a finished icon back in as a style reference for the
next one in the same family.

Filenames matter: save each result as the name given above its prompt. See
[`achievements.md`](achievements.md) for what each achievement means and how to wire the
file in.

---

## The style block

Paste this before every subject line.

```text
You are producing one icon from a set of 35 for a desktop reading-tracker application called BookWorm. Every icon in the set must look like it came from the same hand, so the style block below is fixed and must be followed exactly.

STYLE — identical for every icon in the set:
- Flat vector illustration. Bold, solid, filled shapes. No gradients, no photorealism, no 3D rendering, no bevels, no glossy highlights.
- Fully transparent background. Nothing behind the subject — no circle, no plate, no card, no backdrop.
- No drop shadow cast onto the background. The icon will be composited over three different app themes and a shadow would only work on one of them.
- Palette: a violet accent (#7C5CE0) as the lead colour, a warm brass (#C99A3F) for emphasis, a deep ink (#241F33) for structure and weight, and one soft parchment (#EFE9DC) for paper surfaces. Use these four; add at most one further hue if the subject genuinely needs it.
- Every shape must be legible at 56 × 56 pixels. No line thinner than 6px at 256 × 256. No fine hatching, no small internal detail, no texture.
- Strong readable silhouette. The same artwork is shown at 28% opacity when the achievement is locked, so the shape alone has to carry it.
- Centred, symmetrical weight, with roughly 12% clear margin on all four sides.
- Absolutely no text, letters, numbers, digits, words or lettering of any kind anywhere in the image. Book spines and covers must be blank.
- Front-on or very slightly three-quarter view. Consistent across the set.

OUTPUT: a single 256 × 256 PNG with an alpha channel.

SUBJECT for this icon:
```

---

## The 35 subjects

### The shelf

**`library_10.png`** — A Shelf Begins · *Półka się zaczyna*  
<sub>Ten books in your library</sub>

```text
Three books leaning together on one short wall shelf, the first gap on a new shelf.
```

**`library_25.png`** — Filling Out · *Zapełnia się*  
<sub>Twenty-five books in your library</sub>

```text
A single shelf filled end to end, one volume tipped out of line.
```

**`library_50.png`** — A Proper Collection · *Prawdziwa kolekcja*  
<sub>Fifty books in your library</sub>

```text
Two stacked shelves packed solid, a couple of books laid flat on top.
```

**`library_100.png`** — Private Library · *Biblioteka domowa*  
<sub>A hundred books in your library</sub>

```text
A tall four-shelf bookcase, every shelf full, seen straight on.
```

**`library_250.png`** — Wall to Wall · *Od ściany do ściany*  
<sub>Two hundred and fifty books in your library</sub>

```text
A wall of bookcases seen head on, running past the edges of the frame.
```

**`library_500.png`** — You Need Another Room · *Potrzebujesz kolejnego pokoju*  
<sub>Five hundred books in your library</sub>

```text
A bookcase with a doorway cut through it, books continuing into the room beyond.
```

### Books finished

**`read_1.png`** — The First One · *Pierwsza*  
<sub>Finish your first book</sub>

```text
One closed book with a ribbon bookmark hanging from the very last page.
```

**`read_5.png`** — Getting Somewhere · *Coś się dzieje*  
<sub>Finish five books</sub>

```text
Five closed books in a neat stack, ribbon trailing from the top one.
```

**`read_10.png`** — Double Figures · *Dwucyfrowo*  
<sub>Finish ten books</sub>

```text
A stack of ten books, the top one sitting slightly askew.
```

**`read_25.png`** — Well Read · *Oczytany*  
<sub>Finish twenty-five books</sub>

```text
A leaning stack tall enough to bow, a small laurel sprig resting against it.
```

**`read_50.png`** — Half a Hundred · *Pół setki*  
<sub>Finish fifty books</sub>

```text
Two book stacks side by side with a hanging medal between them.
```

**`read_100.png`** — Centurion · *Centurion*  
<sub>Finish a hundred books</sub>

```text
A laurel wreath encircling a single closed book, roman in feel.
```

**`read_250.png`** — Bookworm · *Mól książkowy*  
<sub>Finish two hundred and fifty books</sub>

```text
A bookworm curling through the pages of a tall stack, head emerging at the top.
```

### Books finished this year

**`year_12.png`** — A Book a Month · *Książka na miesiąc*  
<sub>Finish twelve books in one year</sub>

```text
A calendar page whose grid squares are tiny book spines, twelve of them marked.
```

**`year_24.png`** — Two a Month · *Dwie na miesiąc*  
<sub>Finish twenty-four books in one year</sub>

```text
A calendar page with two book spines filling each row.
```

**`year_52.png`** — A Book a Week · *Książka na tydzień*  
<sub>Finish fifty-two books in one year</sub>

```text
A ring of fifty-two week marks encircling one open book.
```

### Pages

**`pages_1000.png`** — A Thousand Pages · *Tysiąc stron*  
<sub>Read a thousand pages</sub>

```text
A thick stack of loose paper sheets, edges slightly uneven.
```

**`pages_10000.png`** — Ten Thousand · *Dziesięć tysięcy*  
<sub>Read ten thousand pages</sub>

```text
A paper stack with loose sheets lifting off the top and drifting away.
```

**`pages_50000.png`** — Fifty Thousand · *Pięćdziesiąt tysięcy*  
<sub>Read fifty thousand pages</sub>

```text
A towering ream of paper bowing under its own weight.
```

**`pages_100000.png`** — Six Figures · *Sześciocyfrowo*  
<sub>Read a hundred thousand pages</sub>

```text
A mountain of paper, sheets cascading down one side like a slope.
```

### Series

**`series_1.png`** — Saw It Through · *Do samego końca*  
<sub>Finish every book in a series</sub>

```text
Three matched book spines in a row, joined by one continuous band across them.
```

**`series_5.png`** — Completionist · *Kompletysta*  
<sub>Finish five series</sub>

```text
Five matched spine sets arranged in a row, linked by a chain motif.
```

**`series_10.png`** — No Loose Ends · *Żadnych niedokończonych wątków*  
<sub>Finish ten series</sub>

```text
Interlocking jigsaw pieces whose faces are book spines, the last piece dropping in.
```

### Breadth

**`genres_5.png`** — Broadening Out · *Poszerzanie horyzontów*  
<sub>Finish books in five genres</sub>

```text
Five books of visibly different shapes and thicknesses fanned out.
```

**`genres_10.png`** — Catholic Taste · *Szerokie gusta*  
<sub>Finish books in ten genres</sub>

```text
A colour wheel built from book spines radiating from the centre.
```

**`genres_20.png`** — Omnivore · *Wszystkożerny*  
<sub>Finish books in twenty genres</sub>

```text
A globe whose surface is made of open book pages.
```

### Habit

**`streak_7.png`** — Seven Days · *Siedem dni*  
<sub>Read on seven days in a row</sub>

```text
A small steady flame above an open book, seven tally marks beneath.
```

**`streak_30.png`** — A Month Straight · *Miesiąc bez przerwy*  
<sub>Read on thirty days in a row</sub>

```text
A taller flame above an open book with a crescent moon behind it.
```

**`streak_100.png`** — A Hundred Days · *Sto dni*  
<sub>Read on a hundred days in a row</sub>

```text
A flame held inside a struck badge or coin.
```

**`streak_365.png`** — Every Single Day · *Każdego dnia*  
<sub>Read on three hundred and sixty-five days in a row</sub>

```text
A flame at the centre of a ring split between sun rays and moon phases.
```

### Revisiting

**`reread_1.png`** — Worth Another Look · *Warto wrócić*  
<sub>Read a book for the second time</sub>

```text
A closed book with one circular return arrow sweeping around it.
```

**`reread_5.png`** — Old Friends · *Starzy znajomi*  
<sub>Reread five times over your library</sub>

```text
A book with several arrows orbiting it at different radii.
```

### Keeping records

**`rated_25.png`** — An Opinion on Everything · *Opinia o wszystkim*  
<sub>Rate twenty-five books you have finished</sub>

```text
A closed book with a row of stars settling onto its cover.
```

**`notes_10.png`** — Marginalia · *Notatki na marginesie*  
<sub>Save ten quotes or highlights</sub>

```text
A quill resting on a bookmark that carries a large quotation mark.
```

**`notes_100.png`** — The Commonplace Book · *Sylwa*  
<sub>Save a hundred quotes or highlights</sub>

```text
A fat bound commonplace book overflowing with slips of paper wedged between pages.
```

---

## If the set drifts

Separate generations wander even with an identical style block. Three things that help,
in the order worth trying:

1. **Regenerate the outlier, not the set.** One icon that came back glossy or off-palette
   is cheaper to redo than to match everything else to it.
2. **Name the reference explicitly.** Append to the style block: *"Match the flat fill
   weight, palette and line thickness of the attached image exactly."* and attach an icon
   you are happy with.
3. **Ask for a family in one image.** A 2×3 or 1×4 sheet generated in a single call is far
   more internally consistent than the same icons generated separately — then cut it up.
   Say *"a grid of N icons on one transparent background, evenly spaced, no labels"*.

A whole family redrawn is still only three to seven icons.
