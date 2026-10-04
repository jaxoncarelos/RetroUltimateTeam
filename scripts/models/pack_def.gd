class_name PackDef
extends Resource
## A card pack (PLAN.md §5). odds = chance per card of Bronze/Silver/Gold/Elite (sum 1);
## tiers come from card OVR (Bronze < 70, Silver 70-79, Gold 80-89, Elite 90+).
## guarantee_tier: at least one card of that tier or better (-1 = none).
## positions: only players at these positions (empty = any). team: only this team ("" = any;
## "FRANCHISE" = the player's franchise).

@export var id := ""
@export var display_name := ""
@export var price := 500                 ## coins; 0 = reward-only
@export var card_count := 5
@export var odds := PackedFloat32Array([0.8, 0.18, 0.02, 0.0])
@export var guarantee_tier := -1
@export var positions: Array[String] = []
@export var team := ""
@export var color := Color("#b86f3c")
## X-Factor (ability) cards vs a base card of the same tier: weight multiplier per card.
@export var xf_weight := 0.2
## At least this many cards are X-Factor versions (when the filters allow one).
@export var xf_guarantee := 0
## Draft pack: the cards are shown face-down with hints and you keep ONE of them.
@export var pick := false
## Mystery pack: it is secretly one of these packs (weights sum to 1), revealed on opening.
@export var mystery: Array[String] = []
@export var mystery_weights := PackedFloat32Array()
## Per card: chance it is a LEGEND card instead (retired greats, EconomyRules.pick_legend).
@export var legend_chance := 0.0
## The best this many cards are LEGEND cards (all of them = a legends-only pack/draft).
@export var legend_guarantee := 0
## One-line store pitch ("" = the card count / guarantee summary).
@export var blurb := ""
## LEGEND cards in this pack only come from these decades (legends.csv `era`, empty = any).
@export var eras: Array[String] = []
## Bundle: buying it queues these packs (Profile.pending_packs) instead of opening cards.
@export var bundle: Array[String] = []
## Store ribbon ("NEW", "BEST VALUE"; "" = none).
@export var tag := ""
## Name on the foil band ("" = display_name without " PACK" / " DRAFT").
@export var art_label := ""
