# Pocket Gridiron — notes for Claude

Godot 4.7 + GDScript retro football game. Design/roadmap: `PLAN.md`. Status table: `README.md`.

## Commands
- Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json`
- Full check (import + tests + sim smoke): `bash tools/run_tests.sh "$GODOT"`
- Linux/cloud: `source tools/install_godot_linux.sh` first (exports `$GODOT`).
- Balance sim: `godot --headless --path . -- --sim=300` (add `--verbose` for per-play lines,
  `--spam=slants` to repeat one play, `--nokey` to disable defensive memory, `--smart` for
  situational calls, `--by-play` for per-play averages). Steps at 60 Hz; prints pts/drive.
- Debug a single matchup: a throwaway GUT test that builds a PlayRunner, steps `_physics_process`
  and prints positions is the fastest loop (see `tests/unit/test_play_runner.gd` for setup).
- Visual check without a device: `godot --path . --write-movie out/f.png --fixed-fps 20 --quit-after 200 -- --autoplay`, then look at the PNG frames.
- After adding/renaming a `class_name` script, run `godot --headless --import` so the global class cache updates.

## Conventions
- **Field space is yards**: x 0–120 (own goal line x=10, opponent's x=110), y 0–53.33 (top sideline 0). Offense always attacks +x. Only `FieldProjection` converts to pixels.
- Agents move by custom kinematics (`PlayerAgent.step`), not physics bodies. Brains set `desired_dir`/`throttle`; `ContactResolver` owns blocks/tackles.
- Every attribute→gameplay formula lives in `scripts/rules/rating_model.gd`; every constant in `GameplayTuning` (`data/tuning/gameplay_tuning.tres`) or `DefenseAITuning` (`defense_ai_tuning.tres`, CPU defense play calling/keying). Don't hardcode balance numbers elsewhere.
- Headless `--script` runs have no autoloads (`Events`, `UiTheme`), so anything touching PlayRunner can't run that way; use a GUT test or the `--sim` path.
- Pure logic (`scripts/rules`, models) must stay node-free so it is unit-testable.
- Static typing everywhere; tabs for indentation; match the surrounding comment density (`##` doc comments on classes and non-obvious functions).
- `data/roster.csv` uses the `keep` importer (raw file) — keep `roster.csv.import` as is.
- Plays/formations are `.tres`; `tools/build_playbooks.gd` regenerates (and overwrites) them.
- Commit `.uid` files; never commit `.godot/` or `export/`.

## Next steps / handoff (keep this list current; top item = next task)
User playtest feedback (2026-09-28) comes first, then the PLAN.md phases:
1. [x] Defensive adaptation: `DefenseMemory` + `AIPlayCaller.pick_defense` + keyed defenders
   (`PlayRunner.key_level`), constants in `data/tuning/defense_ai_tuning.tres`. `--spam=ID` /
   `--nokey` sim flags compare spamming vs mixing.
2. [x] Bigger playbook: 18 offense / 10 defense, 5+4 formations (all share the lineup slot
   names), press man (`press`), play action (`fake`), draws (`delay`), pitches (`range`), QB sneak
   (`sneak`). Carriers follow the play's lane (`PlayRunner.carrier_lane`). CPU QB = `CpuPasser`.
3. [x] Situational suggestion: `PlayAdvisor` (score/rank/pick); HUD bar = top 4 + BEST tag + MORE grid.
4. [x] Snap gesture: `HumanOffenseControl` press-on-QB snaps (`snap_requested`), same drag
   aims/scrambles/steers; tap still snaps; QB grab ring + chevrons in `PlayOverlay`.
   Balance (sim, `--smart` mix ≈ 3.0 pts/drive; every `--spam=X` lower). Known: INT rate high
   (~6%), run game ~2.5 ypc, sacks ~5% — retune in the Phase 3 ai_vs_ai pass.
5. [ ] Field detail: crowd/stands strip, midfield emblem, goalposts, pylons, down marker, turf texture.
6. [ ] Phase 2 – playable defense (PLAN.md §4).
7. [ ] Phase 3 – full game: clock, quarters, possessions, kicks/FG meter, AI offense, ai_vs_ai sim.
8. [ ] Phase 4 – roster import (GameData), cards affect play, team picker, lineup.
9. [ ] Phase 5 – packs, coins, save system, collection.
10. [ ] Phase 6 – season, challenges, polish.
