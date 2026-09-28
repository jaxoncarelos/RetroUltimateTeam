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
@export var carrier_speed_mult := 0.94 ## ball carriers run a bit slower than their top speed
@export var pursuit_speed_mult := 1.05 ## pursuing defenders run a bit faster (effort + angles)

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
@export var int_base := 0.07
@export var int_cov_scale := 0.26
@export var tip_int_chance := 0.07     ## a contested ball the receiver fails to catch pops to the defender

@export var press_jam_base := 0.45    ## seconds a pressed receiver is jammed at equal ratings
@export var press_jam_per_point := 0.012 ## extra jam seconds per point of coverage over route running
@export var press_jam_max := 0.9
@export var press_jam_speed := 0.4     ## speed multiplier while jammed
@export var press_depth := 1.3         ## yards off the ball a press corner lines up
@export var man_hold_depth := 3.0      ## man defenders wait this deep while their man is in the backfield
@export var pa_bite_time := 0.75       ## seconds underneath zone defenders step up on a play fake (awareness 60)

@export_group("CPU quarterback")
@export var cpu_read_slow := 0.6       ## seconds per progression read at awareness 60
@export var cpu_read_fast := 0.32      ## … at awareness 99
@export var cpu_read_noise := 1.2      ## yards of openness misjudgment at awareness 60
@export var cpu_open_threshold := 2.4  ## yards of projected separation to pull the trigger
@export var cpu_min_throw_time := 0.75 ## earliest throw (plus 0.12 s per yard of drop)
@export var cpu_max_hold := 2.6        ## after this the QB takes the best option or throws it away
@export var cpu_checkdown_open := 0.6

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
@export var run_engage_range := 1.6    ## run blockers latch on from a bit farther
@export var snap_engage_range := 2.8   ## on run plays linemen fire off and engage the man over them at the snap
@export var fall_forward_time := 0.3  ## tackled carriers fall forward: spot += forward speed × this
@export var fall_forward_max := 2.8
@export var shed_base := 1.9           ## seconds a block holds at equal ratings
@export var shed_per_point := 0.035
@export var shed_min := 0.5
@export var shed_jitter := 0.35

@export var fumble_base := 0.012      ## fumble chance per tackle at equal ratings
@export var fumble_scale := 0.03       ## extra chance per 40 points of hit power over ball security
@export var fumble_recover_radius := 4.0

@export_group("Defense controls")
@export var jump_time := 0.5           ## seconds a defender's leap lasts; ideal = ball arrives at the peak
@export var jump_height := 0.9         ## yards
@export var jump_reach := 0.9          ## extra yards of reach while leaping
@export var jump_start_range := 4.5    ## yards from the landing spot a leap can start
@export var jump_perfect := 0.09       ## s of timing error for a perfect jump
@export var jump_good := 0.22          ## s of timing error that still gets a hand on it
@export var jump_int_perfect := 0.55   ## base INT chance on a perfect jump (scaled by coverage/hands)
@export var jump_deflect_good := 0.75  ## swat chance on a good (not perfect) jump
@export var stick_deadzone := 6.0      ## px before the defense stick moves the player
@export var stick_full := 26.0         ## px of drag for full speed
@export var tap_carrier_radius := 3.5  ## yards: a tap this close to the ball carrier is a dive
@export var human_dive_range := 2.8    ## yards: max distance for the human's dive tackle
@export var tap_switch_radius := 2.2   ## yards: tapping this close to a defender switches to him
@export var tap_ball_radius := 5.0     ## yards: a tap this close to the landing marker is a jump
@export var switch_manual_hold := 1.5  ## s a manual switch holds before auto-switch may override
@export var switch_margin := 0.35      ## s of intercept time a new auto pick must be better by

@export_group("Kicking")
@export var touchback_yard := 25.0        ## kickoff touchback spot (yards from own goal)
@export var kickoff_touchback_low := 0.55 ## touchback chance at kick power 0
@export var kickoff_touchback_high := 0.9
@export var kickoff_big_return := 0.03
@export var punt_base := 36.0
@export var punt_power := 14.0            ## extra gross yards at kick power 99
@export var punt_spread := 6.0
@export var punt_return_max := 9.0
@export var fg_range_base := 44.0         ## max FG distance at kick power 0
@export var fg_range_power := 20.0
@export var meter_zone_base := 0.22       ## green half-width of the kick meter
@export var meter_doink := 0.05
@export var meter_speed_base := 0.9       ## needle sweeps per second
@export var meter_speed_range := 1.1

@export_group("Game clock")
@export var runoff_normal := 32.0         ## game seconds between plays when the clock runs
@export var runoff_hurry := 9.0           ## offense trailing in the last 2:00 of a half
@export var runoff_milk := 36.0           ## offense leading in the last 4:00 of the game

@export_group("Runner controls")
@export var steer_deadzone := 5.0      ## px
@export var steer_full := 28.0         ## px of vertical drag for full lateral
@export var juke_speed := 7.5          ## lateral yd/s burst
@export var juke_time := 0.22
@export var juke_cooldown := 0.9
@export var flick_speed := 450.0       ## px/s drag velocity that counts as a flick
@export var dive_distance := 2.0
@export var dive_time := 0.35
