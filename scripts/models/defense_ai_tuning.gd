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
