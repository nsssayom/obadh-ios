# Native iPadOS keyboard geometry

Measured, not guessed. Every number here comes from a screenshot of the **system**
keyboard in `Reference/native-ipad/`, extracted by `scripts/parity/ipad-geometry.py`.
Re-run `scripts/parity/ipad-geometry.py fit` to reproduce the whole table.

## Why this document exists

iPhone taught us that native key geometry is **class-quantized**, not
width-proportional: 43pt keys below ~410pt, 45pt above. Assuming proportionality
there cost us rows that sat up to 18.5pt off native.

iPad is quantized far more aggressively. The *row structure itself* changes with
width, so a ratio table measured on one iPad is not merely imprecise on another
iPad, it is describing a different keyboard. An earlier attempt (branch
`wip/ipad-native-key-set`) derived ratios from a single iPad Pro 11-inch; those
ratios describe a layout that does not exist on an iPad mini.

## The fleet

Portrait widths of every iPad that can run our iOS 18 deployment target. There is
nothing between 744 and 820, so the compact/standard boundary cannot be probed
further with real hardware — these five widths **are** the fleet.

| Width | Devices | Family |
|---|---|---|
| 744 | iPad mini (A17 Pro), iPad mini 6 | A — compact |
| 820 | iPad (A16), iPad 10, iPad Air 11-inch | B — standard |
| 834 | iPad Pro 11-inch | B — standard |
| 1024 | iPad Air 13-inch, iPad Pro 12.9-inch 6th gen | C — extended |
| 1032 | iPad Pro 13-inch | C — extended |

## The three layout families

**Family A (744) — compact.** Four rows, no tab, no caps lock, `123` rather than
`.?123`. The home row is *indented* and does not span the width. Backspace lives
at the end of row 1, return at the end of row 2.

```
q w e r t y u i o p  ⌫
  a s d f g h j k l  ⏎        <- indented 26.5pt
⇧ z x c v b n m , .  ⇧
🌐 123 🎤 [    space    ] 123 ⌨︎
```

**Family B (820, 834) — standard.** Four rows, gains tab and caps lock, and every
row spans the full width.

```
⇥ q w e r t y u i o p ⌫
⇪ a s d f g h j k l  ⏎
⇧ z x c v b n m , .  ⇧
🌐 .?123 🎤 [  space  ] .?123 ⌨︎
```

**Family C (1024, 1032) — extended.** *Five* rows: a dedicated number row appears,
plus bracket / quote / slash keys, and both shifts are full width.

