# Landscape width audit

The app has no root SafeArea or global maximum width. MaterialApp's Overlay
does not shrink route contents. Lobby SafeArea reserves the device padding once;
its nested bottom dock SafeArea sees consumed horizontal padding and retains the
bottom inset. No duplicate device safe area was found.

Lobby added 26 logical pixels on the left and 16 on the right **after** SafeArea.
These are now symmetric 6-pixel gutters. Dock extra gutters changed from 12 to 6.
League proportions, 2–2–1 layout, actions and table list are unchanged.

## Reproducible measurements

These are logical-pixel widget-test scenarios, **not measurements taken on an
iPhone**. Actual system insets depend on device, orientation and system UI.

| Screen | Safe L/R | Lobby before | Lobby after | GameWidget canvas | Flame viewport (unchanged) | Horizontal space outside viewport |
|---|---|---:|---:|---:|---:|---:|
| 852 × 393 | 59 / 59 | 692 | 722 | 852 | 698.67 | 153.33 |
| 852 × 393 | 44 / 0 | 766 | 796 | 852 | 698.67 | 153.33 |
| 852 × 393 | 0 / 0 | 810 | 840 | 852 | 698.67 | 153.33 |
| 960 × 432 | 0 / 0 | 918 | 948 | 960 | 768 | 192 |
| 640 × 360 | 0 / 0 | 598 | 628 | 640 | 640 | 0 |

At 852 × 393 with 59 / 59 safe insets, the dock increases from 710 to 722.
The lobby retains 12 pixels of intentional total gutter after system safe insets.
GameWidget and viewport widths are different quantities: FlameGame.size is the
virtual 1600 × 900 world; FlameGame.canvasSize reports the actual Flutter canvas.

## Game findings and remaining limitation

OkeyGameScreen gives GameWidget the full canvas. HUD SafeAreas are siblings, not
wrappers around GameWidget. The 1600 × 900 FixedResolutionViewport preserves
aspect ratio, giving scale = min(canvasWidth / 1600, canvasHeight / 900).
This is shared platform code: wide Android displays can show the same spacing.
SpectatorScreen also explicitly retains a 16:9 AspectRatio and fixed camera.

The viewport was deliberately **not expanded** in this change. Rack slots,
discard positions, action controls and DraggedTilesOverlay share this transform;
GameAvatarOverlay also computes placement using the same 1600 × 900 scale.
Filling a wider viewport without a dedicated responsive world layout would
stretch tiles, crop content, or misalign Flutter overlays and touch coordinates.
The remaining game-side spacing is therefore still present. This audit does
not claim to have eliminated it. Existing camera behavior is covered by five
canvas/viewport/projection round-trip tests, including both rack ends.

## Validation scope

Lobbies cover small landscape sizes, increased text scale, asymmetric cutouts,
safe areas applied once, navigation callbacks and updated visual goldens.
Camera tests exercise the actual Flame fixed-resolution camera configuration
without network or game-state changes. They do not simulate physical dragging
on an iPhone or validate native iOS inset reporting.

No iPhone, iOS simulator or Android device was available in this Windows session.
Real-device confirmation of system insets and a separate responsive game-world
layout remain necessary before promising edge-to-edge gameplay.
