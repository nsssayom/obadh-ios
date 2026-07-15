# Native parity: the measured model of iOS keyboard presentation

Obadh's goal is to be indistinguishable from Apple's keyboard in geometry and
look. None of the numbers below are guesses: every value was measured from
screenshots against native, on six simulator device classes and on a physical
iOS 27 device, and is enforced by the parity suite
([`scripts/parity/`](../scripts/parity/README.md)). This document is the model
those measurements produced, kept because iOS gives keyboard extensions no API
for any of it.

## How iOS presents a third-party keyboard

- The extension declares its height with a single Auto Layout constraint on
  its root view (`allowsSelfSizing` + one constraint, the documented
  mechanism). The system composites the view into a container it owns.
- **Metrics must derive from the intended height, never `view.bounds`.** The
  suggestion strip's required height feeds the view's fitting size, which is
  what the system sizes the container by. Deriving metrics from current
  bounds therefore creates a feedback loop that locks the container and, with
  self-sizing released, makes every height a fixed point (visible shaking).
- In the modern (Liquid Glass) presentation the system paints an unpaintable
  **band of ~15–18 pt** above the extension inside its container. The visible
  suggestion zone is therefore `band + strip`.
- **Presentation paths differ.** On iOS 27, cold-launched hosts draw *no*
  band, while re-presentations do. The only observable discriminant is the
  presentation's transient sizing pass: cold presents pass through an
  intermediate *below* the asked height; re-presents settle at the ask
  directly. The keyboard classifies each presentation and draws the full zone
  itself when no band is coming.
- **Legacy hosts** (apps predating the iOS 26 SDK, on iOS 26) get a different
  container: edge-to-edge, square, band-less, with its own geometry. There is
  no API for this either; the transient intermediates are class-quantized and
  disjoint (modern {294, 444, 452} vs legacy {260, 411, 419} across all width
  classes), so the keyboard detects legacy presentations the same way. iOS 27
  removed the legacy fallback entirely, so the detector is iOS 26-only.

## Geometry (all device-measured)

- **Key geometry is class-quantized, not proportional to width.** Native keys
  are 43 pt at widths below ~410 pt and 45 pt above, at 54/56 pt row pitch
  respectively, with an 11 pt row gap, near-constant across devices from the
  SE (375 pt) to the Pro Max (440 pt). A proportional `width/440` scale (our
  first model) sat key rows up to 18.5 pt below native's.
- **The suggestion zone is a design constant per OS**: ~51 pt on iOS 26,
  54 pt on iOS 27, uniform across hosts and widths. The strip we draw is
  `zone − band` in banded presentations and the full zone otherwise.
- Verified end state: our key rows land on native's exact pixels (q-row
  delta 0.0 pt at 402 and 440 pt), zones within 1 pt, on all 24 tested cells
  (6 devices × modern/legacy × light/dark).

## Color (sampled, then solved)

- The panel is `UIInputView(inputViewStyle: .keyboard)`, the system's own
  keyboard material, and it measures pixel-identical to native everywhere.
- Key fills are white-over-panel alphas solved from screenshot sampling:
  **0.16 dark / 0.87 light** (modern), **0.30 dark / opaque white light**
  (legacy). Native keys are flat: no shadow, no specular rim (a full-strength
  `UIGlassEffect` adds a rim native keys don't have; a flat translucent fill
  matches).
- Suggestion text centers ~26 pt above the strip's bottom edge regardless of
  strip height (native-measured rule), separators cap at ~27 pt.
- The key preview (press popover) is a plain rounded rectangle flush above the
  pressed key: native draws no stem/arrow and never overlaps the key face.

## The instruments

- **Probe overlay** (DEBUG): a live readout on the keyboard itself (bounds,
  window, asked height, rendered metrics, detected presentation) plus yellow
  fiducial hairlines at the view top and strip bottom, so any screenshot
  self-certifies our geometry with no detector heuristics.
- **Measurement backdrop**: the debug app's `--measure-bg` launch argument
  paints an appearance-independent mid-gray behind the keyboard so native's
  container edges measure cleanly in both light and dark.
- **`Debug-Legacy` build config**: the container app opts out of the modern
  design (`UIDesignRequiresCompatibility`), reproducing the legacy host
  presentation on demand.
- Measurement rules that survived contact with reality: read pixel *runs*
  (background → sustained material), never largest-brightness-step heuristics
  (they snap to accessory bars, labels, and our own fiducials, all observed);
  sample right of the probe label (it reaches ~0.88 × width on the narrowest
  device).

## Deliberately open

- Pressed-state key colors are relative values (scriptable now via the
  `preview:<key>` channel command; native's pressed state needs reference
  captures).
- Landscape and iPad zones are not yet measured.
- iOS 27 values should be re-verified at GA; the probe makes that a
  two-minute check.
