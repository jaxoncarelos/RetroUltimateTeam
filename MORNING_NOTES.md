# Morning notes — overnight session 2026-09-28

All ten items in `docs/OVERNIGHT_TASKS.md` are done and pushed to `main`, one commit per
item (items 2–4 share a commit). CI is green on every push. There are 142 GUT tests, plus
the drive-sim and CPU-vs-CPU smoke runs in `tools/run_tests.sh`.

**Before your first launch:** the game now opens on **Pick Your NFL Team** and then the
**hub**, not the drive sandbox. To jump straight into a game, use `-- --quick`. To reach
the old sandbox, use `-- --sandbox`.

## What changed, and how to try each part

| # | Feature | Try it |
|---|---|---|
| 1 | **Defensive adaptation.** The CPU defense tracks your calls (play, formation, category, yards) with decay. It picks counter-calls, and when you repeat a play it gets *keyed*: defenders react faster, zones slide onto that play's route points, man defenders jump the break, and blitzes get home faster against runs. The HUD shows **DEFENSE IS KEYING ON …** and a red "!" marks that play's card. | Call the same play 3 times. Headless: `--sim=1000 --smart` vs `--sim=1000 --spam=mesh` |
| 2 | **Bigger playbook.** 18 offensive plays across 5 formations (QB sneak, dive, GL power, draw, counter, toss, sweep, screen, slants, mesh, smash, curl-flat, four verts, post-wheel, flood, PA cross, deep shot, fade) and 10 defensive calls (cover 0–4, press, zone blitz, LB blitz, prevent, goal line). Adds press jams, play-action bites, delayed draws and pitches. | **MORE** on the play bar |
| 3 | **Situational suggestions.** `PlayAdvisor` preselects the best call with a **BEST** tag. The bar shows the top 4, and **MORE** opens the full grid. | 3rd & 1 suggests a sneak or dive; 3rd & long suggests a deep pass |
| 4 | **Retro Bowl-style snap.** Press on the QB and the ball is snapped. Keep dragging in the same gesture: **back** aims, **forward** scrambles. On runs the same touch steers after the handoff. A tap still snaps. A pulsing ring plus chevrons on the QB is the hint. | Any pass play |
| 5 | **Field detail.** Textured turf with mow stripes, animated crowds in both teams' colors, benches and sideline players, a midfield shield emblem, goalposts, pylons, yard-number arrows, and a chain crew with a down box. All of it is drawn in code. | Run near a sideline. `-- --look=35,5` pins the camera |
| 6 | **Playable defense.** Auto-switching to the most relevant defender, and tapping a defender takes him (the pick holds for 1.5 s). **Drag** moves your man. **Tap the carrier** to dive. **Tap the landing marker** to leap; timing decides swat or pick, and from far away the tap sprints you there. You steer INT returns. Also adds pick-sixes, simple fumbles, Defense Pace (every snap / key downs / highlights) and an AI debug overlay (**F1** or a three-finger tap). | Any CPU possession, or `-- --sandbox --defend` |
| 7 | **Full game.** Kickoffs, punts, FG/PAT timing meter, extra point or 2-pt choice, quarters, two-minute warning, halftime, overtime, timeouts, a pause menu and a final screen. The CPU makes its own 4th-down and 2-pt decisions and uses timeouts. | Hub → **QUICK MATCH**. Demo: `-- --watch` |
| 8 | **Roster and cards.** Team picker. You start with your team's real players as cards (top 5 Silver, the rest Bronze), and your lineup's ratings drive the players on the field. CPU opponents are real teams rescaled to the difficulty. The HUD shows the name and number of the player you control. | First launch, or `-- --reset-save` |
| 9 | **Packs and economy.** Store (Bronze, Silver, Gold, Elite), pack opening (flip cards, flashes for Gold and Elite), collection (filters; quick-sell, train with a duplicate, lock), lineup (tap a slot, or AUTO-BEST), sets, postgame coin rewards. Saves are atomic, keep a `.bak`, and are versioned. | Hub |
| 10 | **Season and challenges.** 8- or 17-game season with the other games simulated, standings, 7-team-per-conference playoffs and a Super Bowl (champion gets an Elite pack). 11 challenges plus a daily one. Settings screen, Franchise Chemistry, screen shake and flashes, synthesized chiptune sound effects, and coach tips in your first game. | Hub → SEASON / CHALLENGES / SETTINGS |

Debug commands (also in the README):
```
godot --path . -- --quick                          # straight into KC vs PHI
godot --path . -- --watch                          # CPU vs CPU full game
godot --headless --path . -- --ai-vs-ai=40         # batch full games, league averages (~3 min)
godot --headless --path . -- --ai-vs-ai=20 --home-ovr=88 --away-ovr=64   # ratings A/B
godot --headless --path . -- --sim=1000 --smart    # sandbox drive sim; --spam=ID, --nokey, --by-play
godot --path . -- --demo-profile --screen=store    # meta screens with a throwaway KC career
godot --path . -- --reset-save                     # start a new career
```

