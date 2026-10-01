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
- **Match HUD** (`MatchHUD`, everything inside a `SafeArea`-inset container, no per-frame offsets):
  compact centered scoreboard pill (away | quarter + clock | home, team-colour chips, ball icon)
  with down & distance + ball spot on a strip under it; 28 px pause button top-left; PUNT/FG/TIMEOUT
  stack top-right (`HudButton` / `HudButtonHot`); ONE bottom play carousel (4 `HudCard`s with name,
  category line, green BEST badge, red "!" keyed marker, + MORE) in a row that reserves the defense
  SWITCH slot; MORE opens a category-tabbed grid (selected play = yellow). Borders use
  `UiSkin.HUD_EDGE`, not near-white; yellow = selected / primary. Slim bottom strip = player + hint.
- **Players:** on-field sprites are drawn at `PlayerSprites.SCALE` (1.25) for readability. Camera zoom stays 1.0: at 1.25 wide receivers at the sidelines fall off screen.
- **Review loop:** `godot --path . --resolution 1170x540 --fixed-fps 60 -- --snap=out.png,120 <flags> --fake-notch`
  (flags: `--demo-profile --screen=X`, `--quick`, `--watch`, `--show=pause|pat|final|kick|tip|grid`).
