# Pocket Gridiron

A personal, never-published retro 2D arcade football game for mobile (Godot 4 + GDScript):
chunky pixel art, quick drives, touch controls. **You play both offense and defense**, with a
Madden-Mobile-2016-style ultimate-team meta game (packs, cards, coins) on top.

The full design and roadmap live in [PLAN.md](PLAN.md).

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Tooling, project skeleton, Android export | ✅ done (APK builds; on-device check pending) |
| 1 | One playable offensive drive, placeholder art | ✅ playable in `drive_sandbox` |
| 2 | Defense playable | ✅ `drive_sandbox -- --defend` |
| 3 | Full game (clock, both halves, AI opponent) | ✅ main scene (`scenes/match/match.tscn`) |
| 4 | Roster import, cards affect gameplay | ✅ team picker → your real players as cards |
| 5 | Packs, economy, collection | ✅ store, packs, collection, lineup, sets, save |
| 6 | Season, challenges, polish | ✅ season + playoffs, 11 challenges + daily, settings, SFX, coach tips |
| 7 | Road to Glory (career as one QB/RB/WR/CB) | ✅ create, combine, draft, seasons, awards, Hall of Fame |
| 8 | AI overhaul (QB reads + risk model, coverage, pursuit) | ✅ `docs/AI_OVERHAUL_PLAN.md`, lab `tests/lab/lab_ai.gd` |
| 9 | Legends (vintage cards: 90 retired greats) | ✅ baked into Silver+ packs, Throwback / Hall of Fame / era program packs, Legend Draft |
| 10 | Store v2 (Madden Mobile style) | ✅ featured rotation (weekly program, daily deal, bundle of the week), Pro pack, bundles, drafts |

## Running

1. Install **Godot 4.7.x** (standard build, not .NET).
2. Open `project.godot`, press **F5**. First run: pick your NFL team (you get its real players
   as Silver/Bronze cards), then play from the hub: offense when you have the ball, defense
   when they do. `-- --quick` jumps straight into KC vs PHI; `-- --reset-save` starts over. The drive sandbox is still there for debugging
   (`scenes/debug/drive_sandbox.tscn`, or launch with `-- --sandbox`).

### Controls (touch, or mouse on desktop)
| When | Gesture |
|---|---|
| Play call | the situational **BEST** call is preselected; tap another card or **MORE** for the full playbook (18 offense plays) |
| Snap (pass) | press on the **QB** and keep dragging: **back** = aim (slingshot), release to throw · **forward** = scramble. A tap anywhere also snaps |
| Snap (run) | press on the QB to snap; keep holding and drag up/down to steer once you have the ball |
| QB with the ball | drag **back** (slingshot) to aim, release to throw; farther = deeper. Loft is automatic and labeled on the arc: **BULLET** (short), **TOUCH** (over a defender / ~13+ yds), **LOB** (~32+ yds, drops in over the shoulder). Light aim assist snaps to a receiver in stride · drag **forward** to scramble |
| Ball carrier | follows the play's lane on his own · hold + drag up/down to steer · drag back to slow |
| | flick up/down = juke · double-tap = dive |
| CPU defense | learns your tendencies: repeat a play and it gets **keyed** (red "DEFENSE IS KEYING ON …" warning) |
| **Defense** pre-snap | pick a call (BEST preselected) · **tap a defender** to control him (yellow ring + name tag; your pick is remembered) · tap the field when ready |
| Defense live | drag anywhere = move your man · **run into the ball carrier to tackle** (your man wraps up farther and far more surely than CPU defenders) · tap the carrier = dive |
| | tap the ball's landing marker = leap to swat/pick · INT return: drag up/down to steer |
| | **SWITCH** (big button bottom right; Tab/Space) = jump to the defender nearest the ball. You stay on your man until you switch; tapping any defender also takes him |
| Anytime | **II** / **Esc** / Android **back** = pause (resume, defense pace, quarter length, **QUIT TO MENU** — leaving counts as a loss) · **TIMEOUT** button between plays |
| Keyboard | `R` restarts the drive (sandbox) · `F1` AI debug overlay (three-finger tap on a phone) |

