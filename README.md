# Obadh iOS

Native iOS/iPadOS keyboard for Obadh Bangla transliteration.

The first product target is intentionally narrow: a fast Bangla-only custom
keyboard that feels close to Apple’s own keyboard and uses the published
`obadh_engine` Rust SDK through a thin native bridge. Swipe typing, voice input,
emoji prediction, and neural suggestion models are later platform layers.

## Project Shape

- `Obadh`: small containing app with setup status, permission guidance, and the
  public app-settings link.
- `ObadhKeyboard`: `UIInputViewController` keyboard extension.
- `Shared/Sources`: UIKit keyboard UI, composer state, design tokens.
- `rust/ObadhBridge`: static Rust bridge depending on `obadh_engine = "0.6.0"`.
- `Resources/ObadhModels`: compact autocorrect and autosuggest artifacts copied
  into the keyboard extension bundle.
- `Frameworks/ObadhBridge.xcframework`: generated native bridge, ignored by Git.

The keyboard extension requests iOS “Allow Full Access” so UIKit haptics can
work inside the custom keyboard extension. Obadh still performs
transliteration, autocorrect, autosuggest, and personal learning locally; this
build does not use network services.

The bridge intentionally stays thin: Swift owns UIKit, touch routing, bundle
resource discovery, and text proxy mutation. Rust owns transliteration,
autocorrect ranking, autosuggest lookup, and artifact parsing. The C ABI only
moves UTF-8 buffers across the boundary.

## Setup

```bash
cd obadh-ios
./scripts/bootstrap.sh
open Obadh.xcodeproj
```

If `xcodebuild` still points at Command Line Tools, run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then rerun `./scripts/bootstrap.sh`.

## Real Device Install

The real iPhone/iPad path is meant to be stable. Signing is stored in
`Config/Signing.local.xcconfig`, which is ignored by Git and included by the
generated Xcode project.

```bash
./scripts/install-device.sh
```

The script:

- infers `DEVELOPMENT_TEAM` from the local Apple Development certificate when
  `Config/Signing.local.xcconfig` does not exist;
- regenerates the Xcode project;
- builds with automatic provisioning updates;
- installs the signed app on the connected iPhone/iPad;
- launches `Obadh`.

After install, the app shows a setup checklist. The only public deep link Apple
allows here opens Obadh’s app settings. For keyboard-specific switches, follow
the paths shown in the app:

- Settings > General > Keyboard > Keyboards > Add New Keyboard > Obadh
- Settings > General > Keyboard > Keyboards > Obadh > Allow Full Access
- Settings > Sounds & Haptics > Keyboard Feedback > Haptic
- Settings > Accessibility > Touch > Vibration

The containing app also exposes a simple Haptic Feedback toggle. The setting is
stored in the shared app group and read by the keyboard extension.

To target a specific device:

```bash
DEVICE_ID=00008140-000410243ED3001C ./scripts/install-device.sh
```

## Build Pieces

Generate the project:

```bash
xcodegen generate
```

Build the Rust bridge:

```bash
./scripts/build-rust-xcframework.sh
```

The bridge script builds arm64 device, arm64 simulator, and x86_64 simulator
slices, then packages them into a local XCFramework.
Rerun it after changing the Rust bridge or updating `obadh_engine`.

Run the app or keyboard extension from Xcode on an iPhone/iPad simulator or a
device. Enable the keyboard in Settings > General > Keyboard > Keyboards.

If automatic inference fails, create the local signing file manually:

```bash
cat > Config/Signing.local.xcconfig <<'EOF'
DEVELOPMENT_TEAM = YOUR_TEAM_ID
EOF
```

Then rerun `./scripts/install-device.sh`.

## Current Keyboard Behavior

- Roman QWERTY keys feed Obadh transliteration only.
- The active Roman token is rendered live as Bangla in the focused text field.
- Press Space to keep the deterministic Obadh output and insert a space.
- The ribbon shows the deterministic output first, then autocorrect candidates.
  The deterministic item is informational; tapping an autocorrect item replaces
  the active token.
- After a word is committed, the ribbon can show next-word suggestions from the
  bundled n-gram artifact.
- Committed words are observed by Obadh’s bounded personal autosuggest layer.
  The keyboard exports the compact Rust snapshot to the shared app-group
  Application Support container and imports it again on startup. Snapshot import
  is validated by the autosuggest vocabulary fingerprint, so stale personal
  state is discarded.
- `.` inserts Bengali danda `।`.
- Key taps use the system input-click path and lightweight UIKit haptics.
  On device, enable Obadh > Allow Full Access in iOS Keyboard settings, and
  ensure Settings > Sounds & Haptics > Keyboard Feedback > Haptic plus
  Settings > Accessibility > Touch > Vibration are enabled.
- Holding Backspace follows a native-like acceleration curve: immediate delete,
  fast character repeat, slower word chunks, then larger sentence/context chunks
  after a sustained hold. The repeat stops on touch-up, cancel, or dragging away
  from the key.
- The emoji key opens Obadh’s local Unicode/CLDR-backed emoji panel with
  categories, recents, and search. Emoji search uses an English key path and
  returns to Bangla typing when dismissed.
- The system globe switches to the next enabled keyboard.
- Shift is deliberate and affects the next Roman key for Obadh case-sensitive
  rules.

No English keyboard mode is included. Users should switch to Apple’s English
keyboard with the globe key when needed.

## Design Direction

The keyboard uses a native UIKit layout rather than a web view or custom engine.
The visual language follows Apple’s keyboard restraint: system colors, SF
Symbols, compact controls, minimal settings, and no ornamental UI. Full Access
is requested only because iOS gates UIKit haptics inside third-party keyboard
extensions behind that switch; Obadh’s typing engine remains local.

The extension does not force a custom keyboard height. iOS owns the input-view
container size, and the Obadh rows/suggestion ribbon fit inside that system
provided keyboard area. This keeps the keyboard aligned with the current device,
orientation, and Apple keyboard profile instead of relying on a fixed pixel
constant.

Future layers should plug into the same composer boundary:

- emoji prediction and classic emoticon conversion
- swipe/voice input
- native neural autosuggest through Core ML