## Balance, measured headless

- **Full game** (40 CPU-vs-CPU games, equal generic teams): 22.6 pts/team, 58% completions,
  0.88 INT/team, 0 stuck plays. With the real KC and PHI rosters it runs hotter: about 29
  pts/team and 71% completions.
- **Ratings matter:** an 88-OVR team beat a 64-OVR team in 20 of 20 games.
- **Repeating plays stops working** (sandbox drive sim, points per drive). Situational
  mixing scored 3.0. Spamming one play scored lower every time: mesh 2.6, pa_cross 2.6,
  four_verts 2.1, slants 1.9, curls 1.8, smash 0.7, sweep 0.1, dive 0.0.
- **Card progression** (economy sim, 55% win rate): team OVR goes from 65 at the start to
  73 after 20 games, 80 after 45 and 83 after 100. That is a little behind PLAN §5's curve
  late on.

## Decisions I made for you

1. **The game clock runs in NFL time.** It shows 15:00 quarters but runs about 6× fast while
   the ball is live, so a quarter takes roughly *Quarter length* (2:30 by default) of
   play. The runoff between plays is 32 NFL seconds. PLAN's literal "2:30 clock + 25 s
   runoff" only allowed about 20 plays per game.
2. **Keying thresholds.** Calling a play twice within about 4–5 calls, or one gain of 15+
   yards, keys the defense. A 4-play rotation still gets partly keyed; a 6-play rotation
   doesn't. All the numbers are in `data/tuning/defense_ai_tuning.tres`.
3. **The drive sim changed.** It now steps at a fixed 60 Hz instead of 4× time scale. The old
   coarse steps were distorting results; the true 60 Hz baseline was far too easy for the
   offense, which is why so much tuning landed tonight.
4. **Ball carriers follow the designed lane** until you steer, both the human auto-run and
   the CPU runner.
5. **Rosters.** I added 4–6 well-known players for each of the 28 teams that had none,
   from memory of the 2025 season. Positions no real player covers are filled with
   generated depth players, visibly named "KC OL3" and Bronze-only. **Please verify the
   names, teams and jersey numbers** in `data/roster.csv`; mid-season trades may be wrong.
6. **Economy.** Match coins went up to 400 for a win, 160 for a loss and 240 for a tie (PLAN
   said 300/120/180) so progression tracks PLAN's curve more closely. Generated depth players
   never appear in packs.
7. **Opponents and home field.** You always receive the opening kick. Quick-match opponents
   are random. Your team is treated as home in season games (the home/away label only
   matters to the score model).
8. **Overtime.** Each team gets one possession, then it's sudden death. If the 10:00 OT
   clock runs out, the game is a tie.

## Known issues and rough edges

- **The run game is still the weakest part.** Runs average about 3–4 ypc in the full game but
  only 2–3 in the sandbox. Draws lose to man coverage and blitzes, and keyed runs are harsh.
- **INTs are too frequent in the sandbox** (about 5% of passes); the full game is fine.
- **Touch targets:** some meta-screen rows (lineup slots, filters) are 20–22 px tall, below
  PLAN's 44 px guideline. They are fine with a mouse; check them on a phone.
- **The stands are only visible near the sidelines**, because the camera follows the ball
  and the field is taller than the screen.
- **Pausing during a live play** freezes the play, but result banners already on screen
  keep timing out.
- **Not done:** left-handed mode (the setting exists but does nothing), music, iOS export,
  and an on-device performance pass. I had no phone overnight, so nothing has been checked
  on a device. The APK export settings are unchanged.
- Kick meter, PAT choice and the tutorial were exercised by tests and screenshots but
  never by a human.
- Coach tips are shown in order the first time each situation comes up. Replay them from
  Settings.

## Suggested next steps

1. **Playtest on your phone**, especially the snap gesture, defensive taps and leap timing,
   and the kick meter. Tell me what feels off; every constant lives in
   `data/tuning/gameplay_tuning.tres` or `defense_ai_tuning.tres`.
2. **Run-game pass:** second-level blocking, cutback lanes for the CPU runner, and a
   stiff-arm move.
3. **Verify and expand `roster.csv`**, ideally full real rosters so fewer generated players
   remain.
4. **UI polish:** bigger touch targets on meta screens, a pregame matchup card, and a
   postgame box-score screen.
5. **Refine the art:** redraw `art/players/player_template.png` (same grid and key colors)
   and add a real title screen.
6. **PLAN leftovers:** music, left-handed mode, mid-match resume, iOS export.
