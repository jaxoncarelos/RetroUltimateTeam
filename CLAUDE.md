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
- Flow: boot.tscn routes → team picker (no save) / hub; debug flags → sandbox or match. Road to Glory lives
  behind MODE SELECT (rtg_* screens; its own season in `Profile.rtg`, separate from the UT season).
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
21. [x] Retro Bowl route (owner: "defense is too complicated, Dolphins gain 20+ every play"): CPU possessions are
   simulated as whole drives (`MatchController._sim_cpu_drive` -> `GameSim.sim_drive`/`drive_rate`: both teams'
   game OVR + start field position, yards fit the field, box score, clock runoff, banner, ball back by
   kickoff/punt/turnover). Playable defense only in challenges or with `--play-defense` (`--human=away`,
   `--drawtest`); defense pace setting hidden. Found on the way: the human's suggested defense (and the
   highlights auto-sim) always used Cover 0 (ties rank by playbook order). Pocket pass pro: `BlockBrain` cup
   (`POCKET` angles/radii around the QB) + `PlayRunner.pocket_assignments()` (closest threats -> nearest free
   blocker) + RB blitz pickup. Blitz first pressure 1.2 s -> 2.75 s; CPU-vs-CPU sacks now ~0.8/team (CPU QBs throw
   before base pressure arrives; engine AI-vs-AI only matters for balance tests now). Debug: `--quick --show=cpudrive`.
22. [x] Selling (owner: "sell cards I don't want, ~70% of value; a 99 Allen should pay ~1.5 Elite packs"):
   `CardRules.card_value(ovr, program)` (log-linear `VALUE_CURVE`, big jump at 90; X-Factor x1.4, Prime x1.2),
   `sell_price` = 70% of it (CardDef.quicksell, by the card's own OVR so training doesn't inflate it). Mid
   tiers are kept low (75: 250, 85: 700, 90: 6,300, 99: 60,200) so selling doesn't fund the grind
   (test_progression_pace/test_economy curves unchanged). Pack summary: SELL button under every card.
23. [x] Road to Glory (owner: "get drafted, play as one skill player, full controls revamp for QB/RB/WR/CB only"; plan
   docs/ROAD_TO_GLORY_PLAN.md). Engine: `PlayRunner.lock_slot`/`locked` (you never hand control to a teammate;
   `human_qb()` gates the human-QB protections), `RtgPad` (multi-touch floating stick + 5 context buttons, left-handed
   mirror) + `RtgControl` (analog movement, plant-and-cut by agility, BURST, carrier JUKE/SPIN/POWER = stiff arm or
   truck/DIVE with `ContactResolver.move_against` + `RatingModel.move_tackle_mult`, juke "bite" on defenders, WR
   CALL (CpuPasser favorite) / CATCH timing (`PlayRunner.aggressive_catch`), CB pre-snap shading, JAM, BALL, TACKLE,
   break telegraph `RatingModel.telegraph_time`), `FreeRunBrain`, `RtgOverlay`, camera follows you. Tuning:
   GameplayTuning "Road to Glory controls". Match: `MatchController.rtg` config plays only your side (CB: your offense
   is simmed by the generalized `_sim_cpu_drive`), coordinators call (`RtgPlay.oc_call`, AUDIBLE, HOT ROUTE), CPU coach
   handles 4th downs/PATs/timeouts, `RtgTracker` grades every play. Career: `RtgRules` (archetypes, OVR weights,
   XP/upgrade costs, draft, seasons, goals, awards, aging, contracts, retirement/HOF), `RtgFlow`, `Profile.rtg` +
   `rtg_legends`, screens rtg_create/draft (+`RtgDrill` combine & weekly practice)/hub/upgrade/postgame/offseason. Your
   player is a locked, unsellable UT card (`GameData.register_rtg`, id `rtg_<uid>`, legends frozen at peak). Pace
   (test_rtg_career): ~73 OVR after year 1, high 80s by year 5, same for 8/17-game seasons; leaving a game early pays
   like a sim (`RtgRules.played_share`). Debug: `--rtg-game=WR [--rtg-call=hb_dive]`, `--demo-profile --rtg=CB
   [--rtg-stage=draft|offseason] --screen=rtg_hub|rtg_create|rtg_draft|rtg_upgrade|rtg_postgame|rtg_offseason`.
24. [x] RTG playtest 1: receivers run routes fully by hand (`RtgControl.manual_routes`: no autopilot, let go = pull up;
   live gold route, red + "GET ON YOUR ROUTE" when `PlayRunner.route_offset` > `rtg_off_route`, CpuPasser docks
   openness off-route); easier high-point catch (window 0.6 s, early taps ignored, reach +1.3, box-out 1.2 yd, catch
   floor 85%, leap animation): contested 2/40 -> 35/40. Every script/scene must load (test_scripts_compile).
25. [x] AI overhaul (owner: "when I play WR the QB constantly throws picks"; plan docs/AI_OVERHAUL_PLAN.md): CPU QB =
   `CpuPasser` progression (hot read vs. blitz, read order by concept, routes "ready" at the break, anticipation) +
   `ThrowRisk` (pure: per-defender break time/arrival, lane picks, p_comp/p_int, value = p_comp*worth(yds) - p_int*cost;
   bar drops with time/pressure, INT cap by awareness, desperate late), checkdown/throwaway (out of bounds = "THROWN
   AWAY")/scramble; CPU aim error x`cpu_aim_error_mult`. Man coverage mirrors (cushion, hip flip, `trail_gap` by matchup,
   break read by rte-cov); zone `PlayRunner.zone_matches()` (one defender per receiver, QB eyes); `PursuitBrain`
   intercept angles + leverage; runner counts blockers (`run_shield_slack`). Tuning group "CPU quarterback brain".
   Lab (`LAB=cpu,wr_bot,wr_wild,runs -gdir=res://tests/lab -gprefix=lab_ai`): 47%->72% comp, INT 5%->1.3%, deep 43%;
   RTG WR ~50% of targets, ~0 picks. Not done yet: receiver option routes / scramble drill, offense game plan.
26. [x] Legends: `data/legends.csv` (90 vintage greats, era column, `keep` importer), `RosterDB.load_legends`,
   `CardRules.PROGRAM_LEGEND` (id `<player>_legend`, value x1.25, no development), packs legends (45,000, 1 legend
   guaranteed) + legend_draft (keep 1 of 3), Elite 2%/card, Gold 0.2%; jade LGND card style, sets/milestones.
   Debug: `--demo-profile --legends`, `--screen=store --tab=4`, `--screen=pack_open --pack=legends`.
Next ideas (after the owner's playtest): see MORNING_NOTES.md. RTG follow-ups: kick returns, S/LB/TE positions,
   injuries, rivalries / weekly storylines. Card revamp follow-ups: CPU star
abilities, ability UI on the lineup screen, ability-themed sets/objectives, balance pass on ability boosts.
