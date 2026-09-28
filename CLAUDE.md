# Pocket Gridiron — notes for Claude

Godot 4.7 + GDScript retro football game. Design/roadmap: `PLAN.md`. Status table: `README.md`.

## Commands
- Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json`
- Full check (import + tests + sim smoke): `bash tools/run_tests.sh "$GODOT"`
- Linux/cloud: `source tools/install_godot_linux.sh` first (exports `$GODOT`).
- Balance sim: `godot --headless --path . -- --sim=300` (add `--verbose` for per-play lines,
  `--spam=slants` to repeat one play, `--nokey` to disable defensive memory). Steps at 60 Hz, ~5 s.
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
2. [ ] Bigger playbook (~16 offense incl. QB sneak, draw, screen, goal line; ~8 defense).
3. [ ] Situational play suggestion: preselect/highlight the best call (3rd & 1 -> short run, etc.).
4. [ ] Retro Bowl-style snap: pressing/dragging from the QB snaps and starts aiming in one
   gesture (no "tap the middle of the field"); dragging forward = scramble; runs stay simple.
5. [ ] Field detail: crowd/stands strip, midfield emblem, goalposts, pylons, down marker, turf texture.
6. [ ] Phase 2 – playable defense (PLAN.md §4).
7. [ ] Phase 3 – full game: clock, quarters, possessions, kicks/FG meter, AI offense, ai_vs_ai sim.
8. [ ] Phase 4 – roster import (GameData), cards affect play, team picker, lineup.
9. [ ] Phase 5 – packs, coins, save system, collection.
10. [ ] Phase 6 – season, challenges, polish.
