class_name FormationDef
extends Resource
## Where each slot lines up, in yards relative to the ball.
## x: + is downfield for the offense (defense slots use + for depth off the ball).
## y: + is toward the bottom sideline.
## Slot entry: {"pos": "WR", "at": Vector2(-0.5, -16)}; defenders may add "align": "WR1"
## to take that offensive slot's y.

@export var id := ""
@export var display_name := ""
@export_enum("offense", "defense") var side := "offense"
@export var slots: Dictionary = {}
