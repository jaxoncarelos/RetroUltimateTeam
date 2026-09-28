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
| 2 | Defense playable | next |
| 3 | Full game (clock, both halves, AI opponent) | — |
| 4 | Roster import, cards affect gameplay | — |
| 5 | Packs, economy, collection | — |
| 6 | Season, challenges, polish | — |

## Running

1. Install **Godot 4.7.x** (standard build, not .NET).
2. Open `project.godot`, press **F5**. The main scene is the Phase 1 drive sandbox.

### Controls (touch, or mouse on desktop)
| When | Gesture |
|---|---|
| Play call | tap a play card, then tap the field to snap |
| QB with the ball | drag **back** (slingshot) to aim, release to throw · drag **forward** to scramble |
| Ball carrier | runs forward on his own · hold + drag up/down to steer · drag back to slow |
| | flick up/down = juke · double-tap = dive |
| Keyboard | `R` restarts the drive |

### Debug arguments
```
godot --path . -- --autoplay          # CPU calls plays and throws; watch a drive
godot --headless --path . -- --sim=300 # 300 autoplay plays at 4x, prints stats, quits
godot --headless --path . -- --sim=80 --verbose   # plus one line per play
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
