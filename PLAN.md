# POCKET GRIDIRON — Implementation Plan (Godot 4 + GDScript)

> Working title: **Pocket Gridiron** (rename freely). Personal, never-published, offline, mobile, landscape.
> First implementation step after approval: copy this plan to `PLAN.md` in the project root.

## Context

The goal is a retro 2D arcade football game: chunky pixel art, quick drives, and easy touch controls in the spirit of Retro Bowl. It adds a Madden Mobile 2016-style Ultimate Team meta-game with coins, packs, and real NFL player cards. The key difference from Retro Bowl: **you play both offense and defense**. The project folder is currently empty (greenfield).

### Decisions locked in (from Q&A)
| Topic | Decision |
|---|---|
| Engine | **Godot 4.x latest stable (4.5+)**, GDScript, **Compatibility renderer** (best for 2D mobile) |
| Experience | Some game-engine experience → moderate detail on engine concepts |
| Platforms | **Android + iOS** (Android sideload from Windows; iOS needs a Mac + Xcode at export time) |
| Team size | **9v9 target**, formations data-driven so **7v7 is a data-only fallback** |
| Camera | Horizontal side-scroll, field runs left↔right, camera follows the ball |
| Your team | **Pick a real NFL team.** You start with its real roster as low-tier cards and upgrade through packs |
| Defense control | Auto-switch to the most relevant defender + tap any defender to take control |
| Special teams | Minimal: auto kickoffs/punts, FG/PAT via timing swipe, ~2–3 min quarters (~10–15 min games) |
| Art | **Original** sprites in the Retro Bowl-like style (no ripped assets). Generated placeholders first, then a palette-swap template refined in Pixelorama/Aseprite |

---

## 1. Architecture overview

**Principles**
- **Simulation in yards, rendering in pixels.** All gameplay math uses field units (yards, x = 0–120 incl. end zones, y = 0–53.3). A `FieldProjection` converts to screen (x ≈ 12 px/yd, y ≈ 4 px/yd compressed, z/height → vertical offset + shadow). This keeps ratings and tuning independent of art.
- **Custom kinematics, not physics bodies.** Agents are `Node2D`s moved by code (velocity, acceleration, turn rate from ratings). Contacts use distance checks (18 agents is cheap). This is deterministic, easy to tune, and gives no physics jank.
- **Data-driven everything:** roster CSV, team JSON, plays/formations/packs/tuning as Godot `Resource` (`.tres`) files.
- **Pure logic separated from nodes** (rules, clock/downs, ratings math, economy, save) so it can be unit-tested headless with GUT.
- **Signal bus autoload** (`Events`) for cross-system messages (touchdown, play_ended, coins_changed, card_pulled).
- **Seeded RNG per match** for reproducible bugs and AI-vs-AI balance runs.

### Autoloads (singletons)
| Autoload | Responsibility |
|---|---|
| `Events` | Global signals only |
| `GameData` | Loads `roster.csv` + `teams.json` at boot → dictionaries of `PlayerData`, `TeamData`; generates `CardDef` catalog; lookups |
| `SaveManager` | Load/save `SaveData` to `user://save.json`; atomic write; versioned migrations; autosave on app pause |
| `Economy` | Coins, pack purchase, pack opening (odds), quick-sell/convert, rewards granting |
| `SceneRouter` | Scene transitions with pixel fade; passes `MatchConfig` into the match scene |
| `Settings` | Audio, control sensitivity, game length, defense pace, difficulty, left-handed mode |

### Match scene: key classes and flow
```
MatchScene (Node2D)
├── MatchController        state machine + owns GameState (score, clock, down, dist, LOS, possession)
│   ├── GameClock          quarter time, play clock, runoff rules, timeouts
│   ├── DownTracker        downs, first-down line, turnover on downs, safeties
│   └── PlayCaller (x2)    HumanPlayCaller (UI) | AIPlayCaller (situation tables)
├── PlayRunner             spawns/positions 18 PlayerAgents from FormationDef + PlayDef, assigns Brains, runs the live play, emits play_ended(PlayResult)
│   ├── PlayerAgent (x18)  kinematics (from ratings), sprite/anim, current Brain, optional HumanControl
│   │   └── Brains:        QBBrain, RouteBrain, BlockBrain, RunnerBrain, RushBrain, ManCoverBrain, ZoneBrain, PursuitBrain
│   ├── Ball               states: SNAP → HELD → IN_AIR(x,y,z arc) → CAUGHT/LOOSE/DEAD
│   ├── ContactResolver    tackles, broken tackles, catches, deflections, INTs, block engagements, fumbles (uses RatingModel)
│   └── DefenseSwitcher    picks the auto-controlled defender; handles tap-to-switch
├── TouchInput             converts InputEventScreenTouch/Drag into intents: AimDrag, Steer, Flick, Tap(target)
├── CameraRig              follows ball with look-ahead, clamps to field, pixel-snapped
├── FieldView              turf, yard lines, end zones in team colors, LOS + first-down markers
└── MatchHUD (CanvasLayer) scorebug, down&dist, clock, play-call cards, aim arc, result banners
```
**Flow of one play:** `MatchController` asks both `PlayCaller`s for a `PlayDef` → `PlayRunner.setup(offPlay, defPlay, formation, lineups)` → human taps to snap → `PlayRunner` ticks Brains + `ContactResolver` in `_physics_process` → `play_ended(PlayResult{yards, type, turnover, clock_stopped, scoring})` → `MatchController` applies it to `GameState`, runs off clock, and moves to the next state.

