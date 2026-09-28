class_name PlaybookDef
extends Resource
## An explicit list of plays (export-safe; no directory scanning).

@export var id := ""
@export var plays: Array[PlayDef] = []
