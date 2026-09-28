# Playtest round 2 — art, ball marker, pass protection (2026-09-28)

Feedback: (1) players/helmets don't feel like Retro Bowl, (2) it's not obvious who has the ball,
(3) the QB is sacked before receivers (e.g. JSN on a post) can break.

## 1. Player sprites
Problem: the 28x26 template has an oversized helmet (10x7 vs an 11x7 torso), a stubby body and
little leg, so the figure reads as a "bobblehead" rather than an athlete.
Fix (`tools/gen_player_sprites.gd`, key colors/frames unchanged so the shader and anims still work):
- Smaller helmet (8x6) with a crown stripe, shine and a clear facemask edge.
- Taller torso (7 rows) with square shoulder pads and a tapered waist; head overlaps the pads (no neck).
- Legs stay 6 px, so the figure is ~20 px tall with a body-to-head ratio closer to Retro Bowl.
Verify: regenerate, `--write-movie` screenshot, compare crop.

## 2. Ball carrier marker (Madden style)
Problem: only a small bobbing arrow over the head, easy to lose in a pile.
Fix (`PlayerAgent._draw`, `PlayRunner._update_markers`):
- Pulsing ground ring + soft fill under the carrier's feet (yellow = yours, red = theirs), drawn
  in the field plane (squashed ellipse), plus two small tick marks so it reads as a target.
- Shown for whoever holds the ball, including the QB before the snap and during the drop-back.
- The overhead arrow is removed (less clutter).

## 3. Pass protection
Measured (throwaway probe, never throwing, 92 OVR offense vs 88 OVR defense, all 15 pass plays x
10 defensive calls x 3 seeds): median time-to-sack 3.0 s, fastest 1.05 s, 25th percentile 1.7 s.
A post breaks at ~1.5-2 s and a deep throw needs 1 s more, so the human rarely gets a window.
Causes: (a) blocks are shed on the same 1.9 s clock as run blocks; (b) after a shed, the blocker
is locked out 0.6 s and the rusher 0.8 s, so a beaten rusher has a free run at the QB.
Fix (`GameplayTuning` "Contact", `ContactResolver`):
- `pass_shed_mult`: pass-pro blocks hold longer (applies while the QB still has the ball).
- `pass_reblock_cd` / `pass_rusher_cd`: quick re-engage so a shed rusher is picked up again.
- Blitzes (extra rushers) still get home sooner because there are more rushers than blockers.
Target: median time-to-sack >= 4.5 s, blitz 25th percentile >= 3 s, and the CPU-vs-CPU sim
still sacks ~4-6% of dropbacks (the CPU QB throws on time, so it barely notices).
The probe stays in the sim as `SACKS n, avg time to sack` output.
