class_name PlayDef
extends Resource
## One play call. Assignments map slot -> behavior dictionary:
##   offense: {"type": "pass", "drop": 3.0, "fake": true}   QB drops back; fake = play action
##            {"type": "handoff", "to": "RB", "mesh": Vector2, "delay": s, "range": yd}
##                                                            QB hands off (range > 2 = pitch)
##            {"type": "sneak", "path": PackedVector2Array}  QB keeps it (runner from the snap)
##            {"type": "route", "path": PackedVector2Array, "end": "continue"|"sit", "delay": s}
##            {"type": "carry", "path": PackedVector2Array, "delay": s}  runner path; takes the handoff
##            {"type": "block"}
##   defense: {"type": "rush"} | {"type": "man", "target": "WR1", "press": true}
##            {"type": "zone", "center": Vector2, "size": Vector2}  (rel. ball, x = depth)
## Route/carry paths are waypoints relative to the player's alignment.

@export var id := ""
@export var display_name := ""
@export_enum("offense", "defense") var side := "offense"
@export var category := "SHORT"   ## RUN/SHORT/DEEP | MAN/ZONE/BLITZ
@export var formation: FormationDef
@export var assignments: Dictionary = {}
## Defense: offensive categories this call is strong against (drives CPU counter-calls).
@export var counters: PackedStringArray = []
## Situational tags, e.g. short_yardage, goal_line, screen, play_action, deep, prevent.
@export var tags: PackedStringArray = []


func is_run() -> bool:
	return category == "RUN"
