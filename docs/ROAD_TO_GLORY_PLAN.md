# Road to Glory — design & build plan

Owner ask (2026-10-02): "a Road To Glory mode where you get drafted to a team and play as a
single player (QB, RB, WR, CB). Full controls and movement revamp for this mode only: RBs
get real movement control and juke moves, CBs get full control to track a WR and pick the
ball. Plan every nook and cranny."

This is a career mode on top of the existing match engine. Ultimate Team, Season and
Challenges are unchanged (their controls stay exactly as they are).

---------------------------------------------------------------------------------------
## 1. The player's journey

1. **Create** (MODE SELECT -> ROAD TO GLORY):
   - Position: QB / RB / WR / CB (big cards, one line on how each plays).
   - Archetype (3 per position, sets the starting attribute shape and potential):
     - QB: GUNSLINGER (arm), FIELD GENERAL (accuracy/awareness), SCRAMBLER (legs)
     - RB: POWER BACK (str/carrying), ELUSIVE BACK (elusiveness/accel), RECEIVING BACK (hands/routes)
     - WR: DEEP THREAT (speed), ROUTE RUNNER (route/accel), POSSESSION (hands/strength)
     - CB: LOCKDOWN (man coverage/speed), BALLHAWK (hands/awareness), HARD HITTER (tackle/str)
   - Name (random generator + edit), jersey number (position-legal range), look (skin tone,
     hair, beard, visor) previewed on the in-game sprite.
   - Starting OVR ~62-66 depending on archetype; age 21.
2. **Combine** (optional, 3 reps in the real engine, doubles as the controls tutorial):
   - RB: 3 carries vs a live defense; WR: 3 one-on-one routes vs a corner; CB: 3 one-on-one
     coverage snaps; QB: 3 throws vs coverage. Each rep graded; the combine grade moves
     your draft stock. SKIP = average grade.
3. **Draft day**: picks tick by on a board ("ROUND 1, PICK 14 ..."), then the card flips:
   "WITH THE 23RD PICK, THE CHIEFS SELECT ...". Draft round from combine grade + archetype
   + luck; the team from need (weakest real starter at your position) + luck.
4. **Seasons** (Settings.season_games weeks + playoffs, same league model as Season mode):
   - RTG hub: your player card (OVR, archetype, dev trait), XP + UPGRADE, coach trust bar,
     next opponents strip, season stat line, goals, standings, awards shelf.
   - PLAY (real game, you only play your side of the ball; the other side is simulated
     drive-by-drive like the existing Retro Bowl route) or SIM (a stat line around a C+
     game, less XP: playing is always better).
   - After every game: grade screen (letter grade with a stamp, your line, XP, trust).
5. **Offseason**: awards ceremony (Rookie of the Year, Pro Bowl, All-Pro, OPOY/DPOY, MVP,
   Super Bowl ring), age +1, development (aging curve), contract: rookie deal 3 years, then
   offers from 3 teams + your team (stay or sign elsewhere).
6. **Retirement**: allowed after season 3 or from age 30, forced at 37 or if OVR < 60.
   Legacy score -> HALL OF FAME at a threshold. Retired players are kept as LEGENDS.
7. **Ultimate Team tie-in**: every finished season adds/updates a locked card of your RTG
   player in your UT collection (program "rtg", OVR = his current OVR, capped 99, can't be
   sold). Coins from RTG games go to the shared wallet (smaller than UT games).

---------------------------------------------------------------------------------------
## 2. Controls revamp (Road to Glory only)

Two thumbs, landscape. **Left half = floating joystick** (appears where the thumb lands;
ghost base shown when idle). **Right side = context buttons** (big round, labelled, with
cooldown rings). `Settings.left_handed` mirrors the layout. Multi-touch: the pad tracks
each finger by index, so you can run and press buttons at the same time.

Movement feel (all skill players):
- Analog: stick length = throttle, direction = 360 degrees (field y compressed like the
  screen). Full stick = full speed for your rating.
- Responsive accel (rtg_accel_mult) and **plant-and-cut**: a turn sharper than ~70 degrees
  at speed snaps the velocity to the new direction keeping a share of speed from agility
  (RB elu/acc, WR rte/acc, CB cov/acc). Cooldown so it can't be spammed.
- **BURST** button: short speed surge (+12 %, ~0.9 s) with cooldown, ring shows readiness.
- Let go of the stick: the ball carrier keeps running his heading; a WR who took over his
  route keeps striding; a CB hands back to his coverage AI (assist).

Ball carrier (RB, WR after the catch, QB scramble, CB on a pick):
- **JUKE**: quick lateral hop (side = stick, else away from the nearest defender).
  Defenders close by and in front "bite" (lose their read for a moment, more if your ELU
  beats their AWR) and the tackle chance during the juke is reduced.
- **SPIN**: ~0.45 s spin, slower but the first tackle attempt during it is much likelier
  to slide off (ELU + STR vs TAK).
- **POWER**: auto stiff arm (defender to the side/front-side) or truck (head-on):
  STR vs TAK decides; trucking costs speed. Big moments pop text ("TRUCKED!").
- **DIVE**: lunge forward for the extra yard (existing dive).
- Moves share a short global cooldown; each has its own cooldown ring.

