class_name CardDef
extends RefCounted
## A collectible version of a player at one tier (id "mahomes_patrick_gold").

var id := ""
var player_id := ""
var tier := 0
var ovr := 55
var attrs: Dictionary = {}
var quicksell := 25


static func build(p: PlayerData, tier: int) -> CardDef:
	var c := CardDef.new()
	c.id = CardRules.card_id(p.id, tier)
	c.player_id = p.id
	c.tier = tier
	c.ovr = CardRules.card_ovr(tier, p.ovr)
	c.attrs = CardRules.card_attrs(p.attrs, p.ovr, c.ovr)
	c.quicksell = CardRules.quicksell(tier)
	return c
