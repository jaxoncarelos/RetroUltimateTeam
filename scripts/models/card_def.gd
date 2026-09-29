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


## Base card of a player. `_tier` is legacy (ignored): there is one base card per player.
static func build(p: PlayerData, _tier := -1) -> CardDef:
	return build_program(p, CardRules.PROGRAM_BASE)


static func build_program(p: PlayerData, program: String) -> CardDef:
	var c := CardDef.new()
	c.player_id = p.id
	c.program = program
	c.id = CardRules.prime_id(p.id) if program == CardRules.PROGRAM_PRIME else (CardRules.champ_id(p.id) if program == CardRules.PROGRAM_CHAMP else CardRules.card_id(p.id))
	c.ovr = CardRules.program_ovr(program, p.ovr)
	c.tier = CardRules.tier_for_ovr(c.ovr)
	c.attrs = CardRules.card_attrs(p.attrs, p.ovr, c.ovr)
	c.quicksell = CardRules.quicksell(c.tier, program)
	c.pot = maxi(c.ovr, p.pot + (c.ovr - p.ovr))
	c.age = p.age
	return c


func is_champ() -> bool:
	return program == CardRules.PROGRAM_CHAMP


func is_prime() -> bool:
	return program == CardRules.PROGRAM_PRIME
