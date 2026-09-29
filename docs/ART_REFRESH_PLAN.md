# Full art refresh — look good, feel fun, UI clear (2026-09-28)

Goal: every screen reads at a glance on a phone, feels like a fun retro sports game, and shares one
visual language. Original art only (no ripped assets). Viewport is 480x270, so every pixel counts.

## Audit (screenshots of current build)
Good already: title screen, store packs, card art, lineup grid, challenge list, star/helmet header.
Problems seen:
1. **Match field**: players are ~20 px on a 270 px-tall view and read small next to the big yard
   numbers; the two teams are hard to tell apart in a pile; the top/bottom HUD strips are thin,
   low-contrast text; the ball is hard to spot in flight.
2. **Hub**: busy. Daily check-in popup covers the screen and the panels behind it are dense; the
   PLAY button competes with SQUAD/STORE/OBJECTIVES and the small text rows (team list, XP).
3. **Text size/contrast**: small pixel text (dim blue on navy) on subtitles, reward lines,
   "CAREER 0-0-0", store card descriptions. Fails a phone-at-arm's-length test.
4. **Consistency**: the header (stars + shield + title) is repeated on every screen and eats
   vertical space; bottom bars differ per screen (button sizes, order, icon vs. text).
5. **Feedback**: few tap/hover states, no consistent "primary vs. secondary" button styling.

## Plan (in order; each step ends with screenshots + commit)
1. **Style guide** (`scripts/ui/ui_skin.gd`, `UiTheme`): one palette (navy/blue base, gold =
   primary action, red = danger/opponent, green = positive), 3 text sizes (title/body/small), min
   body contrast, 3 button styles (primary gold, secondary blue, disabled), min tap target 24 px.
2. **Match HUD**: bigger scoreboard (score, quarter/clock, down & distance, possession arrow) in
   solid panels; play-call bar and hints with higher contrast; clear "you control" tag; ball
   trail/shadow + landing marker for passes.
3. **Field and players**: larger player sprites (or a camera zoom-in option), stronger team
   color separation (jersey vs. pants vs. helmet stripe), home/away uniform swap when colors
   clash, cleaner yard numbers and hash marks so they don't fight with players.
4. **Hub and menus**: single obvious PLAY action, group secondary buttons, compact header, move
   daily check-in to a small banner that opens on tap, trim text rows.
5. **Cards / packs / collection**: keep card art; clearer tier borders, rating number larger,
   position badge color-coded; pack opening reveal with bigger rarity flash.
6. **Juice**: button press/hover animation, screen transitions (exists), TD/turnover banners,
   confetti on wins, coin count-up.
7. **Verify**: screenshot every screen before/after (`--write-movie` with `--screen=X`), check on
   an actual phone via the sideload build, run the GUT tests.

## Decisions for the owner
- Zoom the match camera in a little (bigger players, less field visible) vs. keep the wide view?
- Keep the current blue/gold theme, or shift the palette?
- Any reference for "fun" beyond Retro Bowl (Madden mobile cards, NES Tecmo Bowl)?
