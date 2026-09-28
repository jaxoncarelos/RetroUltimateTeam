class_name PackDef
extends Resource
## A card pack (PLAN.md §5). odds = chance per card of Bronze/Silver/Gold/Elite (sum 1).
## guarantee_tier: at least one card of that tier or better (-1 = none).
## positions: only players at these positions (empty = any). team: only this team ("" = any;
## "FRANCHISE" = the player's franchise).

@export var id := ""
@export var display_name := ""
@export var price := 500                 ## coins; 0 = reward-only
@export var card_count := 5
@export var odds := PackedFloat32Array([0.8, 0.18, 0.02, 0.0])
@export var guarantee_tier := -1
@export var positions: PackedStringArray = []
@export var team := ""
@export var color := Color("#b86f3c")
