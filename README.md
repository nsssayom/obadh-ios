# Obadh iOS

Native iOS/iPadOS keyboard for Obadh Bangla transliteration.

Obadh is a Bangla-only custom keyboard that aims to feel like Apple's own: you
type roman, it composes Bangla live, and the whole thing runs on device. It uses
the published `obadh_engine` Rust SDK through a thin native bridge for
transliteration, autocorrect, and autosuggest, and adds an iOS-native layer for
touch, layout, haptics, punctuation, and emoji.

## Project shape

- `Obadh` — the containing app: setup checklist, permission guidance, a few
  settings (haptics, emoji-search language), and a test field.
- `ObadhKeyboard` — the `UIInputViewController` keyboard extension.
- `Shared/Sources` — the UIKit keyboard UI, composer state, design tokens, and
  the emoji stores. The parts with no UIKit dependency also build as the
  `ObadhKeyboardCore` SwiftPM library so they can be unit-tested off-device.
- `rust/ObadhBridge` — a static Rust bridge over `obadh_engine`.
- `Resources/ObadhModels` — the compact binary artifacts bundled into the
  extension: autocorrect/autosuggest models, the emoji catalog, and the Bangla
  emoji suggestion + search indexes.
- `Frameworks/ObadhBridge.xcframework` — the generated native bridge (git-ignored).

The bridge stays deliberately thin. Rust owns transliteration, autocorrect
ranking, autosuggest lookup, and model parsing; Swift owns UIKit, touch routing,
bundle resource discovery, and text-proxy mutation. The C ABI only moves UTF-8
buffers across the boundary. Everything is local — no network, no telemetry. Full
Access is requested only because iOS gates keyboard-extension haptics behind it.

## Setup

```bash
cd obadh-ios
./scripts/bootstrap.sh
open Obadh.xcodeproj
```

If `xcodebuild` still points at Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then rerun `./scripts/bootstrap.sh`.

## Real device install

Signing lives in `Config/Signing.local.xcconfig` (git-ignored, included by the
generated project). The install script infers `DEVELOPMENT_TEAM` from your Apple
Development certificate, git-stamps the build, regenerates the project, builds
with automatic provisioning, installs, and launches.

```bash
./scripts/install-device.sh                 # Release (default)
DEVICE_ID=<udid> ./scripts/install-device.sh
CONFIG=Debug ./scripts/install-device.sh    # Debug build, only when explicitly needed
```

The phone runs **Release** by default — it excludes all `#if DEBUG` tooling.
After install, the app shows a setup checklist; the paths to enable the keyboard
and Full Access are listed there.

Regenerate the project, or build the Rust bridge, on their own:

```bash
xcodegen generate
./scripts/build-rust-xcframework.sh   # device + simulator slices, rerun after Rust changes
```

Every build is stamped with the git commit count, short SHA, and a UTC
timestamp (`scripts/stamp-build.sh` → `Config/BuildInfo.xcconfig`). The version
is shown in the app's test screen and logged by the extension on appear, so you
can confirm the device is running the build you think it is — a keyboard
extension will otherwise happily keep serving a cached old binary.

## Keyboard behavior

- Roman QWERTY feeds Obadh transliteration; the active token renders live as
  Bangla marked text in the focused field. Space keeps the deterministic output.
- The suggestion ribbon shows the deterministic output first (informational),
  then autocorrect candidates. After a word commits, it can show next-word
  suggestions from the bundled n-gram model. Personal autosuggest learns from
  committed words, persisted to the shared app group and fingerprint-validated
  on load so stale state is dropped.
- Numerals and punctuation are handled on the iOS layer: the number pad emits
  Bangla numerals ০–৯, `৳` (taka) and `।` (danda) sit on the punctuation pages,
  and Apple-style smart punctuation is applied (`--`→`—`, `...`→`…`, curly
  quotes, double-space → danda).
- `qq` (q tapped twice) is a mobile shortcut for `^`, the চন্দ্রবিন্দু marker.
- Holding backspace follows a native-like curve: immediate delete, fast
  character repeat, then word and sentence chunks on a sustained hold.
- The emoji key opens the local Unicode/CLDR emoji panel with categories,
  recents, and search. Search runs in English by default with an in-bar **EN⇄BN**
  toggle (default set in the app); skin tones are picked by long-press and
  remembered.
