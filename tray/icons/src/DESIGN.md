# a2a tray icon — "Two Roofs"

One chevron pair. Each chevron pivots 90 degrees in place to encode daemon state.
The pair layout (side by side, 4-unit seam) never changes.

## Geometry (all files)

- Canvas: 32 x 32 units, viewBox "0 0 32 32"
- Chevron: 12 units of span, 7 units of depth, identical in every state
- Stroke: 4 units (3.5 for down), `round` cap and join, `fill="none"`
- Seam between the two chevrons: 4 units clear of the stroke outlines = 2px at 16px
- Colour: `currentColor` — recolour at build time, do not bake it in

## States

| State     | File                  | Chevrons        | Colour                                  |
|-----------|-----------------------|-----------------|-----------------------------------------|
| Idle      | a2a-idle.svg          | both point up   | taskbar foreground (white / near-black) |
| Sending   | a2a-sending.svg       | both point right| #2F6FD0 light bar · #5B96EA dark bar    |
| Receiving | a2a-receiving.svg     | both point left | #2F7D4F light bar · #5FB383 dark bar    |
| Down      | a2a-down.svg          | both point down | #8A8376 light bar · #7D838B dark bar    |

Direction is the primary signal; colour is secondary. Flattened to greyscale all
four states are still distinguishable, so the set is colour-blind safe.

## Building the .ico set

Windows picks 16 / 20 / 24 / 32 / 48 depending on DPI. Render each state at every
size, then pack:

```sh
for state in idle sending receiving down; do
  for px in 16 20 24 32 48 256; do
    rsvg-convert -w $px -h $px "a2a-$state.svg" -o "build/$state-$px.png"
  done
  magick build/$state-16.png build/$state-20.png build/$state-24.png \
         build/$state-32.png build/$state-48.png build/$state-256.png \
         "a2a-$state.ico"
done
```

Recolour before rasterising by replacing `currentColor` with the hex for the
state and the active taskbar theme.

## Hinting notes

- At 16px the 4-unit stroke lands on exactly 2px. Keep the whole drawing on even
  units so nothing falls on a half pixel.
- If the 16px render looks soft, hand-nudge that master only: snap the apex to a
  pixel centre and the arm ends to pixel edges. Never scale the 48px down.
- Down uses a 3.5-unit stroke so it reads lighter than the live states even
  before colour is applied. At 16px round that to 2px and rely on the grey.
- Do not add badges or overlays. Every state is the same two paths moved.

## Windows integration

- Ship idle as a monochrome mask so the shell can tint it with the taskbar's own
  foreground colour on both light and dark themes.
- Transition between states by rotating the chevrons, ~150ms, no crossfade.
- Sending/receiving should hold for a 400ms minimum so short bursts are visible,
  then fall back to idle.
