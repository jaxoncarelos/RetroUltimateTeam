class_name DailyPopup
extends RefCounted
## Daily check-in popup (7-day login streak, DailyRules): the week's reward boxes with
## today's pulsing; CLAIM pays it with flying coins, a pack reward offers OPEN IT.


static func show(owner: Control, prof: Profile, ui: Dictionary) -> void:
	var cal := DailyRules.calendar(prof)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var streak := int(prof.login.get("streak", 0))
	col.add_child(MetaUI.label("COME BACK EVERY DAY - DAY 7 IS A GOLD PACK!", UiSkin.MUTED, 8,
			HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	var today_box: Control = null
	for d in cal:
		var box := _DayBox.new()
		box.info = d
		row.add_child(box)
		if d["today"]:
			today_box = box
	var dim: Control
	var claim := func() -> void:
		var res := DailyRules.check_in(prof)
		SaveManager.save()
		if res.get("already_claimed", false):
			return
		var r: Dictionary = res["reward"]
		Sfx.play("claim")
		var pill: CoinPill = ui["coins"]
		if int(r["coins"]) > 0:
			var from := today_box.get_global_rect().get_center() if today_box != null else Vector2(240, 135)
			Fx.fly_coins(ui["layer"], from, pill.coin_global(), 12)
			pill.set_coins(prof.coins)
			MetaUI.toast(owner, "DAY %d: +%d COINS" % [int(res["day"]), int(r["coins"])])
		if str(r["pack"]) != "":
			var pack := PackCatalog.get_pack(r["pack"])
			var body := MetaUI.label("%s ADDED!" % (pack.display_name if pack != null else "PACK"), UiSkin.YELLOW, 16,
					HORIZONTAL_ALIGNMENT_CENTER)
			var open_it := func() -> void:
				var cfg := GameFlow.open_pending_config(prof, SceneRouter.HUB)
				if not cfg.is_empty():
					SceneRouter.goto(cfg["scene"], cfg)
			MetaUI.popup(owner, "DAY %d REWARD" % int(res["day"]), body, [["LATER", Callable()], ["OPEN IT", open_it, true]])
	dim = MetaUI.popup(owner, "DAILY CHECK-IN  -  STREAK %d" % (streak + 1), col, [["CLAIM", claim, true]])


## One day of the calendar: DAY n, the reward (coins or a pack chip), a check when claimed.
class _DayBox:
	extends Control
	var info: Dictionary = {}
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(44, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if info.get("today", false):
			queue_redraw()

	func _draw() -> void:
		var today: bool = info.get("today", false)
		var claimed: bool = info.get("claimed", false)
		var fill := UiSkin.ROW if not today else UiSkin.NAVY_HI
		var border := UiSkin.YELLOW if today else UiSkin.BORDER
		var r := Rect2(Vector2.ZERO, size)
		if today:
			var g := 1.0 + sin(_t * 5.0)
			draw_rect(r.grow(1.0 + g), Color(UiSkin.YELLOW, 0.25))
		UiSkin.draw_frame(self, r, fill, border)
		UiSkin.draw_text_c(self, size.x * 0.5, 10, "DAY %d" % int(info.get("day", 1)), 8,
				UiSkin.YELLOW if today else UiSkin.WHITE)
		var rw: Dictionary = info.get("reward", {})
		if str(rw.get("pack", "")) != "":
			var pack := PackCatalog.get_pack(rw["pack"])
			var pc: Color = pack.color if pack != null else UiSkin.YELLOW
			draw_rect(Rect2(size.x * 0.5 - 7, 14, 14, 18), UiSkin.SHADOW)
			draw_rect(Rect2(size.x * 0.5 - 6, 15, 12, 16), pc)
			draw_rect(Rect2(size.x * 0.5 - 6, 19, 12, 2), pc.lightened(0.4))
			UiSkin.draw_text_c(self, size.x * 0.5, 42, "PACK", 8, UiSkin.WHITE)
		else:
			UiSkin.draw_coin(self, Vector2(size.x * 0.5 - 7, 16), 2.0)
			UiSkin.draw_text_c(self, size.x * 0.5, 42, str(int(rw.get("coins", 0))), 8, UiSkin.WHITE)
		if claimed:
			draw_rect(r.grow(-1), Color(0.02, 0.05, 0.2, 0.55))
			UiSkin.draw_icon(self, "check", Vector2(size.x * 0.5 - 7, 16), UiSkin.GREEN, 2.0)
