# Native iPhone keyboard geometry — landscape

Measured from the system keyboard on six iPhone classes. Captures in
`Reference/native-iphone/landscape/`.

**Status: implemented and gated.** `PhoneLandscapeMetrics` carries the table below;
`scripts/parity/iphone-landscape.py compare <shots>` measures a capture directory
against the references and exits non-zero on any violation.

Before this, landscape ran on heuristics that had never been checked against the
system keyboard: `clamp(shorterSide * 0.50, min: 196, max: 220)` for the asked
height, which requested 196.5pt on an iPhone 16 where native's container is 207,
and a key height that fell out of `floor((bounds.height - …) / 4)` — making every
constant native actually uses a function of whatever height the host granted.

## The structural difference

In landscape the system keyboard **does not span the screen**. The container is
inset on both sides, and on notched iPhones the globe and dictation keys sit
*outside* it, in the bottom corners of the safe area. That is why the bottom row
carries three keys on a notched phone and five on an SE.

## Measurements

| Device | Landscape W | Portrait W | Side inset | Key height | Row pitch | Gap | Bottom row |
|---|---|---|---|---|---|---|---|
| iPhone SE 3 | 667 | 375 | 72 | 32.0 | 40.0 | 6 | 5 keys |
| iPhone 16 | 852 | 393 | 79 | 27.3 | 35.2 | 6 | 3 keys |
| iPhone 17 Pro | 874 | 402 | 79 | 27.3 | 35.2 | 6 | 3 keys |
| iPhone Air | 912 | 420 | 121 | 27.3 | 35.2 | 6 | 3 keys |
| iPhone 16 Plus | 932 | 430 | 121 | 27.3 | 35.2 | 6 | 3 keys |
| iPhone 17 Pro Max | 956 | 440 | 121 | 27.3 | 35.2 | 6 | 3 keys |

Rows are 10 / 9 / 9 / n, the same shape as portrait.

## What the numbers say

**Key height and pitch are constants, not proportions.** 27.3 and 35.2 hold across
852→956 — a 12% span in width — exactly the class-quantization iPhone portrait
already showed (43pt keys below ~410pt, 45pt above). Do not scale them.

**The side inset is class-quantized on the SAME boundary as portrait.** 79pt for
portrait widths below ~410 (393, 402), 121pt at and above it (420, 430, 440). The
iPhone portrait geometry class boundary is ~410pt, and landscape reuses it. That is
a strong hint the two are the same underlying device class.

**The SE is its own class.** No safe-area inset to work around, so it gets a
smaller side inset (72) and *larger* keys (32 high, 40 pitch) than every notched
phone. A home-button phone is not simply a small notched phone here.

Letter-key width is what absorbs the remainder: 64.0 / 66.2 / 61.6 / 63.6 / 66.0
across the five notched devices. It is not constant, and it is not monotonic in
width, because the inset jumps between classes.

## The container, and how to probe it

**Container height is 207.0pt on every notched iPhone and 205.0 on the SE.** Another
class constant, invariant across the same 852 → 956 span.

Getting that number took three attempts, and the failures are instructive:

* Scanning a column at mid-width for "the first row that differs from the page"
  finds the host's white text field, not the keyboard. That is what the first
  attempt reported.
* Moving the column just left of the first key fixes the wide-inset classes but not
  the narrow ones, because the container's left edge moves with the class.
* Scanning **up** from the first key row while rows still match the backdrop hits
  the prediction strip's separators and text, which sit between the container edge
  and the keys. It reported 207 / 184.7 / 207 / 184.7, alternating by device.

What works: sample the backdrop just above the first key row, walk up comparing the
row **median** (which ignores thin separators and glyphs), and require the change to
persist for 3pt before believing it. That is what `scripts/parity/iphone-landscape.py`
does, and it returns the same answer on all six devices.

## The derived model

| | SE (667) | notched (852-956) |
|---|---|---|
| container | 205.0 | 207.0 |
| key block (4 rows) | 152.0 | 133.3 |
| last row to screen edge | 4 | 25 |
| zone above the keys | 49.0 | 48.7 |

The 25pt under a notched phone's last row is the 21pt home-indicator safe area plus
4pt; an SE has no safe area and shows the 4pt directly. So the inset applied below
the key block is **4pt on both**, because our view already stops above the safe area.

`key_top` sits **158pt above the screen bottom on every notched iPhone** and 156 on
the SE. That is the single most useful check that an implementation is right.

Home-button phones are selected on **aspect ratio**, not width: 16:9 against the
~19.5:9 of every notched phone. Width cannot separate them, since an SE is 375pt and
an iPhone 16 is 393pt, both under the 410pt portrait boundary. Unlike portrait,
where the two share a class, landscape gives the SE its own geometry.

## Capture recipe

Unlike iPad, iPhone **honours in-app orientation locks**, so `--landscape` on the
debug harness works and all six devices capture in parallel (`capture-native.sh`,
about 90 seconds for the set). Two things still bite:

* `simctl io screenshot` returns the raw display buffer — portrait-shaped with the
  UI rotated inside it. De-rotate the PNG afterwards.
* The one-time QuickPath sheet ("Speed up your typing by sliding your finger…")
  covers the entire keyboard. Suppress it by writing
  `DidShowContinuousPathIntroduction` before launching.
