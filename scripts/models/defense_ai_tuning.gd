class_name DefenseAITuning
extends Resource
## Constants for the CPU defense's play calling and "keying" on the offense's tendencies.

@export_group("Memory")
@export var decay := 0.75              ## heat kept per later call (older calls fade)
@export var heat_per_call := 1.0
@export var big_gain_yards := 15       ## a gain this big makes the defense key on the play at once
@export var big_gain_heat := 0.55
@export var stuffed_relief := 0.35     ## heat removed when the play gained nothing
@export var key_threshold := 1.3       ## play heat needed to be "keyed" (≈ 2 calls in the last 5)
@export var key_full := 2.4            ## play heat for a full key (level 1.0)
@export var formation_key_weight := 0.3 ## share of formation heat that counts toward the key
@export var category_key_weight := 0.25
@export var formation_key_threshold := 2.6
@export var category_key_threshold := 2.6

@export_group("Play calling")
@export var counter_weight := 2.6      ## extra weight per unit of category share a call counters
@export var keyed_counter_bonus := 2.0 ## extra weight for calls that counter the keyed play's category
@export var confidence_heat := 2.5     ## total heat before tendencies fully count
@export var repeat_call_penalty := 0.6 ## CPU avoids calling the same defense twice in a row
@export var situation_weight := 1.2    ## how strongly down & distance shifts expectations

@export_group("Keyed defenders")
## Keying strength vs the human by difficulty (Rookie, Pro, All-Pro, Legend): beginners get a
## gentler adaptive defense. CPU-vs-CPU is unaffected.
@export var key_scale_by_difficulty := PackedFloat32Array([0.35, 0.7, 1.0, 1.15])
@export var reaction_cut := 0.35       ## keyed defenders react this much faster at level 1
@export var jump_blend := 0.65         ## how far coverage aims shift toward the next route point
@export var zone_shift := 0.8         ## zones slide this share of the way onto the repeated play's route points
@export var zone_shift_reach := 10.0   ## …for route points within this many yards of the zone center
@export var jump_reach := 3.0          ## extra yards a zone defender will leave his zone to jump a route
@export var ball_react_extra := 3.0    ## extra yards of radius in which defenders break on a throw
@export var int_bonus := 1.0           ## INT chance multiplier bonus at level 1
@export var contest_bonus := 0.8       ## yards of head start defenders get racing to the ball
@export var catch_contest_bonus := 0.35 ## added contest (0..1) on catches
@export var rush_speed_bonus := 0.06   ## blitzers run faster vs a keyed run
@export var shed_cut := 0.3           ## blocks hold this much shorter vs a keyed run
@export var blitz_weight := 0.5        ## CPU blitz calls (not goal line) are this much likelier to be picked vs a human offense (they get home in under 2 s)

@export_group("Difficulty: decisions")
## Difficulty changes how the CPU thinks, not just its OVR (Rookie, Pro, All-Pro, Legend).
## Every one of these only applies to the CPU side playing against you.
## Defensive play calling: exponent on its read of your tendencies (0 = calls at random, 1 =
## as designed, >1 = goes straight for the counter).
@export var call_iq_by_difficulty := PackedFloat32Array([0.25, 0.75, 1.0, 1.5])
## Defenders' reaction delay (reading the snap, the break, the throw) x this.
@export var react_mult_by_difficulty := PackedFloat32Array([1.35, 1.1, 1.0, 0.85])
## Zone defenders reading your QB's eyes (staring down a receiver draws them) x this.
@export var eyes_by_difficulty := PackedFloat32Array([0.2, 0.6, 1.0, 1.4])
## CPU quarterback's decision making: awareness points added for his reads and risk taking.
@export var qb_iq_by_difficulty := PackedFloat32Array([-18.0, -6.0, 3.0, 12.0])
## CPU coach (4th downs, 2-point tries, timeouts, clock): 0 = timid and careless, 1 = sharp.
@export var coach_iq_by_difficulty := PackedFloat32Array([0.2, 0.55, 0.85, 1.0])
## Simulated CPU drives: points per game from smarter play calling (the drive model's prior).
@export var drive_pts_by_difficulty := PackedFloat32Array([-2.0, 0.0, 1.0, 2.0])


## Value of a per-difficulty table for difficulty `d` (clamped; `fallback` if empty).
static func by_difficulty(table: PackedFloat32Array, d: int, fallback := 1.0) -> float:
	if table.is_empty():
		return fallback
	return table[clampi(d, 0, table.size() - 1)]
