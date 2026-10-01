class_name CardDef
extends RefCounted
## A collectible card of a player. The base card ("mahomes_patrick") has the player's real
## OVR; the rare Prime program ("mahomes_patrick_prime") is +CardRules.PRIME_BONUS. The tier
## (Bronze/Silver/Gold/Elite) is derived from the OVR. Owned copies can develop further
## (Profile card entry "dev"/"boost", see Collection.card_ovr).

var id := ""
var player_id := ""
var tier := 0
var ovr := 55
var attrs: Dictionary = {}
var quicksell := 25
var program := CardRules.PROGRAM_BASE
var pot := 55          ## development ceiling (card OVR + growth room of the player)
var age := 0
var ability := ""      ## AbilityRules id (X-Factor and CHAMP cards), "" = none


## Base card of a player. `_tier` is legacy (ignored): there is one base card per player.
static func build(p: PlayerData, _tier := -1) -> CardDef:
	return build_program(p, CardRules.PROGRAM_BASE)


static func build_program(p: PlayerData, program: String) -> CardDef:
	var c := CardDef.new()
	c.player_id = p.id
	c.program = program
	match program:
		CardRules.PROGRAM_PRIME:
			c.id = CardRules.prime_id(p.id)
		CardRules.PROGRAM_CHAMP:
			c.id = CardRules.champ_id(p.id)
		CardRules.PROGRAM_XFACTOR:
			c.id = CardRules.xf_id(p.id)
		CardRules.PROGRAM_CORE:
			c.id = CardRules.core_id(p.id)
		_:
			c.id = CardRules.card_id(p.id)
	if program in [CardRules.PROGRAM_XFACTOR, CardRules.PROGRAM_CHAMP]:
		c.ability = AbilityRules.ability_for(p.id, p.pos)
	c.ovr = CardRules.program_ovr(program, p.ovr)
	c.tier = CardRules.tier_for_ovr(c.ovr)
	c.attrs = CardRules.card_attrs(p.attrs, p.ovr, c.ovr)
	c.quicksell = CardRules.sell_price(c.ovr, program)
	c.pot = maxi(c.ovr, p.pot + (c.ovr - p.ovr))
	c.age = p.age
	return c


func is_champ() -> bool:
	return program == CardRules.PROGRAM_CHAMP


func is_prime() -> bool:
	return program == CardRules.PROGRAM_PRIME


func is_xfactor() -> bool:
	return program == CardRules.PROGRAM_XFACTOR


func is_core() -> bool:
	return program == CardRules.PROGRAM_CORE