**MatchController states:** `PREGAME → KICKOFF(auto) → PLAY_CALL → PRE_SNAP → LIVE → WHISTLE → RESULT → (PAT/FG | PUNT(auto)) → … → HALFTIME → … → FINAL → POSTGAME_REWARDS`

**`RatingModel` + `GameplayTuning.tres`:** one place for every attribute→gameplay formula, with all constants in a tunable resource (see §3). This is the core balancing surface.

---

## 2. Godot project folder structure
```
res://
├── project.godot
├── autoload/            events.gd, game_data.gd, save_manager.gd, economy.gd, scene_router.gd, settings.gd
├── data/
│   ├── roster.csv       ← THE one file you edit to update rosters (import mode: "Keep File")
│   ├── teams.json       32 teams: abbr, city, name, conf, div, colors
│   ├── tuning/          gameplay_tuning.tres, economy_config.tres, difficulty_tiers.tres
│   ├── formations/      off_shotgun.tres, off_iform.tres, def_43.tres, def_nickel.tres …
│   ├── plays/offense/   *.tres (PlayDef)
│   ├── plays/defense/   *.tres
│   ├── packs/           bronze_pack.tres, silver_pack.tres, gold_pack.tres, elite_pack.tres
│   └── challenges/      *.tres (ChallengeDef)
├── scripts/
│   ├── models/          player_data.gd, team_data.gd, card_def.gd, card_instance.gd, pack_def.gd,
│   │                    formation_def.gd, play_def.gd, route_def.gd, challenge_def.gd, save_data.gd
│   ├── rules/           game_state.gd, game_clock.gd, down_tracker.gd, rating_model.gd, team_rating.gd
│   ├── match/           match_controller.gd, play_runner.gd, player_agent.gd, ball.gd, contact_resolver.gd,
│   │                    field_projection.gd, camera_rig.gd, defense_switcher.gd
│   ├── match/brains/    brain.gd (base), qb_brain.gd, route_brain.gd, runner_brain.gd, block_brain.gd,
│   │                    rush_brain.gd, man_cover_brain.gd, zone_brain.gd, pursuit_brain.gd
│   ├── match/ai/        ai_play_caller.gd, qb_read_logic.gd, difficulty.gd
│   ├── input/           touch_input.gd, human_control.gd
│   ├── meta/            pack_opener.gd, collection.gd, lineup.gd, season.gd, sim_engine.gd, challenges.gd
│   └── ui/              shared widgets (pixel_button.gd, card_view.gd, team_badge.gd)
├── scenes/
│   ├── boot.tscn, title.tscn, hub.tscn
│   ├── match/           match.tscn, player_agent.tscn, ball.tscn, hud.tscn
│   ├── meta/            store.tscn, pack_open.tscn, collection.tscn, lineup.tscn, season.tscn, challenges.tscn
│   └── debug/           drive_sandbox.tscn (one-drive test bed), ai_vs_ai.tscn (headless balance runs)
├── art/
│   ├── players/         player_template.png (grayscale-keyed sheet) + .tres SpriteFrames
│   ├── field/, ui/, cards/, badges/, fonts/ (pixel bitmap font)
│   └── shaders/         palette_swap.gdshader
├── audio/sfx, audio/music
├── addons/gut/          unit testing
├── tests/unit/          test_game_clock.gd, test_down_tracker.gd, test_rating_model.gd, test_pack_odds.gd,
│                        test_economy.gd, test_save_roundtrip.gd, test_roster_import.gd
└── tools/               gen_placeholder_sprites.py (Pillow), derive_ratings.py (stats → CSV), validate_roster.gd (EditorScript)
```

**Key project settings:** base viewport **480×270** (16:9), stretch mode `viewport`, aspect `expand` (handles 19.5:9 phones; extra width shows more field), texture filter `Nearest`, `snap_2d_transforms_to_pixel = true`, orientation `landscape` (sensor), input `emulate_touch_from_mouse = true` for desktop testing, Compatibility renderer, target 60 fps.

> **Godot gotcha:** Godot imports `.csv` as a translation file by default. Set `roster.csv` → Import tab → **"Keep File (no import)"** so it's shipped raw and readable via `FileAccess` in exported builds.

---

## 3. Data models

### Roster file (`data/roster.csv`)
One row per real player. **Blank attribute = auto-filled from position defaults**, so you can add players with just name/team/pos/ovr.