```
` 1 2 3 4 5 6 7 8 9 0 - =  ⌫
⇥ q w e r t y u i o p [ ] \
⇪ a s d f g h j k l ; '   ⏎
⇧ z x c v b n m , . /     ⇧
🌐 .?123 🎤 [  space  ] .?123 ⌨︎
```

## The horizontal model

Within a family every row satisfies

```
indent + Σ(weightᵢ) · u + (n − 1) · gap + 2 · margin  ==  screenWidth
```

`margin` and `gap` are family constants. `u` — the letter-key width — is not a
constant; it falls out of that equation. This is the falsifiable part of the
model, and it holds: **every row of every device fills its width to 0.00pt.**

| Family | margin | gap | row-2 indent |
|---|---|---|---|
| A | 6.0 | 12.0 | 26.5 (0.486·u) |
| B | 9.0 | 10.0 | 0 |
| C | 3.5 | 7.0 | 0 |

Resulting letter width: 54.5 (744) · 55.0 (820) · 56.1 (834) · 63.4 (1024) · 64.0 (1032).

### Weights

Fitted jointly across both devices in each family by least squares. Worst-case
error against the measured native key, in points, is quoted per family.

**Family A** (u = 54.5) — worst error 0.0pt, single device so the weights are exact.

| Key | Weight |
|---|---|
| letter | 1.000 |
| backspace | 1.239 |
| return | 1.972 |
| left shift | 1.000 |
| right shift | 1.239 |
| globe / 123 / mic | 1.046 |
| space | 5.835 |
| 123 (right) / hide | 1.679 |

**Family B** — worst error **0.56pt**.

| Key | Weight |
|---|---|
| letter | 1.000 |
| tab / backspace | 1.292 |
| caps lock | 1.648 |
| return | 2.120 |
| left shift | 2.179 |
| right shift | 1.589 |
| globe / .?123 / mic | 1.067 |
| space | 7.284 |
| .?123 (right) | 1.589 |
| hide | 1.594 |

**Family C** — worst error **0.15pt** for every key except the space bar, see below.

| Key | Weight |
|---|---|
| letter / digit | 1.000 |
| tab / backspace | 1.601 |
| caps lock / return | 1.853 |
| left shift / right shift | 2.410 |

### The space bar is the flex key

Family C's bottom row is the one place proportional weights break down: the side
keys measure **identically** on 1024 and 1032 (93.5, 93.5, 94, 145, 145) while the
space bar grows by exactly the 8pt the screen grew. A proportional space bar is
2.25pt off; a space bar that absorbs the remainder is exact.

So the rule, applied to every family: **lay out the fixed keys by weight, then give
the space bar whatever is left.** This also guarantees rows fill the width exactly
rather than accumulating rounding error.

## The vertical model

Vertical geometry does **not** scale with width. It is a per-family constant.

| | A (744) | B (820) | B (834) | C (1024) | C (1032) |
|---|---|---|---|---|---|
| key height | 55.5 | 55.0 | 55.5 | 61.0 | 61.0 |
| number-row height | — | — | — | 45.5 | 45.5 |
| row pitch | 64.5 | 63.75 | 64.5 | 68.12 | 68.12 |
| row spacing | 9.0 | 8.75 | 9.0 | 7.12 | 7.12 |
| bottom inset | 28.0 | 28.0 | 28.0 | 24.0 | 24.0 |
| key band height | 249.0 | 246.25 | 249.0 | 318.0 | 318.0 |
| **total keyboard** | **322.5** | **319.5** | **322.5** | **385.5** | **385.5** |

Across the whole 4-row range — 744pt to 834pt, a 12% span in width — key height
moves by 0.5pt and total height by 3pt. Treat both as constants:

* 4-row families: key height **55.3**, row spacing **8.9**, bottom inset **28**.
* 5-row family: key height **61.0** (number row **45.5**), spacing **7.12**, inset **24**.

The residual 45.4pt (43.5pt on family C) between the container top and the first
key row is the **system shortcut bar** — `UITextInputAssistantItem`, drawn by iOS
above the extension on iPad, carrying undo/redo/paste and the prediction chips. It
is not ours to draw and not part of our requested height.

## The 20pt band below an iPad input view

Native's bottom insets (28pt on a 4-row iPad, 24pt on the 13-inch) are measured
from the **screen** edge, and an iPad keyboard extension does not reach it: the
system's keyboard container keeps a 20pt band below our view. Measured identically
on all five widths. It is **not** the safe area, which reports 5pt.

So the inset we apply is native's gap minus that band — 8pt and 4pt. Anchoring to
`view.safeAreaLayoutGuide` instead left the whole key block 25pt high; anchoring to
`view.bottomAnchor` with native's raw 28 left it 20pt high. Both were tried and
measured before this landed.

One more consequence: on iPad the key block must be anchored from the **bottom**,
with the top constraint demoted to slack. iPhone positions from the top (strip
height plus inset), which is how its geometry was calibrated, but the system hands
an iPad extension a view taller than the height it asked for, so a top-driven
block floats above where native's sits.

## Verification

`scripts/parity/ipad-geometry.py compare <shots>` diffs a capture directory against
the stored reference and exits non-zero on any violation. Current state, tolerance
2pt:

| Device | Result | Worst key |
|---|---|---|
| iPad mini (744) | PASS | 0.5pt |
| iPad (820) | PASS | 1.0pt |
| iPad Pro 11-inch (834) | PASS | 1.0pt |
| iPad Air 13-inch (1024) | PASS | 0.5pt |
| iPad Pro 13-inch (1032) | PASS | 0.5pt |

Margins, gaps, row counts and per-row key counts match native exactly on all five.

## Landscape

Captures in `Reference/native-ipad/landscape/`. The single most important finding:

> **The layout family is a property of the DEVICE, not of the current width.**

An iPad Pro 11-inch is 1210pt wide in landscape, well past the extended threshold,
and native still draws it the **4-row standard** layout. An iPad mini at 1133pt
still gets the **compact** layout, indented home row and all. Selecting the family
from the live width would hand every rotated iPad a number row it does not have —
which is why `PadFamily.forPortraitWidth` takes the screen's *shorter* side.

Row structure is identical to each device's portrait layout: 11/10/11/6,
12/11/11/6, 14/14/13/12/6.

| | mini 1133 | iPad 1180 | Pro 11 1210 | Air 13 1366 | Pro 13 1376 |
|---|---|---|---|---|---|
| family | compact | standard | standard | extended | extended |
| margin | 7 | 15 | 15 | 5 | 5 |
| gap | 14 | 14 | 14 | 10 | 10 |
| key height | 75 | 72.5 | 74 | 79 | 79 |
| number row | — | — | — | 59 | 59 |
| row pitch | 85.75 | 84.25 | 85.75 | 88 | 88 |
| row spacing | 10.75 | 11.75 | 11.75 | 9 | 9 |
| bottom inset | 30 | 31 | 31 | 24 | 24 |
| container | 410.5 | 404.5 | 410.5 | 480.5 | 480.5 |

**Letter-row weights are orientation-independent.** Every one of them reproduces
within 0.01 of the portrait fit — tab 1.292/1.294/1.297, caps 1.648/1.644/1.652,
return 2.120/2.117/2.120, left shift 2.179/2.172/2.177, right shift 1.589 exactly
on both. The extended family matches too (tab 1.601, caps 1.853→1.863, shift
2.410→2.423). So landscape reuses the same weight tables.

What *does* change is the command row and the spatial constants. Landscape command
weights, in units of the letter key:

| | compact | standard | extended |
|---|---|---|---|
| globe / mode / emoji | 1.023 | 1.013 | 1.474 |
| space | 5.770 | 7.617 | 6.565 |
| mode (right) / hide | 1.612 | 1.503 | 2.280 |

The extended family's command row is effectively unchanged from portrait
(1.474/6.523/2.276); compact and standard both give the space bar more and the
side keys less than they get in portrait.

Key height in landscape tracks the device's portrait width within a family —
72.5/820 = 0.0884 against 74/834 = 0.0887 — rather than being the flat constant it
is in portrait.

**Not yet implemented.** These numbers are measured and stored; the layout code
still runs landscape through the old heuristics. See the handoff note below.

### Capturing landscape

iPadOS 26 ignores in-app orientation locks (iPad apps are resizable), so
`requestGeometryUpdate` does **not** rotate an iPad simulator — it was tried.
`simctl` has no rotation primitive either. The only route is Simulator's own
**Device ▸ Orientation ▸ Landscape Left** menu command, which means:

* Exactly one simulator may be booted, or the frontmost window is ambiguous.
* Landscape captures are **serial**, unlike the portrait sweep, which runs all
  five at once.
* The menu is disabled until Simulator has a window for the booted device — allow
  several seconds after `open -a Simulator`.
* Launch the app **before** rotating; rotating SpringBoard alone did not stick.
* `simctl io screenshot` returns the raw display buffer, which keeps the panel's
  portrait shape with the UI rotated inside it. De-rotate the PNG afterwards.

## Where Obadh stood before this work

Measured off `Reference/native-ipad/` versus a capture of the shipping build on the
same iPad mini:

| | native | Obadh (main @ 9192cb4) |
|---|---|---|
| margin | 6.0 | 6.5 |
| gap | 12.0 | 7.4 |
| letter width | 54.5 | 66.5 |
| bottom inset | 28.0 | 53.0 |
| row key counts | 11 / 10 / 11 / 6 | 10 / 9 / 9 / 5 |

The width error is structural, not cosmetic: native row 1 carries backspace and
row 2 carries return, so native fits 11 keys where we fit 10, which is why our
letter keys are 22% too wide.

## Reproducing the captures

Screenshots are taken on **freshly erased** simulators. A simulator that has already
presented a keyboard will not accept the keyboard-selection preference write, and
`advanceToNextInputMode()` from Obadh triggers the one-time "Quickly Change
Keyboards" tutorial sheet, which covers the keyboard. Both were hit while producing
this table. Install the app, launch it with `--keyboard-test --solid`, and never
enable Obadh — the system keyboard is then what gets presented.