- The globe switches to the next keyboard. There is no English typing mode —
  switch to Apple's English keyboard with the globe when needed.

## Design notes

Most of the interesting decisions were forced by how iOS treats custom
keyboards, and several of them generalise to any platform.

**Touch routing.** iOS *drops* touches over fully-transparent regions of a
keyboard extension before they reach `hitTest`. The gaps between keys and the
padding around the outer keys were dead zones, and no amount of hit-test slop
fixes it — the event never arrives. The fix is a single near-invisible surface
(one plain view at ~0.004 alpha, so it's non-transparent but imperceptible)
covering the whole key area; it catches every touch and resolves it to the
nearest key by midpoint boundaries. The keys themselves are non-interactive. The
general lesson: a keyboard lives on the edges of its keys, so make the whole
surface catch input and resolve to intent instead of trusting per-key hit rects.

**Backdrop and key material.** The background is the system's own keyboard
material via `UIInputView(inputViewStyle: .keyboard)`, not a hand-rolled blur —
a generic blur reads as a distinct rectangle sitting on the keyboard. On iOS 26
the keys are Liquid Glass, but a full-strength glass effect adds a raised
specular rim the native keys don't have; a flat translucent fill matched them.
(The Simulator doesn't render Liquid Glass faithfully, so that comparison is a
device-only check.)

**Haptics.** Apple's key tap is one crisp, near-uniform tick, not a per-key
intensity curve. The only public API that controls crispness (sharpness) is Core
Haptics, so the tap is a single transient tuned by intensity and sharpness, with
a `.rigid` `UIImpactFeedbackGenerator` as the fallback. Final values were dialed
in on device (intensity 0.5, sharpness 0.9) — haptics don't fire in the
Simulator, so this is felt, not measured.

**Composer boundary.** Keystrokes go to a composer that produces the
deterministic transliteration synchronously (shown immediately as marked text)
and merges the expensive autocorrect/FST results asynchronously, generation-
guarded so out-of-order or stale results are discarded. New capabilities plug in
at this boundary rather than into the key handling.

**Emoji, and the data pipeline behind it.** This is the most portable part. When
you finish a Bangla word, up to three emoji appear in the ribbon, taking over the
third text slot (the top two text candidates always survive) — matching the
native keyboard. The data is built offline (`scripts/generate-emoji-data.py`)
from Unicode CLDR Bengali annotations laid *under* a hand-curated colloquial map,
because CLDR is descriptive (হার্ট = heart) while people type colloquially
(ভালোবাসা = love). Candidates are ranked by name-centrality first — an emoji
whose *primary name* is the word beats one that merely mentions it, so নাক → 👃,
not 😤 — then by Unicode usage frequency, which is used at build time only and
never ships. The runtime artifact is a tiny sorted-key binary (word → up to 3
emoji) answered by exact binary search. Emoji *search* reuses the same pipeline
as a broader index with prefix and multi-term matching, plus a fuzzy fallback
(grapheme edit-distance against the closed keyword vocabulary — aggressive is
safe there because the only candidates are emoji keywords). Skin tones are
remembered per-emoji in shared preferences. None of this needs iOS: the build
pipeline, the ranking, and the binary format are directly reusable on Android.

**Performance discipline.** The typing path never touches the ~1 MB emoji
catalog; the suggestion lookup is a memory-mapped binary search over a ~110 KB
index. The Bangla search index (and its fuzzy fallback) only load when you switch
the search to Bangla, so the English default pays nothing. Preferences (haptics,
skin tone, emoji-search language) are plain `UserDefaults` in the shared app
group — the right tool for small state; no SQLite or Core Data.

**Where things live.** The pure logic — composer, emoji stores, resolvers — is in
the SwiftPM `ObadhKeyboardCore` target so it's unit-tested against the *real*
generated artifacts off-device. UIKit views and the extension controller stay in
the extension target. App and extension share preferences and learned state
through an App Group.

Debug builds carry a small file-based control channel and on-device tuning
controls (haptic sliders, glass-style toggle) for iterating on feel; it is all
`#if DEBUG`, verified absent from Release binaries, and never ships.