| Column | Meaning |
|---|---|
| `id` | stable slug, e.g. `mahomes_patrick` (never changes, used by saves) |
| `name`, `team` (abbr), `pos`, `jersey` | identity. pos ∈ QB RB WR TE OL DL LB CB S K |
| `ovr` | real-world overall (40–99) |
| `spd`, `acc`, `str`, `awr` | speed, acceleration, strength, awareness (all positions) |
| `thp`, `tha` | throw power, throw accuracy (QB) |
| `cth`, `rte`, `car`, `elu` | catching, route running, ball security, elusiveness (skill players) |
| `blk` | blocking (OL/TE/RB) |
| `tak`, `cov`, `prs` | tackling, coverage, pass rush (defense) |
| `kpw`, `kac` | kick power, kick accuracy (K) |

**`teams.json`:** `{ "abbr":"KC", "city":"Kansas City", "name":"Chiefs", "conf":"AFC", "div":"West", "primary":"#E31837", "secondary":"#FFB81C", "tertiary":"#FFFFFF" }`, rendered as a 16×16 pixel shield badge (team colors + abbreviation). No official logos.

**Sample roster (starting file, ratings are illustrative placeholders, not official).** Phase 1 ships 4 teams (KC, PHI, BUF, SF) × ~14 players (enough for 9v9 starters + K + a few backups):
```csv
id,name,team,pos,jersey,ovr,spd,acc,str,awr,thp,tha,cth,rte,car,elu,blk,tak,cov,prs,kpw,kac
mahomes_patrick,Patrick Mahomes,KC,QB,15,97,78,84,70,97,96,92,,,,,,,,,,
kelce_travis,Travis Kelce,KC,TE,87,92,80,83,74,95,,,94,93,85,70,68,,,,,
jones_chris,Chris Jones,KC,DL,95,95,76,86,94,90,,,,,,,,82,,97,,
mcduffie_trent,Trent McDuffie,KC,CB,22,90,91,92,62,86,,,68,,,,,78,91,,,
butker_harrison,Harrison Butker,KC,K,7,88,,,,,,,,,,,,,,,94,90
hurts_jalen,Jalen Hurts,PHI,QB,1,90,85,87,78,88,88,84,,,,,,,,,,
barkley_saquon,Saquon Barkley,PHI,RB,26,97,92,94,82,90,,,76,,92,96,55,,,,,
brown_aj,A.J. Brown,PHI,WR,11,94,89,90,82,90,,,93,91,86,80,,,,,,
allen_josh,Josh Allen,BUF,QB,17,96,82,85,84,92,99,88,,,,,,,,,,
mccaffrey_christian,Christian McCaffrey,SF,RB,23,92,90,93,80,93,,,90,85,90,93,62,,,,,
warner_fred,Fred Warner,SF,LB,54,96,86,88,78,97,,,70,,,,,94,90,72,,
```
(The full sample file gets generated in Phase 1. Verify team assignments against a current roster when you do the real dataset.)

### Deriving ratings from real stats (`tools/derive_ratings.py`, optional, offline)
1. Pull season stats (e.g. nflverse / Pro-Football-Reference / Next Gen Stats CSV exports) and combine data.
2. For each attribute, compute a **percentile within position** over players with a minimum snap count, then map percentile → 55–99 (`rating = 55 + 44 * pct^0.8`, so the elite tail spreads out).
3. Stat → attribute mapping (examples):
   - `spd` ← 40-yard dash (4.25s→99, 4.90s→60) or NGS top speed; `acc` ← 10-yd split
   - `thp` ← avg intended air yards + deep-attempt %; `tha` ← CPOE / on-target %
   - `awr` ← EPA/play (QB), INT rate inverse, years of experience
   - `cth` ← catch rate over expected + drop rate inverse; `rte` ← NGS average separation
   - `car` ← fumbles per touch inverse; `elu` ← yards after contact + missed tackles forced
   - `tak` ← missed tackle % inverse; `cov` ← passer rating allowed inverse, targets per coverage snap
   - `prs` ← pressure rate, sacks; `blk` ← pressures/sacks allowed per pass-block snap inverse
4. `ovr` = position-weighted average (e.g. QB: tha 30, thp 25, awr 25, spd 10, acc 10; WR: spd 25, cth 25, rte 25, acc 15, elu 10; CB: cov 35, spd 25, acc 15, awr 15, tak 10), then hand-adjust stars.
5. The script writes `roster.csv`. The game only ever reads the CSV.

### Runtime models (GDScript classes)
```gdscript
# PlayerData (RefCounted, built from CSV)       — the real player
id, name, team, pos, jersey, ovr, attrs: Dictionary  # {"spd":92, ...}

# CardDef (generated per player × eligible tier) — a collectible version
id = "%s_%s" % [player_id, tier]   # "mahomes_patrick_gold"
player_id, tier (BRONZE/SILVER/GOLD/ELITE), card_ovr, attrs (scaled), quicksell_value

# CardInstance (owned, saved)
uid (int), card_def_id, acquired_unix, locked (bool), training_boost (0..3)

# TeamData: abbr, city, name, conf, div, colors[3]
# FormationDef (Resource): side, slots: Array[{slot:"WR1", pos:"WR", offset:Vector2 (yards from ball)}]
# PlayDef (Resource): name, side, formation, category (RUN/SHORT/DEEP/PA/SCREEN | ZONE/MAN/BLITZ/PREVENT),
#   assignments: {slot → {type: ROUTE|BLOCK|HANDOFF|RUSH|MAN|ZONE, route: PackedVector2Array, zone: Rect2, target_slot}}
# PackDef (Resource): name, price, card_count, odds: {BRONZE:.., SILVER:.., GOLD:.., ELITE:..}, guaranteed_min_tier, position_filter
# ChallengeDef (Resource): title, start_state (score, clock, LOS, down), goal (win/score/hold), opponent, reward_pack
```

