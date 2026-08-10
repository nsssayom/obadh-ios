# Native iPhone keyboard geometry — landscape

Measured from the system keyboard on six iPhone classes. Captures in
`Reference/native-iphone/landscape/`.

**Status: measured, NOT implemented.** Portrait iPhone is already native-accurate
and gated by `scripts/parity/run.sh` (24 cells, passing). Landscape still runs on
the original heuristics — `clamp(shorterSide * 0.50, min: 196, max: 220)` in
`preferredKeyboardHeight` and `clamp(bounds.height * 0.032, …)` in `metrics(for:)`
— which were never checked against native. These numbers are what it takes to fix
that.

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

## Open before implementing

The container's total height is not yet trustworthy. The probe used to measure it
sampled a column at mid-width, which on these screens crosses the host's white text
field rather than the keyboard backdrop, so the "container top" it reported is the
text field's top edge. Re-probe using a column inside the container but clear of
the text field — or reuse the mid-gray `--measure-bg` backdrop the iPhone parity
suite already relies on for exactly this disambiguation — before deriving
`preferredKeyboardHeight`.

## Capture recipe

Unlike iPad, iPhone **honours in-app orientation locks**, so `--landscape` on the
debug harness works and all six devices capture in parallel (`capture-native.sh`,
about 90 seconds for the set). Two things still bite:

* `simctl io screenshot` returns the raw display buffer — portrait-shaped with the
  UI rotated inside it. De-rotate the PNG afterwards.
* The one-time QuickPath sheet ("Speed up your typing by sliding your finger…")
  covers the entire keyboard. Suppress it by writing
  `DidShowContinuousPathIntroduction` before launching.
