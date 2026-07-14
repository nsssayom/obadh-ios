# Native-parity suite

Measures Obadh against the native keyboard — geometry and color — across device
width classes, host presentations, and appearances, on the iOS Simulator.
Everything is measured from screenshots; nothing is eyeballed.

```
scripts/parity/run.sh                    # full matrix, PASS/FAIL
scripts/parity/run.sh "iPhone 17 Pro"    # one device
SKIP_BUILD=1 scripts/parity/run.sh       # reuse existing sim builds
```

Exit 0 means every cell is within tolerance. Artifacts (screenshots, probe logs,
`report.json`) land in `build/parity/<timestamp>/`.

## What it checks

Per device × {modern, legacy host} × {light, dark}, native vs Obadh:

| check   | what                                            | tolerance |
|---------|--------------------------------------------------|-----------|
| zone    | container edge → q-row distance                  | 3 pt      |
| q       | absolute q-row position on screen                | 2 pt      |
| keyfill | key fill color (median, away from the glyph)     | 4 / channel |
| panel   | material between key rows                        | 3         |
| glyph   | key text color                                   | 6         |
| strip   | suggestion-strip interior                        | 3         |

The device set covers both measured geometry classes (key 43 / pitch 54 below
~410 pt; key 45 / pitch 56 above) and the legacy-presentation detector
(`UIDesignRequiresCompatibility` host = the Debug-Legacy build of our own app).

## How it measures

- **Obadh is self-certifying**: with the probe overlay on, the keyboard draws
  yellow fiducial hairlines at its view top and strip bottom (= q row), and logs
  an `OBADH-PROBE` line with the screen size and rendered metrics. The suite
  reads the fiducials at x 0.86..0.97 W — the probe label must never grow past
  ~0.84 W (keep new probe fields on its shortest line).
- **Native** has no fiducials: q comes from key-brightness bands (glyph-structure
  fallback), container edges from panel-color runs walking up from the q row.
  The debug harness's `--measure-bg` launch argument paints an
  appearance-independent mid-gray behind the keyboard so those runs have
  contrast in both light and dark. Never measure edges with a
  largest-brightness-step heuristic — it snaps to accessory bars, labels, and
  fiducials (all observed).
- Captures are mouse-free: `simctl` + the DEBUG control channel
  (`scripts/sim-kbd.py`). Fresh simulators are created on demand and keyboards
  are enabled by writing `AppleKeyboards` directly.

## Honest limits

- Runs against the **iOS 26.5 simulator runtime** — the only one installed with
  Xcode 26.6. iOS 27 truth comes from device screenshots (the fiducials make
  those self-measuring too; see the probe overlay switch in the debug app).
- Pressed-state colors are not covered (static captures).
- Landscape and iPad are not covered yet.
- This is an on-demand harness, not an XCTest target: it orchestrates
  simulators from outside the app, which XCTest cannot do.