**Card tier → card OVR.** Every player can exist in several tiers, like MUT's program versions. The tier's range sets the card OVR, and the player's real OVR places the card within that range:
| Tier | Card OVR range | Eligible if real OVR ≥ | Quick-sell |
|---|---|---|---|
| Bronze | 55–64 | any | 25 |
| Silver | 65–74 | any | 100 |
| Gold | 75–84 | 75 | 500 |
| Elite | 85–99 | 85 | 2,500 |

`card_ovr = lerp(tier_min, tier_max, (real_ovr - 60)/39)`. Card attributes = real attributes × `(card_ovr / real_ovr)`, clamped 40–99. So an Elite Mahomes is the real Mahomes, and a Bronze Mahomes is a weaker version that still has his throw-power profile.

**Starting team:** you pick an NFL team and receive that team's real players as cards. Its top ~5 players come as **Silver** and everyone else as **Bronze**, so you start around team OVR ~62–65 with your real favorites. Packs pull higher-tier versions of any player.

### SaveData (`user://save.json`)
```json
{
  "version": 1,
  "franchise_team": "KC",
  "coins": 1200,
  "next_uid": 58,
  "cards": [{"uid":1,"def":"mahomes_patrick_silver","t":1769000000,"locked":false,"boost":0}],
  "lineup": {"QB":1,"RB":7,"WR1":9,"WR2":12,"TE":3,"OL1":20,"OL2":21,"OL3":22,"OL4":23,
             "DL1":30,"DL2":31,"DL3":32,"LB1":40,"LB2":41,"CB1":50,"CB2":51,"S1":52,"S2":53,"K":5},
  "season": {"year":1,"week":4,"schedule":[...],"results":[...],"standings":{...}},
  "challenges": {"completed":["two_min_drill_1"],"daily_seed":20260927},
  "stats": {"games":12,"wins":8,"packs_opened":9},
  "settings": {...}
}
```
- Saves store **only ids** (card def ids, player ids). If a player leaves the CSV, the card shows as "Retired" instead of crashing.
- Atomic write: write `save.tmp`, then rename it over `save.json`; keep `save.bak`. `version` + `migrate(data)` chain.
- Autosave after every match, pack opening, and lineup change, plus on `NOTIFICATION_APPLICATION_PAUSED` (mobile).
- Mid-match state is **not** saved in v1 (a quit counts as a forfeit or a resume prompt). This could be added in Phase 6.

---

## 4. Gameplay design

