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
- Phone-aspect screenshot (585x270 viewport, real aspect, no crop): `godot --path . --resolution 1170x540 --fixed-fps 60 -- --snap=out.png,120 --demo-profile --screen=store --fake-notch` (`--fake-notch` simulates iPhone insets; UI insets come from `SafeArea`).
- After adding/renaming a `class_name` script, run `godot --headless --import` so the global class cache updates.

## Shipping an iOS build to the owner's phone (AltStore)
- Workflow `.github/workflows/ios-build.yml` (manual `workflow_dispatch`, ~15–20 min, macOS runner) builds an
  unsigned IPA and publishes it to the rolling GitHub release tagged `latest` (stable URL, replaced each run).
- To ship a fix: commit + push to `main`, then `gh workflow run ios-build.yml` (or `gh workflow run ios-build.yml --ref main`),
  watch with `gh run watch`, and tell the owner the release is ready
  (`gh release view latest --web` URL). The owner downloads the IPA in Safari and opens it in AltStore.
- OTA updates (`autoload/updater.gd`, must stay the FIRST autoload): each build also attaches `update-e<epoch>-<sha>.pck`
  to `latest`. The game downloads it on launch (needs repo secret `UPDATE_TOKEN`, a fine-grained read-only PAT for
  this repo's contents) and mounts it on the next launch, so most fixes reach the phone with no IPA reinstall.
  A new IPA is only needed when `autoload/updater.gd`, `project.godot` or the engine change — then bump
  `pocket_gridiron/engine_epoch` in project.godot. Never reference `BuildInfo` from `updater.gd`. A pack that
  doesn't reach the title screen is auto-discarded. CI stamps `scripts/build_info.gd` and `base_build`; don't commit those stamps.
- OTA status: the title screen shows `Updater.headline()` (downloading / "update ready - close the app fully and
  reopen it" / failures / "build has no update token"); coming back to the app re-checks. Each release's notes say
  `Auto-updates: ON` or `OFF (UPDATE_TOKEN secret missing)` (the build also raises a warning). engine_epoch is 2
  since the 2026-10-01 updater fix, so epoch-1 IPAs need one fresh IPA install.
- Export gotcha: Godot 4.7's text->binary resource conversion on export drops PackedStringArray properties, so
  resource string lists are `Array[String]` (pack `positions`/`mystery`, play `tags`/`counters`); never use
  PackedStringArray in exported .tres data. Keep the conversion ON: installed builds hold `.remap` files, and an
  update pack must ship its own remaps to override them (turning conversion off once left phones reading the old
  QB PACK). CI runs `tools/verify_pack.gd` on the new pack alone and stacked on the previous release's pack.
- The owner is away from the PC while testing: push fixes, trigger the build, and report the release link. Don't wait to be asked.

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
6. [x] Phase 2 – playable defense: `DefenseSwitcher` (manual: pre-snap tap to pick, SWITCH button / tap during play; no auto-switch),
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
9. [x] Phase 5 – `PackDef` (data/packs/*.tres) + `PackCatalog`, `EconomyRules` (odds, guarantees,
   weak-position weighting, buy+open atomically, quick-sell, duplicate training, sets, match
   rewards), screens: hub (rewards, difficulty), store, pack opening (flip/flash), collection
   (filters, detail: sell/train/lock), lineup (slot picker, auto-best), sets. `CardView`
   (48x64 code-drawn), `MetaUI` helpers, `Sfx` autoload (synthesized chiptune).
   Debug: `-- --demo-profile --screen=store` (unsaved KC career). Progression sim in
   test_economy: OVR 65 → 73 (20 games) → 80 (45) → 83 (100).
10. [x] Phase 6 – `SeasonRules` (league schedule, score model, standings, 7-seed playoffs,
   Elite pack for the title) + season screen; `ChallengeRules` (11 scenarios + daily from the
   date) + challenges screen + MatchController challenge mode; `ModeResults` feeds results
   back; settings screen; Franchise Chemistry boosts your players in matches; juice (hit
   shake, TD/turnover flash, synthesized SFX); first-game coach tips (Settings.tutorial_done).
   Not done: left-handed mode, iOS export, on-device perf pass, music.
11. [x] Playtest round 2 (docs/ART_AND_PROTECTION_PLAN.md): slimmer helmet/longer-body sprites, Madden-style feet ring on the ball carrier (incl. QB), pass-pro blocks hold longer (`pass_shed_mult` etc.; base coverages ~5 s to sack, blitzes ~1.7 s).
14. [x] Defense revamp: hero per call (`PlayRunner.hero_for_call`), draw-it-up path (`DrawnPathBrain`, drag from your hero pre-snap), block duels for your rusher (leverage bar + TAP! window in `ContactResolver.duel_move`), burst tap, quicker steering, ball-hawk timing ring. CPU rushers keep the timer system (sim balance unchanged). Tried mirror-blocking OL: over-protects (1 sack per 250 passes), reverted. Tuning: GameplayTuning "Hero moves"/"Hero block duels". Debug: sandbox `--hero-demo`.
17. [x] Voted polish round: coach skill tree (`CoachPerks`, coach screen, perks tune matches/economy), music + crowd (`Music` autoload, synthesized loops, worker-thread render), instant replay (`PlayRunner.record_replay`, `ReplayPlayer`, auto after TD/turnover/25+ yd gain), weather + night (`GameConditions`, `WeatherFx`, rolled per fixture in `GameFlow.roll_conditions`). Debug: `--weather=rain|snow|fog|night`, `--replay-any --show=snap`, `--music-debug`, `--coach-demo`.
16. [x] Throw feel: THROW AIM setting (Settings.aim_sens), tap / second-finger tap cycles pass type (`PlayRunner.pass_kind`), human QB free time 2.4 s + sidestep immunity (`qb_free_time`, `qb_evade_*`), play-action rush hold (`pa_rush_bite`), fewer CPU blitz calls vs human (`blitz_weight`). Build id: `BuildInfo.ID` (CI stamps the commit; title + options show it). Debug: `--human=away --drawtest [--drawslot=DL2]`.
15. [x] Sim: `GameSim` drive-by-drive with momentum + matching box score (SIM GAME and sim-the-rest).
13. [x] A league always runs: the hub starts a season if none exists (`GameFlow.needs_season/start_season`), so PLAY plays league games and the other teams are simmed (fixes division standings staying 0-0).
12. [x] Sim the rest of a game (pause menu, or offered at halftime when up 28+: `MatchController._sim_rest_of_game`); Super Bowl title now also pays 3,000 coins + a locked 99 CHAMP card of the franchise star (`EconomyRules.champion_reward`, `CardRules.PROGRAM_CHAMP`). Playoffs/Super Bowl already existed in `SeasonRules`. Debug: `--show=half|simrest`, `-- --demo-profile --champ`.
18. [x] Card revamp + playbook (playtest 2026-10-01): X-Factor cards (`CardRules.PROGRAM_XFACTOR`, id
   `<player>_xf`, +2 OVR, 74+ players) carry one `AbilityRules` ability (17: GUNSLINGER, BELL COW, SACK ARTIST,
   ICE IN THE VEINS…; scopes drive/series/game/clutch). `AbilityTracker` in MatchController counts plays
   (PlayRunner results now carry `carrier_slot`/`tackler_slot`/`ball_def_slot`), resets per `GameState.drive_no`,
   boosts the lineup before each snap; HUD chips + "X-FACTOR!" pop-up. Human team only (CPU has none yet).
   Store tabs (`PackCatalog.SHELVES`): Mystery (secretly another pack), Draft (keep 1 of 3,
   `Profile.pending_pick`, `scenes/meta/draft.tscn`), X-Factor, position packs incl. Trenches.
   Opening: tier climb with fake-outs, mystery slot-machine spin, X-Factor sting, tap-to-flip summary.
   Playbook 30 offense (12 new concepts, every eligible runs routes); `PlayAdvisor.suggest` rotates the
   4-play bar (best first, then a varied weighted mix, recent calls demoted). Debug: `--demo-profile --xf
   --quick --show=xf`, `--screen=store --tab=1`, `--screen=draft`, `--screen=pack_open --pack=mystery`.
19. [x] Progression v3 (owner: "a 95 Mahomes after one game kills the hype", then "too grindy: at least one
   good player your first season if you're lucky and smart"): Core cards (`<player>_core`, `CardRules.core_ovr`:
   real 80->70 … 96->79 … 99->81) for every 80+ player are the common version; the real card shows a PRO chip.
   Franchise star starts as his Core card, starter team ~70, starter pack guarantees one Gold (80-89).
   Gold 8,000 (4% elite/card), Elite 40,000; elite tier weight `ELITE_FALLOFF` 0.75 per OVR above 90, primes
   0.05x; "Win 5" objective pays a Gold pack, "Win 10" a Draft pack; no Elite at coach level 25; slower card
   development (XP 60/game, levels 600+150n). test_progression_pace: saving for Gold packs gives an 85+ within
   ~20 games and often a 90+ in the first season; 95+ stays rare.
20. [x] Pocket/speed pass (owner: "5 s in, receiver only 20 yds downfield, nobody near my QB"): everyone faster
   (speed 5.2 + 4.8*spd/99 yd/s, accel 11 + 13*acc/99) and `pass_shed_mult` 1.9 -> 1.25. test_pocket_time (you at QB,
   base coverages, no throw): receiver 20 yds downfield ~2.7 s, first pressure ~3.2 s, sack ~4.2 s.
   Ball flight: arm 20 + 14*thp/99 yd/s (was 17 + 13), `ball_gravity` 30 -> 48 so lobs drop faster
   (85 THP: 15 yd 0.47 s, 22 yd 0.9 s, 30 yd 1.3 s (was 1.6), 50 yd 1.6 s (was 2.0)); test_flight_times_feel_quick.
Next ideas (after the owner's playtest): see MORNING_NOTES.md. Card revamp follow-ups: CPU star
abilities, ability UI on the lineup screen, ability-themed sets/objectives, balance pass on ability boosts.
