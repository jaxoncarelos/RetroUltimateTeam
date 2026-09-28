class_name GameplayTuning
extends Resource
## Every gameplay constant lives here so balancing never requires code changes.

@export_group("Movement")
@export var speed_base := 4.6          ## yd/s at 0 speed rating
@export var speed_range := 4.4         ## extra yd/s at 99 speed
@export var accel_base := 9.0          ## yd/s^2
@export var accel_range := 11.0
@export var reaction_slow := 0.35      ## seconds at awareness 60
@export var reaction_fast := 0.10      ## seconds at awareness 99
@export var cut_keep_min := 0.45       ## velocity kept through a route cut at route running 0
@export var cut_keep_max := 0.9        ## … at route running 99

@export_group("Passing")
@export var throw_speed_base := 17.0   ## yd/s
@export var throw_speed_range := 13.0
@export var throw_dist_base := 38.0    ## max yards at 0 throw power
@export var throw_dist_range := 30.0
@export var aim_gain := 0.42           ## yards of throw per screen pixel of drag
@export var aim_min_drag := 10.0       ## px; shorter drags cancel the throw
@export var aim_error_base := 0.07     ## yards of error per yard thrown at accuracy 0
@export var lob_extra_time := 0.35     ## deep throws hang this fraction longer
@export var catch_radius := 1.4        ## yards
@export var contest_radius := 1.6
@export var catch_base_low := 0.72     ## uncontested catch % at catching 50
@export var catch_base_high := 0.98    ## … at catching 99
@export var contest_penalty := 0.7
@export var int_base := 0.18
@export var int_cov_scale := 0.35

@export_group("Contact")
@export var tackle_range := 0.85
@export var tackle_bias := 1.4         ## sigmoid offset: >0 favors the tackler
@export var tackle_k := 14.0
@export var tackle_min := 0.3
@export var tackle_max := 0.95
@export var juke_tackle_mult := 0.45
@export var missed_tackle_stun := 0.7
@export var cpu_dive_range := 1.9      ## CPU defenders launch a dive tackle inside this range
@export var dive_tackle_range := 1.15
@export var dive_tackle_bonus := 0.08
@export var dive_recover := 0.8        ## seconds a defender stays down after a dive
@export var open_field_shed_mult := 0.35 ## blocks after the catch/handoff hold this much shorter
@export var engage_range := 1.2
@export var shed_base := 1.9           ## seconds a block holds at equal ratings
@export var shed_per_point := 0.035
@export var shed_min := 0.5
@export var shed_jitter := 0.35

@export_group("Runner controls")
@export var steer_deadzone := 5.0      ## px
@export var steer_full := 28.0         ## px of vertical drag for full lateral
@export var juke_speed := 7.5          ## lateral yd/s burst
@export var juke_time := 0.22
@export var juke_cooldown := 0.9
@export var flick_speed := 450.0       ## px/s drag velocity that counts as a flick
@export var dive_distance := 2.0
@export var dive_time := 0.35
