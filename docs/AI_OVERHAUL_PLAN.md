# AI overhaul — make the players think

Owner (2026-10-04): "a full and very in-depth AI overhaul that makes it feel actually smart. When I play
WR the QB constantly throws picks. Make it feel like actual intelligent people."

## Where it stands (AI lab, `tests/lab/lab_ai.gd`, 300 plays each, 78 offense vs 84 defense)

| | before | real-football target |
|---|---|---|
| CPU QB completion | 47 % | 62–68 % |
| INT per attempt | 5.0 % | ≤ 2.5 % (picks come from bad reads under pressure / tipped balls) |
| time to throw | 1.3 s (throws at the first flicker) | 2.2–2.8 s, quicker vs the blitz |
| separation at the throw | 2.6 yd | ≥ 3.5 yd |
| sacks per dropback | ~1 % | 5–7 % |
| throwaways | ~0 | a few per game when nothing is there |
| run game | 2.1–3.9 ypc, 16–22 % stuffed, 0–4 % explosive | 4.0–4.6 ypc, ~18 % stuffed, ~10 % 12+ yd |
| RTG receiver | QB forces it to you (80–90 % of targets) | ~35–50 % when you're open; almost never into a crowd |

What is dumb today: the QB evaluates one receiver per tick by a single "separation at the catch point"
number with random noise and throws the moment it crosses a threshold; it never asks "can a defender get
to this ball first", never waits for a route to break, never reads the coverage, never checks down on
purpose, never throws it away when it should. A human-run receiver is predicted as if he'll keep his
current velocity, so a cut after the release sends the ball to the defender. Zone defenders don't read
the QB's eyes; pursuit all aims at one spot; the ball carrier's vision ignores his blockers.

## The plan

### 1. Quarterback brain (`QbMind`, replaces CpuPasser's insides; same API)
- **Pre-snap read** (awareness-limited, noisy): coverage shell from the safeties' depth (one-high / two-high)
  and the corners' cushion/press, blitz count vs. blockers → a *hot* read when the rush outnumbers the
  protection.
- **Progression built from the concept**: each route gets a "ready" moment (its break, or its depth for
  verticals); the QB reads them in order (deep → intermediate → checkdown on shot plays, quick → mid →
  checkdown otherwise), moving his eyes at a rate set by awareness. He only throws to a receiver whose route
  is ready (anticipation throws for 85+ awareness: up to ~0.3 s early).
- **Throw evaluation = a real risk model** (`ThrowRisk`, pure): for the best of a few candidate spots
  (lead, a step shorter, back-shoulder / away from the nearest defender) plan the actual flight, then for
  every defender compute how early he can get to (a) the catch point and (b) any point under the flight path
  low enough to reach (reaction + angle + closing speed), versus the ball. → P(complete), P(INT), expected
  yards (air + likely YAC from the space around the catch point). Expected value = P(comp)·yards −
  P(INT)·INT cost.
- **Decision**: throw when the value clears a bar that drops as the clock in his head runs and as pressure
  builds, *never* above a max INT risk set by his awareness and the game situation (a smart QB ~3 %,
  desperate late-game QB more). Under pressure with nothing there: check down if safe, else throw it away
  out of bounds, else scramble if he has the legs and a lane, else take the sack. Accuracy (THA/pressure)
  is part of the risk: a shaky arm wants a bigger window.
- **Pocket**: climb when the edge rush gets deep, slide away from the closest pressure, reset feet.
- **Road to Glory receiver**: the QB throws to where *you* are going only if you are moving consistently; a
  freelancing human gets a stricter window (less predictable). CALL makes him look at you first and
  accept a slightly tighter window, but never a throw into a crowd.

### 2. Coverage
- **Zone**: real landmarks (deep zones keep depth and stay over the top: "nobody behind me"), match a
  receiver who enters the zone and pass him off when he leaves, sink under verticals, and **read the
  QB's eyes** after their reaction time (so staring down a receiver draws a defender — smart QBs look
  defenders off).
- **Man**: hip-flip and trail as now, but play the receiver's hands at the catch point instead of
  flying at the landing spot; safeties in Cover 1 rob the deepest threat.
- **Break on the ball**: go to the earliest point on the flight they can reach (undercut) if it's real,
  else to the receiver to tackle — no more defenders running to empty landing spots.

### 3. Run game
- **Ball carrier vision**: lanes are scored by the defenders *and his blockers* (follow the block, run
  off the blocker's hip), press the hole, one cut, then get downhill; bounce only when the edge is
  clearly open; protect the ball when wrapped.
- **Blocking**: combo the nose and climb to a linebacker; backside cut-off; lead blockers kick out the
  first defender to show.
- **Pursuit**: real intercept angles, staggered (no five defenders aiming at one point), outside
  defenders keep contain and force the carrier back inside.

### 4. Receivers (CPU)
- Option routes: settle in the open window vs. zone, keep running vs. man.
- Scramble drill: when the QB breaks the pocket, receivers work back toward him / to open grass.
- Back to the ball on underthrows (already), fight for position at the catch point.

### 5. Play calling
- Offense game plan: lean on what works (yards per call by concept), avoid what got stuffed, situational
  (2-minute: sideline routes and spikes the clock; backed up: safe calls; red zone: fades/slants).
- Defense: unchanged learning (DefenseMemory) plus more pressure on 3rd and long vs. bad QBs.

## How it's measured
`tests/lab/lab_ai.gd` (not in the unit suite, run by hand) with scenarios cpu / wr_bot / wr_wild /
wr_idle / runs, ratings via `LAB_OFF`, `LAB_DEF`, `LAB_ROOKIE`. Every change is checked against the
targets above; unit tests lock the key behaviours (no throws into a defender's lane, throwaways under
pressure, hot reads vs. the blitz, the INT rate in a batch, ypc range).

## Result (2026-10-04, lab 300 plays)
CPU QB 72 % comp, 1.3 % INT, deep (20+ air) 43 % comp, ttt 2.0 s, sep 3.3 yd, throwaways ~8 %; RTG WR (bot runs
the drawn route) targeted 51 % of throws, 85 % caught, 1 INT in 297. Run game 3.3–4.7 ypc depending on ratings.
Still to do: §4 option routes + scramble drill, §5 offense game plan, pocket climbing.