### Road to Glory controls (MODE SELECT → ROAD TO GLORY)
| Who | Controls |
|---|---|
| Everyone | **left thumb** = floating joystick (360°, hard turns plant-and-cut) · **BURST** = short speed surge |
| Ball carrier | **JUKE** (side = stick, else away from the tackler) · **SPIN** · **POWER** (stiff arm / truck) · **DIVE** |
| Receiver | you run every route yourself: follow the gold line (drift off it and the QB stops trusting it) · **CALL** = QB looks your way · **CATCH** in the last ~0.6 s = go up and moss the defender |
| Corner | stick shades your spot pre-snap (line up tight to press) · **JAM** · watch the **!** break arrow · **BALL** = leap · **TACKLE** = dive |
| QB | right thumb: drag back to snap / aim, release to throw (as always) · left stick moves you in the pocket |
| Pre-snap (not QB) | the coordinator's call + YOUR JOB · **AUDIBLE** (per game, more with coach trust) · **HOT ROUTE** (WR) · SNAP / READY |

### Debug arguments
```
godot --path . -- --demo-profile --screen=store   # any meta screen with an unsaved demo career
                                                  # (title, hub, mode_select, store, collection, objectives,
                                                  #  prematch, results, pack_open, season, settings, ...)
godot --path . -- --demo-profile --screen=pack_open --elite --auto-open   # watch an Elite walkout
godot --path . -- --demo-profile --screen=hub --no-popups                 # skip the daily check-in
godot --path . -- --demo-profile --screen=store --coins=5000000           # test the store with lots of coins
godot --path . -- --demo-profile --screen=lineup --pick=WR1 [--defense]   # lineup with a slot picker open
godot --path . -- --demo-profile --screen=collection --sell-dupes         # squad with SELL DUPES confirm
godot --headless --path . -- --sandbox --sim=300 --defend --bot=0.5       # a bot plays your defender
godot --headless --path . -- --ai-vs-ai=40 --pass-log   # CPU games + passing stats (deep %, lobs, tips)
godot --path . -- --watch                 # CPU vs CPU full game (demo)
godot --headless --path . -- --ai-vs-ai=100   # 100 headless CPU-vs-CPU games, prints averages
godot --path . -- --home=BUF --away=SF --quarter=1.5   # pick teams / quarter length
godot --path . -- --sandbox               # the one-drive sandbox (add --defend for defense)
godot --path . -- --autoplay          # CPU calls plays and throws; watch a drive
godot --headless --path . -- --sim=300 # 300 sandbox autoplay plays, prints stats, quits
godot --headless --path . -- --sim=80 --verbose   # plus one line per play
godot --headless --path . -- --sim=1000 --smart    # CPU calls plays situationally (PlayAdvisor)
godot --headless --path . -- --sim=1000 --spam=mesh  # always call one play (defense keys on it)
godot --headless --path . -- --sim=1000 --by-play --nokey  # per-play averages, no defensive memory
godot --path . -- --rtg-game=RB --rtg-call=toss   # straight into a Road to Glory game (WR/RB/CB/QB)
godot --path . -- --demo-profile --rtg=CB --screen=rtg_hub   # an unsaved RTG career (add --rtg-stage=draft|offseason)
```

## Tests
```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
bash tools/run_tests.sh /path/to/godot   # import + GUT + sim smoke test (what CI runs)
```
CI (`.github/workflows/tests.yml`) runs the same on every push.

## Android
One-time: JDK 17+ and the Android SDK (platform-tools, build-tools, platform 35) are set in
*Editor Settings → Export → Android*; a debug keystore is configured.
```
godot --headless --path . --export-debug "Android" export/PocketGridiron.apk
adb install -r export/PocketGridiron.apk
```
iOS export needs a Mac with Xcode (planned for Phase 6).

## Editing data
| What | Where |
|---|---|
| Players / ratings | `data/roster.csv` (one row per player; blank attribute = position default) |
| Teams & colors | `data/teams.json` |
| Plays & formations | `data/plays/**.tres`, `data/formations/*.tres` (edit in the Godot inspector) |
| Gameplay balance | `data/tuning/gameplay_tuning.tres` (every speed/catch/tackle constant) |
| Player sprites | `art/players/player_template.png` (16×20 frames, key colors swapped per team) |
| Packs (price, odds, mystery/draft/X-Factor flags) | `data/packs/*.tres` (+ shelves in `scripts/rules/pack_catalog.gd`) |
| X-Factor abilities (triggers, boosts) | `scripts/rules/ability_rules.gd` (`DEFS`) |

`tools/build_playbooks.gd` and `tools/gen_player_sprites.gd` bootstrap the playbook and
placeholder sheet; re-running them **overwrites** those files.

All player names are used for personal, non-distributed play only; no logos or third-party art.
