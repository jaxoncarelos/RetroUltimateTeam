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
| 5 | Packs, economy, collection | — |
| 6 | Season, challenges, polish | — |

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
| QB with the ball | drag **back** (slingshot) to aim, release to throw · drag **forward** to scramble |
| Ball carrier | follows the play's lane on his own · hold + drag up/down to steer · drag back to slow |
| | flick up/down = juke · double-tap = dive |
| CPU defense | learns your tendencies: repeat a play and it gets **keyed** (red "DEFENSE IS KEYING ON …" warning) |
| **Defense** (`-- --defend`) | pick a call (BEST preselected), tap the field when ready |
| | drag anywhere = move your defender (yellow ring) · tap the ball carrier = dive tackle |
| | tap the ball's landing marker = leap to swat/pick (time it for the ball's arrival; from far away it sprints you there) |
| | tap any defender = take control · INT return: drag up/down to steer |
| 4th down | **PUNT** / **FG** buttons (top right) · FG/PAT: tap when the meter needle is in the green |
| After a TD | choose KICK PAT or GO FOR 2 |
| Anytime | **II** = pause (defense pace, quarter length, restart) · **TIMEOUT** button between plays |
| Keyboard | `R` restarts the drive (sandbox) · `F1` AI debug overlay (three-finger tap on a phone) |

### Debug arguments
```
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

`tools/build_playbooks.gd` and `tools/gen_placeholder_sprites.gd` bootstrap the playbook and
placeholder sheet; re-running them **overwrites** those files.

All player names are used for personal, non-distributed play only; no logos or third-party art.