WR before the catch:
- Auto-runs the called route until you touch the stick (route shown in gold pre-snap).
- **HOT ROUTE** pre-snap: cycle PLAY ROUTE / GO / SLANT / OUT / CURL / POST.
- **CALL** (hand up): the QB looks your way next (more likely the more he trusts you, and
  only if you're open-ish).
- **CATCH** timing: tap as the ball arrives (window ~0.35 s) for an aggressive high-point
  catch: bigger catch radius and a contested-catch bonus. No tap = normal catch.
- The QB's read uses your actual movement (not the drawn route) once you go off-script.

CB:
- Full control from the snap (and pre-snap: shade your alignment with the stick; line up
  within ~2 yds of your man to press).
- **JAM** (first ~0.6 s, when pressing): timing-based jam, slows the release more.
- **Read telegraph**: when your man is about to break, a small arrow flashes at his hips —
  earlier the better your AWR is vs his RTE. This is what makes coverage playable by thumb.
- Release the stick: the coverage AI takes him (you can hand off and take back any time).
- Ball in the air: landing marker + timing ring; **PLAY BALL** = leap (swat/pick decided by
  timing and position; too far = sprint to the spot). **TACKLE** (dive) near the carrier.

QB:
- Right thumb keeps the existing slingshot aim / pass type tap / drag-back snap (unchanged,
  well tuned). Left stick now moves the QB in the pocket (step up, slide, roll out);
  crossing the line = scramble and the carrier buttons appear.

HUD extras in RTG: "YOU" pill over your player, an edge arrow when he's off screen, a burst
meter, per-play grade pop ("A  GREAT ROUTE"), your running stat line on the bottom strip.

---------------------------------------------------------------------------------------
## 3. Match rules in RTG

- Your team = real roster with you injected at your slot (QB, RB, WR1, CB1). Opponents use
  their real rosters, scaled by difficulty (ROOKIE -6, PRO 0, ALL-PRO +3, LEGEND +6 OVR).
- You play your side of the ball only. The other side is simulated drive-by-drive
  (`GameSim.sim_drive`, already used by the Retro Bowl route) — for a CB that means your
  offense's drives are simulated.
- Play calls:
  - QB: you call (4-play bar + MORE, as now).
  - RB/WR: the offensive coordinator calls (PlayAdvisor + a share that features you,
    growing with trust). Pre-snap card: call name, YOUR JOB, AUDIBLE (2-4 per game by
    trust: pick from 3 calls that feature you), HOT ROUTE (WR), SNAP.
  - CB: the defensive coordinator calls; card shows your assignment ("MAN: #18 J. CHASE,
    PRESS" / "ZONE: DEEP THIRD"); READY -> the CPU offense snaps.
- CPU coach handles 4th downs, PATs/2-pt and timeouts for your team when you're not QB.
- The CPU QB targets an RTG WR more (favor scales with trust) and the CPU offense tests an
  RTG corner (reads his man first).
- Pause -> LEAVE = sim the rest of the game (your line so far + a simmed remainder).

---------------------------------------------------------------------------------------
## 4. Grades, XP, trust, progression

- Per-play grade points (position specific), e.g. WR: catch by yards/YAC, drop = F,
  target when open; RB: yards (0 or less bad, 5+ good, 10+ great), broken tackles,
  fumbles; CB: incompletion on your man A, catch allowed by yards, TD allowed F, INT A+,
  PBU A, tackle B; QB: completion by yards, TD A+, INT F, sack D, scramble yards.
- Game grade (A+ .. F) = average of play grades + stat bonuses.
- XP per game: base + grade + stats + win; SIM gives ~45 %.
- Upgrades: spend XP on +1 to a position attribute; cost rises with the attribute
  (30 + 6 per point over 60). Caps: potential from archetype + dev trait.
- Dev trait: NORMAL -> STAR -> SUPERSTAR -> X-FACTOR, raised by awards and great seasons;
  multiplies XP.
- OVR from position weights of attributes (RtgRules.ovr).
- Trust 0..100: moved by game grades; drives target/carry share, audibles, and offers.
- Aging: +1 per season; from 30 a decline roll each offseason (speed first).
- Season goals: 3 per season, position specific, scaled to the season length (XP + coins).
- Awards from per-game rates and team record; legacy points per award/ring/stat milestone.

---------------------------------------------------------------------------------------
## 5. Build order

1. Engine: locked-player mode in PlayRunner, RtgControl (+ RtgPad on screen), move set in
   PlayerAgent + RatingModel + ContactResolver, plant-and-cut, burst, CPU-QB favor,
   CB telegraph, catch timing, camera follow, result fields (target/cover/catch spot).
   Sandbox flag `--rtg=WR` for fast iteration; GUT tests.
2. Match: MatchController RTG config (roster injection, side-only, coach calls, pre-snap
   card, audible/hot route, CPU 4th downs/PATs, sim of your team's drives), RtgTracker
   stats + per-play grades, HUD, results payload.
3. Career: RtgRules (archetypes, OVR, XP, upgrades, draft, goals, awards, aging,
   contracts, retirement, legacy), Profile.rtg, screens (create, combine, draft, hub,
   upgrade, postgame, offseason/awards, retirement/legends).
4. UT tie-in (RTG card), docs, balance pass (headless RTG games), screenshots, ship.

Debug: `-- --rtg=RB|WR|CB|QB` (sandbox one drive), `--demo-profile --screen=rtg_hub`,
`--screen=rtg_create`, `--screen=rtg_draft`, `--rtg-game=WR` (straight into an RTG match).