### Field and formations (9v9)
- **Offense (9):** QB, RB, WR1, WR2, TE, OL×4 (OL as individual cards; on-field they're simplified block behaviors).
- **Defense (9):** DL×3, LB×2, CB×2, S×2.
- **+ K** in the lineup (used for FG/PAT/kickoff distance).
- **7v7 fallback** = new FormationDefs with 2 OL / 2 DL / 1 LB. No code changes.

### Offense controls
1. **Play call:** 4 play cards shown (Run, Short Pass, Deep Pass, + 1 situational). A "More plays" button opens a small playbook grid (~12 offensive plays total). Routes are previewed on the field.
2. **Snap:** tap anywhere.
3. **Passing (drag-to-aim):** after the drop-back, touch and drag *backwards* anywhere on screen (slingshot). A dotted arc shows the landing spot. Drag length = distance/loft (short drag = bullet, long = lob over defenders). Release to throw. The aim wobble cone grows with pressure and shrinks with `tha`. Ball flight is a true x/y/z arc with a shadow.
4. **Running (QB scramble, handoff, after catch):** the ball carrier auto-runs forward. Hold and drag vertically to steer (relative to your touch-down point, with a dead zone). A **quick flick up/down = juke** (cooldown; success scales with `elu`). **Double-tap = dive** for extra yards/end zone.
5. Handoff plays hand off automatically; you control the RB immediately.

### Defense controls ("fast and fun")
1. **Play call:** 4 cards (Cover 2, Cover 3, Man, Blitz) + more (Zone Blitz, Prevent, Goal Line). About 8 total.
2. **Auto-control:** `DefenseSwitcher` hands you the defender with the best chance to affect the play. Pre-throw that's the defender nearest the QB's likely target; ball in air, the one nearest the landing spot; after the catch or handoff, the nearest pursuer with an angle. Your defender gets a highlight ring. **Tap any defender to take control** (a manual choice holds for 1.5s before auto-switch can override).
3. **Moving:** drag to move (virtual stick anchored at touch point).
4. **Tackle:** tap near the ball carrier while in range → dive tackle. Success = `tak` vs carrier `elu`/`str`, distance, and angle. A miss leaves you on the ground briefly.
5. **Ball in air:** a pulsing landing marker appears. Tap when your defender is near it → jump. Early/late timing gives a deflection, perfect timing plus `cov`/`cth` gives a chance at an **INT**.
6. **Pace options (Settings → Defense Pace):** **Every snap** (default) / **Key downs** (1st/2nd down auto-simulated with a fast result ticker, you play 3rd/4th down + red zone + final 2 min) / **Highlights only**. This keeps defense from becoming a chore.
7. Plays are short by design: the CPU QB gets the ball out in ~2.5s on average.

### Clock, downs, scoring
- 4 quarters, **default 2:30 game minutes each** (configurable 1:30–5:00). The live-play clock runs at real time × 1. Between plays, auto-runoff is 25s unless the clock is stopped (incomplete, out of bounds, score, turnover, timeout, first down inside 2:00 rule simplified). 3 timeouts per half. Two-minute warning.
- TD 6, PAT kick (timing swipe) 1 or 2-pt try (one play from the 2), FG 3, safety 2.
- Kickoffs auto-simulated (touchback, ball at the 25; rare return yardage). Punts are chosen from the play call on 4th down and auto-resolved (net distance from K `kpw` ± random).
- **FG/PAT:** swipe up through a moving accuracy meter. Meter speed scales with distance, meter width with `kac`, max range with `kpw`.
- Overtime: simplified, one possession each, then sudden death.

### How card attributes affect play (`RatingModel`)
| Attribute | On-field effect |
|---|---|
| `spd` | Max run speed (`4.0 + spd/99 * 4.5` yd/s, tunable) |
| `acc` | Time to top speed and cut recovery |
| `str` | Block/shed duels, broken tackles, tackle-drag yards |
| `awr` | AI reaction delay (0.35s at 60 → 0.10s at 99); QB read quality; defender zone discipline |
| `thp` | Ball velocity, max throw distance, lob apex |
| `tha` | Aim error cone radius; pressure multiplies it (reduced by `awr`) |
| `cth` | Catch probability: base per `cth`, minus contest penalty (nearest defender distance × their `cov`) |
| `rte` | Cut sharpness (turn-rate at route breaks) → separation at break points |
| `car` | Fumble chance on hits (esp. big hits from high `tak`/`str`) |
| `elu` | Juke success, broken-tackle chance vs. `tak` |
| `blk` | OL: time before DL disengages; RB/TE blocking in run plays |
| `prs` | DL/blitzer: time-to-pressure and sack chance vs. OL `blk` |
| `tak` | Tackle success on contact/dive |
| `cov` | Man trail distance, zone reaction, deflection/INT chance |
| `kpw`/`kac` | FG range, meter width |

Contact outcomes use **soft probabilities**: `p = sigmoid((attacker - defender + situational) / k)`. Higher ratings skew outcomes without guaranteeing them. All `k`s and bases live in `gameplay_tuning.tres`.

### Opponent AI
- **AIPlayCaller (offense & defense):** weighted tables by situation (down, distance bucket, field zone, score diff, clock), plus per-team tendencies (derived from roster strengths: strong QB/WR → pass-heavy). It adds a small anti-repetition memory and **adapts**: if you beat the same play call 3× it adjusts weights.
- **CPU QB (`qb_read_logic`):** after the drop-back it scans its progression (by play) every `read_interval` (from `awr`). The openness score is separation, minus defender closing speed, minus projected INT risk along the arc. It throws when a target is above the threshold, scrambles if pressure is imminent and there's a lane, and throws the ball away/takes the sack otherwise.
- **CPU runner:** steers toward the lane with the most space (sample 5 directions, score by distance to nearest defender), jukes the closest tackler.
- **CPU defenders (non-controlled teammates too):** man = mirror receiver with lag from `cov`/`awr`, zone = drop to zone, react to the QB's eyes/ball, pursuit = intercept-course steering to the carrier.
- **Difficulty (`difficulty.gd` + `difficulty_tiers.tres`):** Rookie / Pro / All-Pro / Legend multiply AI reaction, read quality, INT aggression, and **opponent effective ratings**.

### Difficulty scaling vs your team strength
- Opponents are real NFL teams, but their on-field ratings are **rescaled**: `opp_effective_ovr = your_team_ovr + tier_offset + (real_team_rank_delta × 0.3)`, clamped. Offsets: Rookie −8, Pro −2, All-Pro +3, Legend +7. Real team identity (who's good) still matters, but the game never becomes trivial as your OVR climbs.
- Season mode uses Pro by default, and playoffs +2. Challenges set their own difficulty.

---

## 5. Meta-game

### Packs & odds (`economy_config.tres`)
| Pack | Price | Cards | Bronze | Silver | Gold | Elite | Guarantee |
|---|---|---|---|---|---|---|---|
| Bronze Pack | 500 | 5 | 80% | 18% | 2% | 0% | — |
| Silver Pack | 1,500 | 5 | 30% | 55% | 13% | 2% | 1 Silver+ |
| Gold Pack | 5,000 | 6 | 0% | 50% | 42% | 8% | 1 Gold+ |
| Elite Pack | 15,000 | 5 | 0% | 20% | 55% | 25% | 1 Elite |
| Position packs (QB/WR/Defense…) | reward-only | 3 | per-pack | | | | |

Pick tier by odds, then a random player eligible for that tier (weighted slightly toward positions you're weak at, a gentle anti-frustration touch). Pack opening shows cards face-down; tap to flip in ascending rarity with bigger flashes for Gold/Elite.

### Coins
- Match: win 300 / loss 120 / tie 180, × difficulty multiplier (0.75 / 1.0 / 1.3 / 1.6). Bonuses: +20/TD, +25/INT or sack by you, +50 shutout, +100 "comeback win".
- Season: +500 playoff berth, +1,000 per playoff win, **Super Bowl win = Elite Pack**.
- Challenges: pack rewards (see §6). Daily login/first win of day: +200.

### Duplicates & collection
- **Quick-sell** any unlocked card for its tier value.
- **Convert duplicates → Training**: feed a duplicate of the *same player* to a card for +1 OVR (max +3 boosts). This makes dupes of favorites feel good.
- **Sets (MUT-style):** e.g. "Trade 10 Bronze → 1 Silver Pack", "5 Silver → Gold Pack", "Any 3 KC Golds → Elite KC player". This is cheap to build (a SetDef resource) and a big retention driver.
- Collection screen: filter by tier/position/team, sort by OVR. Card design is a 48×64 pixel card with tier-colored border, team-color stripe, big OVR number, pos, name, badge, and a 16×16 mini-sprite.

### Progression curve targets (tune with the Phase 5 sim)
| Milestone | Games played | Team OVR |
|---|---|---|
| Start | 0 | ~63 |
| First Gold starters | ~5 | ~67 |
| Solid team | ~15 | ~74 |
| First season done (17 + playoffs) | ~20 | ~78 |
| Contender | ~45 | ~84 |
| Endgame | ~100+ | 88–92 |
Difficulty rescaling (§4) keeps games competitive. Progress is *felt* through your players visibly outrunning and out-throwing opponents at the same effective difficulty tier. Higher tiers pay more, so the long-term incentive is climbing difficulty.

### Team management
- **Lineup screen:** 19 starter slots on a pixel formation diagram. Tap a slot → list of eligible cards sorted by OVR, with "Auto-Best Lineup" button. Bench = everything else.
- **Team OVR** = weighted average of starters: QB 20%, WR/TE 18%, RB 8%, OL 14%, DL 14%, LB 9%, DB 15%, K 2% (split among slots).
- **Chemistry (recommendation: include a *light* version in Phase 6, not before).** Use a **"Franchise Chemistry"** bonus: each starter who is a real player of your chosen NFL team adds +0.5 OVR (max +3) to the team. This fits the "pick your NFL team" choice, rewards pulling your team's stars, is one formula and one UI badge, and avoids MUT's complex scheme chemistry.

---

## 6. Game modes & loops
- **Quick Match:** pick opponent + difficulty → play → rewards.
- **Season:** 17-game schedule (setting: 8-game short season) vs real NFL teams, standings computed by `sim_engine.gd`. It simulates other games from team ratings with a quick Poisson-ish score model. Then 7-team-per-conf playoffs → Super Bowl.
- **Challenges:** scenario vignettes built from `ChallengeDef.start_state` (e.g. "Down 4, 1:45 left, own 30 — score a TD", "Protect a 3-pt lead, stop them on 4 downs", "Throw 2 TDs in a quarter"). These reuse the match engine with a custom start state and win condition. There are ~20 handmade ones, plus a **Daily Challenge** generated from a date seed. They reward packs.

**Loops**
- **Moment-to-moment (5–20s):** call play → snap → aim/steer or chase/tackle → result banner → next call. Every possession switches your role (offense ↔ defense).
- **Session (10–20 min):** one game → coins + stats → open a pack → upgrade lineup → next game / challenge.
- **Long-term (weeks):** seasons and Super Bowl runs, climbing difficulty tiers, completing sets, pulling Elite versions of your franchise's stars, and maxing chemistry.

---

## 7. UI flow & retro style
```
Boot (load data+save) → Title → [first run: Pick Your Team → starter pack reveal] → HUB
HUB: PLAY (Season | Quick Match | Challenges) · TEAM (Lineup | Collection | Sets) · STORE (Packs) · SETTINGS
Match: Pregame matchup card → Play → Halftime summary → Final → Rewards (coins tick up) → back to HUB
```
- One pixel bitmap font (original, or an open-licensed pixel font like "m5x7"/"Press Start"-style, OFL), 9-slice pixel panels and buttons in a shared `Theme` resource, 4-color UI accent palette + team colors.
- Big touch targets (≥ 44 px on the 480×270 canvas ≈ 9+ mm), thumb-reachable, and a left-handed mirror option.
- Minimal effects: screen shake on big hits, pixel flash on TD, card-flip tweens. No particles beyond simple confetti.

---

## 8. Art pipeline
**Approach:** original sprites, "chunky" style, minimal work via **palette swap**.
1. **Player template sheet**, 16×24 px frames, facing right (left = `flip_h`). Animations: idle(2), run(4), backpedal(4), throw(3), catch(2), block(2), dive/tackle(3), fall(2), celebrate(2). About 24 frames total.
2. **Color-key convention:** draw with 6 reserved key colors (pure R/G/B-ish values) = jersey primary, jersey secondary, helmet, pants, skin, outline. `palette_swap.gdshader` maps keys → team colors + a per-player skin tone at runtime. One sheet serves all 32 teams.
3. **Phase 1 placeholders:** `tools/gen_placeholder_sprites.py` (Python + Pillow) programmatically generates the template sheet (blocky helmeted figures), ball, field tiles, 16×16 badges, and card frames. Everything is usable immediately.
4. **Refinement:** open the generated PNG in **Pixelorama** (free, built with Godot) or Aseprite, redraw frames in place (same grid = no code changes), and export PNG. Optionally use the "Aseprite Wizard" plugin to import tags as `SpriteFrames` automatically.
5. **Import settings:** Filter = Nearest, Mipmaps off, Compress = Lossless. `AnimatedSprite2D` + `SpriteFrames.tres` per template.
6. **Field:** tile the turf with a 2-tone stripe every 5 yards, end zones filled with team colors, and yard numbers from the pixel font. Cards and badges are generated from `teams.json` colors at runtime or through the script.

---

## 9. Phased roadmap

### Phase 0: Setup (½–1 day)
- **Goals:** tooling works end-to-end on a real phone before any gameplay.
- **Tasks:** install Godot 4.x stable + export templates. Create the project with the settings in §2 and the folder skeleton. `git init` + Godot `.gitignore`. Install GUT. Android: install JDK 17 + Android SDK (via Android Studio), configure Editor Settings, and create a debug keystore. Export a "hello field" scene and run it via USB (one-click deploy). iOS is deferred until a Mac is available (the code has no platform-specific parts).
- **Test:** the app launches on your Android phone in landscape, and a tap draws a pixel dot where you touched. GUT runs one dummy test.

### Phase 1: One playable offensive drive (placeholder art)
- **Goals:** the core offense *feel*: snap, drop back, aim, throw, catch, run, get tackled, move the chains, score.
- **Tasks:** `FieldProjection`, `FieldView`, `CameraRig`. `PlayerAgent` kinematics + placeholder sprites (generator script). `Ball` 3D arc + shadow. `TouchInput` (aim drag, steer, flick juke, double-tap dive). `PlayRunner` with 2 formations and ~6 offensive plays (`PlayDef` routes). Basic defenders: simple man/zone + pursuit (no user control yet). `ContactResolver` (tackle, catch, incomplete). `DownTracker` + LOS/first-down markers. Result banners, touchdown detection. Tuning resource with hardcoded default ratings. `drive_sandbox.tscn` that starts at your own 25. Create the full sample `roster.csv` + `teams.json` (not wired yet).
- **Test:** on device, complete a drive to a TD in the sandbox. Checklist: aim arc matches the landing spot, lob vs bullet feel is distinct, steering has no jitter, juke works, a 4th-down failure ends the drive. Unit tests: `DownTracker` (first downs, turnover on downs, TD at goal line, safety), ball arc landing math. Tune until a friend can score within 3 tries without instructions.

### Phase 2: Defense playable
- **Goals:** a fun, fast defensive possession.
- **Tasks:** defensive FormationDefs + ~8 defensive plays. `DefenseSwitcher` (auto + tap). Human defender control (drag, dive tackle, jump/swat). CPU offense: `AIPlayCaller` (basic tables), `qb_read_logic`, CPU runner. Deflections, INTs (with returns: the user steers the returner), fumbles (simple). Brain debug overlay (routes, zones, openness scores, controlled-defender ring) toggled with a 3-finger tap or F1.
- **Test:** `drive_sandbox` in "defend" mode: the CPU drives from its 25. Checklist: you can make a tackle within 2s of taking control, INTs happen sometimes (~1 per 30 passes), the CPU completes ~60–70% of passes on Pro, and the switcher never gives you a defender behind the play. Debug overlay confirms AI reads.

### Phase 3: Full game
- **Goals:** a complete 4-quarter match vs AI.
- **Tasks:** `MatchController` state machine, `GameClock` (quarters, runoff, timeouts, two-minute warning, halftime), possession changes, auto kickoffs/punts, FG/PAT timing meter, 2-pt tries, overtime, HUD scorebug, pause menu, final screen, "Defense Pace" setting. `ai_vs_ai.tscn` headless mode (both sides AI, 4× speed) for stats.
- **Test:** play full games on device (~10–15 min). GUT: `GameClock` runoff/stoppage rules, scoring, OT. Headless: 200 AI-vs-AI games between equal teams produce plausible averages (≈ 20–28 pts/team, 55–70% completion, ~1 INT/team, no stuck plays/infinite loops; watchdog ends any play > 15s).

### Phase 4: Roster import & cards affect gameplay
- **Goals:** real players on the field, and ratings visibly matter.
- **Tasks:** `GameData` CSV/JSON loader with validation + position defaults. `CardDef` generation (tiers). `RatingModel` fully wired to all attributes (§4 table). Lineups → agents (names/numbers on HUD when controlled). Team badges + palette-swap shader for team colors. First-run "Pick Your Team" → starter cards. Basic lineup screen + team OVR. `tools/validate_roster.gd` EditorScript, plus optional `derive_ratings.py`.
- **Test:** GUT: roster import (row count, defaults fill, bad rows reported not crashing), card OVR math, team OVR. Headless A/B: an Elite-level team vs Bronze-level beats it ~85%+, with QB `tha` 95 vs 65 showing a clear completion-% gap. Manual: edit one player's `spd` in the CSV → he's visibly faster next launch.

### Phase 5: Packs, economy, collection
- **Goals:** the ultimate-team loop works end-to-end.
- **Tasks:** `SaveManager` (atomic, versioned, autosave), `Economy`, `PackDef`s, store screen, pack-opening scene, collection screen with filters, quick-sell, duplicate training, sets, postgame rewards screen, auto-best lineup.
- **Test:** GUT: pack odds over 100k simulated opens are within ±0.5% of config, guarantees hold, save round-trip is identical, a corrupted save falls back to `.bak`, and v0→v1 migration works. A progression sim script plays out the economy for 100 simulated games (win rate from difficulty) and checks the OVR-by-games curve against the §5 targets. Manual: kill the app mid-pack-opening → no lost coins or duplicated cards.

### Phase 6: Season, challenges, polish
- **Goals:** long-term loop + feel.
- **Tasks:** season mode (schedule, `sim_engine`, standings, playoffs, Super Bowl reward), challenge system + ~20 challenges + daily challenge, Franchise Chemistry, difficulty tiers UI, sound effects/music (e.g. jsfxr/sfxr-generated chiptune SFX), juice (hit shake, TD flash, crowd noise), settings screen, tutorial overlays (first drive/first defense), optional mid-match resume, iOS export on a Mac, performance pass (60 fps on a mid-range phone).
- **Test:** complete a short 8-game season + playoffs. GUT: sim_engine standings/tiebreak sanity, schedule generation. Every challenge has a deterministic start state and is winnable (verify each manually once). A 2-week "play daily" self-test checks whether progression still feels good, then tune `economy_config.tres`.

---

## 10. Technical risks & mitigations
| Risk | Mitigation |
|---|---|
| **Touch feel** (aim precision, drag vs tap confusion, fat fingers) | Test on device from Phase 1. Tap/drag thresholds (≥ 12 px move = drag, < 200 ms = tap) and all sensitivities live in the tuning resource + settings. The aim arc is always visible. Slight aim assist snaps toward an open receiver within a small cone (tunable, can be disabled). |
| **Defense feels like a chore** | Auto-switch, short CPU plays, Defense Pace setting, generous tackle radius on dive, satisfying hit/INT feedback |
| **AI quality** (dumb or unbeatable) | Simple rule-based brains + debug overlay. Difficulty via reaction/read multipliers, not cheating. AI-vs-AI headless stats to catch degenerate plays. Watchdog for stuck plays. |
| **Balancing ratings & economy** | All numbers in `.tres` tuning files. Headless AI-vs-AI A/B tests for ratings, and a progression simulator for economy. Soft-probability contact model avoids cliffs. |
| **Scope creep** | Strict phase gates. 9v9 with simplified linemen, and 7v7 fallback is a data change. Special teams mostly automated. No online, no mid-match saves in v1. |
| **9v9 readability on a small screen** | Compressed vertical projection, controlled-player ring, 480×270 canvas with integer scale. If cluttered after Phase 2, switch to 7v7 formations. |
| **iOS build** | Needs a Mac + Xcode (a free Apple ID's sideloads expire every 7 days). Keep code platform-agnostic and do iOS in Phase 6. |
| **Save corruption** | Atomic temp-rename write, `.bak`, versioned migrations, ids-only references |
| **Roster edits breaking saves** | Stable `id` column, "Retired" fallback card, validator tool |
| **Godot CSV import gotcha** | Set roster.csv to "Keep File". There's a unit test that the loader finds it in an exported build. |
| **GDScript performance** | 18 agents + distance checks is trivial. Use static typing everywhere (faster + catches bugs), and avoid per-frame allocations in brains. |
| **Legal (personal use)** | Real names + team colors only, no logos, original art, never distributed |

---

## 11. Verification (overall)
- **Unit tests (GUT, headless):** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit` for rules, ratings, odds, economy, save, and roster import. Run before every commit.
- **Sandbox scenes:** `drive_sandbox.tscn` (offense/defense single drive, debug overlay) and `ai_vs_ai.tscn` (batch stats printed to console/CSV).
- **Device playtests** at the end of every phase using the per-phase checklists above. Android one-click deploy, iOS in Phase 6.
- **Phase gate:** don't start the next phase until the current phase's "Test" list passes on a real phone.
