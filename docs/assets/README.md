# README assets

Two visuals, deliberately no more. Both come from **Release** builds, never
the in-app debug harness.

| File | Provenance |
|---|---|
| `typing.gif` | Screen recording from a physical device: Notes, dark appearance, typing a Bangla line with Obadh. Full frame, status bar included. |
| `onboarding.png` | Simulator captures of the onboarding welcome step (Release configuration), light and dark, composed side by side with a transparent gutter. |

## Regenerating

Typing GIF from a device screen recording (full frame, 12 fps,
palette-quantized; lands ~1.4 MB for 30 s):

```bash
ffmpeg -i recording.MP4 -vf "scale=420:-1:flags=lanczos,fps=12,\
split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
  typing.gif
```

Onboarding pair from the simulator (fresh install of a Release build shows the
welcome step; `xcrun simctl ui <udid> appearance light|dark` +
`xcrun simctl io <udid> screenshot`), then:

```bash
ffmpeg -i light.png -i dark.png -filter_complex \
  "[0]scale=620:-1,format=rgba,pad=660:ih:0:0:color=0x00000000[a];\
   [1]scale=620:-1,format=rgba[b];[a][b]hstack=inputs=2" \
  -frames:v 1 -update 1 onboarding.png
```
