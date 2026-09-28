extends Node
## Global signal bus. Only signals live here — no state.

signal play_started(play_name: String)
signal play_ended(result: Dictionary)
signal carrier_changed(agent: Node)
signal touchdown(team: int)
signal drive_ended(reason: String)
