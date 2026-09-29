# Pocket Gridiron UI style guide

Canvas: 480x270 viewport, `expand` aspect (phones get ~585x270). All colors live in `UiSkin`.

- **Insets:** never place UI against a screen edge directly. Menus use `MetaUI.screen` (inset by
  `SafeArea`, backgrounds bleed). Custom screens: `SafeArea.apply(root)` / `SafeArea.bleed(bg)`;
  anchored controls add `SafeArea.left()/right()/top()/bottom()` to their offsets.
- **Palette:** blue `BLUE/BLUE_DARK` backgrounds, `NAVY/PANEL` panels, `YELLOW` = the one primary
  action / highlight, `WHITE` body text, `MUTED` secondary text, `GREEN` positive, `RED` danger.
- **Text:** pixel font 8 px body, 16 px titles/big numbers; always outlined or on a dark panel.
  Secondary text uses `MUTED` at minimum (no dimmer).
- **Buttons:** `MetaUI.yellow` = primary (one per screen), `MetaUI.button` = secondary,
  disabled = greyed panel. Minimum tap target 24 px.
- **Match HUD:** top bar shows team-colored score chips (helmet color), quarter + clock, down &
  distance; bottom bar shows the controlled player and gesture hint. Bars are `BAR_H` = 14.
- **Players:** on-field sprites are drawn at `PlayerSprites.SCALE` (1.25) for readability. Camera zoom stays 1.0: at 1.25 wide receivers at the sidelines fall off screen.
- **Review loop:** `godot --path . --resolution 1170x540 --fixed-fps 60 -- --snap=out.png,120 <flags> --fake-notch`
  (flags: `--demo-profile --screen=X`, `--quick`, `--watch`, `--show=pause|pat|final|kick|tip`).
