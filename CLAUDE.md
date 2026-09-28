# Pocket Gridiron — notes for Claude

Godot 4.7 + GDScript retro football game. Design/roadmap: `PLAN.md`. Status table: `README.md`.

## Commands
- Tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json`
- Full check (import + tests + sim smoke): `bash tools/run_tests.sh "$GODOT"`
- Linux/cloud: `source tools/install_godot_linux.sh` first (exports `$GODOT`).
- Full-game balance: `godot --headless --path . -- --ai-vs-ai=40` (~3 min; add `--verbose` for scores).
- Balance sim (one-drive sandbox): `godot --headless --path . -- --sim=300` (add `--verbose` for per-play lines,
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
- Flow: boot.tscn routes → team picker (no save) / hub; debug flags → sandbox or match.
  `-- --reset-save` wipes the local save. Autoloads: Events, UiTheme, Settings, GameData,
  SaveManager (disabled for --sim/--ai-vs-ai/--nosave), SceneRouter.

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
5. [x] Field detail: `StadiumArt` (turf grain/mow stripes, crowd tiles), `CrowdView` (animated
   stands, benches, sideline players), `FieldView` (emblem, goalposts, pylons, arrows, chains,
   down box). `--look=X,Y` pins the camera for screenshots.
6. [x] Phase 2 – playable defense: `DefenseSwitcher` (auto + tap-to-switch with hold),
   `HumanDefenseControl` (drag stick, tap carrier = dive, tap ball marker = leap/sprint, INT
   returns), jump timing (`RatingModel.jump_*`), INT returns/pick six, simple fumbles,
   `DebugOverlay` (F1 / 3 fingers), `DefensePace` + `Settings` autoload. Sandbox `--defend`,
   `--pace=`, `--autosnap`. No route preview for the human defense.
7. [x] Phase 3 – full game: `MatchController` (scenes/match/match.tscn, main via scenes/boot.tscn
   router), `GameClock` (NFL-time clock sped up so a 15:00 quarter ≈ Settings.quarter_minutes of
   play), `GameState` (score/possession/downs/timeouts/stats/OT), `KickModel` (kickoffs, punts,
   FG/PAT meter), `KickMeter` UI, PAT/2-pt choice, CPU 4th-down/2-pt/timeouts, pause menu,
   final screen. `--ai-vs-ai=N` batch: ~23 pts/team, 58% comp, 0.9 INT/team, 0 stuck plays
   (runs 2.9 ypc — still low).
8. [x] Phase 4 – `RosterDB` (CSV parse, bad-row errors, generated depth "KC OL3" players so every
   team fields 19 slots, card catalog), `GameData` autoload, `CardRules` tiers, `TeamRating`
   (weights, auto-best, difficulty rescale), `Profile` + `SaveManager` (atomic, .bak, migrate),
   `Collection` (starters, lineup, chemistry), `SceneRouter`, team picker, minimal hub, HUD
   player tag. roster.csv now has 4–6 stars for every team (verify names/numbers!).
   A/B: `--ai-vs-ai=20 --home-ovr=88 --away-ovr=64` → home wins 100%.
9. [ ] Phase 5 – packs, coins, save system, collection.
10. [ ] Phase 6 – season, challenges, polish.
