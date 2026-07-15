# Testing and verification

Three layers, each aimed at a different failure class. The shared principle:
behavior is verified by exercising the real thing — real artifacts, real
input paths, real screenshots — and anything visual is measured, not
eyeballed.

## Unit tests (SwiftPM, off-device)

The pure logic — composer, text composition controller, emoji stores,
resolvers — builds as the `ObadhKeyboardCore` SwiftPM library and is
unit-tested against the *real generated artifacts* without a simulator.

## Engine integration tests (`Tests/ObadhEngineTests`)

This target links the actual `ObadhBridge.xcframework` and bundles the real
`ObadhModels` artifacts, so it exercises the true Swift↔C boundary:
opaque-handle lifecycle, packed-record decoding, snprintf-style sizing.
Artifact content hashes and canonical lexicon frequencies are **pinned** so an
engine or data bump that silently changes behavior fails loudly here. The
auto-insert gate's thresholds are calibrated by these tests against the real
lexicon (see [autocorrect.md](autocorrect.md)).

Run: `xcodebuild test -scheme Obadh -destination 'platform=iOS Simulator,...'`

## The parity suite (`scripts/parity/`)

Screenshot-measurement verification that the keyboard is geometrically and
chromatically identical to native, across device width classes, host
presentations (modern and legacy), and appearances:

```bash
scripts/parity/run.sh                    # full matrix, PASS/FAIL, exit code
scripts/parity/run.sh "iPhone 17 Pro"    # one device
```

It builds both simulator configs, boots fresh simulators per device class,
captures native and Obadh in the same session, and gates geometry (suggestion
zone, key-row position) and color (key fill, panel, glyphs, strip) against
explicit tolerances. Obadh's cells are self-certified by the probe overlay's
fiducial hairlines; native's are measured by pixel-run analysis. See
[`scripts/parity/README.md`](../scripts/parity/README.md) for the full
contract and its honest limits (simulator runtime only; landscape, iPad, and
pressed-state colors not yet covered).

## Mouse-free simulator automation

Everything above is scriptable without ever touching the mouse — a hard
requirement (simulator UI cannot be safely mouse-automated, and `simctl` has
no tap primitive). Two pieces make it work:

- **`scripts/sim-kbd.py`** — boots/selects Obadh as the presented keyboard by
  writing keyboard-daemon preferences, takes screenshots, and drives the
  debug channel.
- **The DEBUG control channel** — a file the extension polls in its own
  sandbox, giving scripted access to the *production* input path:
  `tap:<keys>`, `cursor:<offset>`, `context` (log the document around the
  cursor), `pick:<slot>`, `pickemoji`, `preview:<key>`, `autoinsert:on/off`,
  `probe:on/off`, `glass:<style>`, `mode:<page>`. Input-behavior bugs are
  reproduced and verified end-to-end through the same code a finger would
  hit.

All debug tooling is `#if DEBUG` — verified absent from Release binaries.
