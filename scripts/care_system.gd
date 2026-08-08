extends Node
class_name PetCareSystem

signal stats_changed(stats: Dictionary)
signal action_performed(result: Dictionary)

const SAVE_PATH := "user://care_state.cfg"
const OFFLINE_CAP_SECONDS := 8.0 * 60.0 * 60.0
const SAVE_INTERVAL := 15.0
const UI_REFRESH_INTERVAL := 0.5

const STAT_KEYS := [&"fullness", &"hydration", &"mood", &"affection", &"energy"]

const ITEM_CATALOG := {
	"meal": [
		{"name": "樱桃布丁", "icon": "res://assets/care/runtime/items/pudding.png", "emoji": "🍮", "message": "布丁甜甜的，心情也变好啦 (*^_^*)", "changes": {"fullness": 16.0, "mood": 4.0, "affection": 1.0}},
		{"name": "草莓蛋糕", "icon": "res://assets/care/runtime/items/strawberry_cake.png", "emoji": "🍰", "message": "草莓蛋糕！这一口分你一半 (^o^)", "changes": {"fullness": 18.0, "mood": 7.0, "affection": 2.0}},
		{"name": "爱心三明治", "icon": "res://assets/care/runtime/items/sandwich.png", "emoji": "🥪", "message": "吃饱啦，接下来也有精神陪你！", "changes": {"fullness": 24.0, "mood": 2.0, "affection": 1.0}},
		{"name": "爱心饭团", "icon": "res://assets/care/runtime/items/rice_ball.png", "emoji": "🍙", "message": "饭团软乎乎的，好满足呀 (^_^)", "changes": {"fullness": 28.0, "mood": 3.0, "affection": 1.0}},
		{"name": "蛋包饭", "icon": "res://assets/care/runtime/items/omurice.png", "emoji": "🍳", "message": "是热乎乎的蛋包饭！我会好好吃完的。", "changes": {"fullness": 34.0, "mood": 5.0, "affection": 2.0}}
	],
	"drink": [
		{"name": "珍珠奶茶", "icon": "res://assets/care/runtime/items/bubble_tea.png", "emoji": "🧋", "message": "嚼到珍珠啦，好快乐！", "changes": {"hydration": 17.0, "mood": 6.0, "energy": 2.0}},
		{"name": "草莓牛奶", "icon": "res://assets/care/runtime/items/strawberry_milk.png", "emoji": "🍓", "message": "草莓牛奶是粉色的，和蝴蝶结很配呢。", "changes": {"hydration": 20.0, "mood": 4.0, "affection": 1.0}},
		{"name": "鲜橙果汁", "icon": "res://assets/care/runtime/items/fruit_juice.png", "emoji": "🍊", "message": "酸酸甜甜的，一下子清醒了！", "changes": {"hydration": 25.0, "mood": 3.0, "energy": 4.0}},
		{"name": "矿泉水", "icon": "res://assets/care/runtime/items/water.png", "emoji": "💧", "message": "咕咚咕咚……补充水分完成！", "changes": {"hydration": 32.0}},
		{"name": "热可可", "icon": "res://assets/care/runtime/items/hot_cocoa.png", "emoji": "☕", "message": "暖暖的热可可，捧在手里好安心。", "changes": {"hydration": 18.0, "mood": 6.0, "affection": 1.0}}
	],
	"play": [
		{"name": "玩偶时间", "icon": "res://assets/care/runtime/items/teddy_bear.png", "emoji": "🧸", "message": "它可爱，还是我更可爱？要认真回答哦。", "changes": {"mood": 12.0, "energy": -3.0, "affection": 2.0}},
		{"name": "一起听歌", "icon": "res://assets/care/runtime/items/headphones.png", "emoji": "🎧", "message": "这首歌很好听，偷偷加入我们的歌单吧。", "changes": {"mood": 15.0, "energy": -2.0, "affection": 2.0}, "activity": "music"},
		{"name": "掌机对战", "icon": "res://assets/care/runtime/items/handheld_game.png", "emoji": "🎮", "message": "再来一局！这次我一定能赢你 (>_<)", "changes": {"mood": 20.0, "energy": -7.0, "hydration": -2.0, "affection": 3.0}, "activity": "handheld"},
		{"name": "一起画画", "icon": "res://assets/care/runtime/items/sketchbook.png", "emoji": "🎨", "message": "我把今天画下来啦，旁边这个就是你。", "changes": {"mood": 17.0, "energy": -5.0, "affection": 3.0}},
		{"name": "故事时间", "icon": "res://assets/care/runtime/items/storybook.png", "emoji": "📖", "message": "再读一页嘛，我还不想让故事结束。", "changes": {"mood": 13.0, "energy": -2.0, "affection": 3.0}},
		{"name": "羽毛球", "icon": "res://assets/care/runtime/items/badminton.png", "emoji": "🏸", "message": "看我的挥拍！陪我多打几个回合吧 (>_<)", "changes": {"mood": 18.0, "energy": -6.0, "affection": 3.0}, "activity": "badminton"}
	],
	"gift": [
		{"name": "玫瑰花束", "icon": "res://assets/care/runtime/items/flower_bouquet.png", "emoji": "💐", "message": "送给我的吗？我会好好珍惜的……", "changes": {"mood": 13.0, "affection": 8.0}},
		{"name": "星星挂饰", "icon": "res://assets/care/runtime/items/star_charm.png", "emoji": "⭐", "message": "挂在身边，就像你一直陪着我一样。", "changes": {"mood": 8.0, "affection": 6.0}},
		{"name": "蝴蝶结礼盒", "icon": "res://assets/care/runtime/items/wrapped_gift.png", "emoji": "🎁", "message": "可以现在拆开吗？我已经等不及啦！", "changes": {"mood": 16.0, "affection": 9.0}},
		{"name": "爱心发饰", "icon": "res://assets/care/runtime/items/hair_bow.png", "emoji": "🎀", "message": "戴起来好看吗？只许看着我回答。", "changes": {"mood": 12.0, "affection": 8.0}},
		{"name": "手写信", "icon": "res://assets/care/runtime/items/heart_letter.png", "emoji": "💌", "message": "我会把这封信收在最重要的地方。", "changes": {"mood": 10.0, "affection": 10.0}}
	]
}

var _stats := {
	"fullness": 78.0,
	"hydration": 76.0,
	"mood": 82.0,
	"affection": 35.0,
	"energy": 80.0
}
var _sleeping := false
var _save_elapsed := 0.0
var _refresh_elapsed := 0.0
var _stats_dirty := false


func _ready() -> void:
	_load_state()
	tree_exiting.connect(save_state)
	stats_changed.emit(get_stats())


func _process(delta: float) -> void:
	_apply_time_passage(delta, _sleeping)
	_save_elapsed += delta
	_refresh_elapsed += delta
	if _stats_dirty and _refresh_elapsed >= UI_REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_stats_dirty = false
		stats_changed.emit(get_stats())
	if _save_elapsed >= SAVE_INTERVAL:
		save_state()


func set_sleeping(value: bool) -> void:
	_sleeping = value


func get_stats() -> Dictionary:
	return _stats.duplicate(true)


func get_items(category: String) -> Array:
	if not ITEM_CATALOG.has(category):
		return []
	return ITEM_CATALOG[category].duplicate(true)


func get_lowest_need() -> Dictionary:
	var lowest_key: StringName = &"fullness"
	var lowest_value := 101.0
	for key in [&"fullness", &"hydration", &"mood", &"energy"]:
		var value := float(_stats[key])
		if value < lowest_value:
			lowest_key = key
			lowest_value = value
	return {"key": String(lowest_key), "value": lowest_value}


func perform_action(action: String, item_index := -1) -> Dictionary:
	var result := {
		"success": true,
		"action": action,
		"message": "",
		"emoji": "",
		"effect": "sparkle",
		"feedback": ""
	}

	if ITEM_CATALOG.has(action):
		var items: Array = ITEM_CATALOG[action]
		if item_index < 0 or item_index >= items.size():
			return _failed_result(action, "这个好像还没有准备好。", "")
		if action == "meal" and float(_stats["fullness"]) >= 97.0:
			return _failed_result(action, "已经吃得饱饱的啦，晚点再一起吃吧。", "🍽️")
		if action == "drink" and float(_stats["hydration"]) >= 97.0:
			return _failed_result(action, "现在还不渴，先放在旁边好不好？", "💧")
		if action == "play" and float(_stats["energy"]) < 12.0:
			return _failed_result(action, "有一点困啦……休息好以后再陪你玩。", "💤")

		var item: Dictionary = items[item_index]
		_apply_changes(item["changes"])
		result["message"] = item["message"]
		result["emoji"] = item["emoji"]
		result["effect"] = _effect_for_action(action)
		result["feedback"] = item["name"]
		result["item_name"] = item["name"]
		if item.has("activity"):
			result["activity"] = item["activity"]
	else:
		match action:
			"chat":
				_apply_changes({"mood": 5.0, "affection": 2.0})
				result["message"] = "你愿意来和我说话，我就已经很开心啦。"
				result["emoji"] = "💬"
				result["effect"] = "mood"
				result["feedback"] = "陪伴 +1"
			"comfort":
				_apply_changes({"mood": 7.0, "affection": 3.0})
				result["message"] = "嘿嘿……再摸一下也不是不可以 (*´▽｀*)"
				result["emoji"] = "💕"
				result["effect"] = "affection"
				result["feedback"] = "好感 +3"
			"rest":
				result["message"] = "那我靠近一点休息，你要记得叫醒我哦。"
				result["emoji"] = "🌙"
				result["effect"] = "energy"
				result["feedback"] = "开始休息"
				result["request_sleep"] = true
			_:
				return _failed_result(action, "这个互动还没有准备好。", "")

	stats_changed.emit(get_stats())
	action_performed.emit(result)
	save_state()
	return result


func apply_ai_chat_reward() -> void:
	_apply_changes({"mood": 2.0, "affection": 1.0})
	stats_changed.emit(get_stats())
	save_state()


func apply_badminton_result(player_won: bool, best_rally: int) -> void:
	var rally_bonus := clampf(float(best_rally) * 0.35, 0.0, 5.0)
	var mood_reward := 4.0 + rally_bonus
	var affection_reward := 2.0 if player_won else 1.0
	if best_rally >= 8:
		affection_reward += 1.0
	_apply_changes({"mood": mood_reward, "affection": affection_reward})
	stats_changed.emit(get_stats())
	save_state()


func save_state() -> void:
	var config := ConfigFile.new()
	for key in STAT_KEYS:
		config.set_value("stats", String(key), float(_stats[key]))
	config.set_value("meta", "saved_at", Time.get_unix_time_from_system())
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("养成数据保存失败: " + error_string(error))
	_save_elapsed = 0.0


func _load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		push_warning("养成数据读取失败: " + error_string(error))
		return
	for key in STAT_KEYS:
		_stats[key] = clampf(float(config.get_value("stats", String(key), _stats[key])), 0.0, 100.0)
	var saved_at := float(config.get_value("meta", "saved_at", Time.get_unix_time_from_system()))
	var elapsed := clampf(Time.get_unix_time_from_system() - saved_at, 0.0, OFFLINE_CAP_SECONDS)
	_apply_time_passage(elapsed, false)
	_stats_dirty = false


func _apply_time_passage(seconds: float, sleeping: bool) -> void:
	if seconds <= 0.0:
		return
	_change_stat("fullness", -0.0035 * seconds)
	_change_stat("hydration", -0.0048 * seconds)
	if sleeping:
		_change_stat("energy", 0.38 * seconds)
		_change_stat("mood", 0.012 * seconds)
	else:
		_change_stat("energy", -0.0028 * seconds)
		_change_stat("mood", -0.0018 * seconds)
	if float(_stats["fullness"]) < 25.0:
		_change_stat("mood", -0.0025 * seconds)
	if float(_stats["hydration"]) < 20.0:
		_change_stat("mood", -0.0035 * seconds)


func _apply_changes(changes: Dictionary) -> void:
	for key in changes:
		_change_stat(String(key), float(changes[key]))


func _change_stat(key: String, amount: float) -> void:
	if not _stats.has(key):
		return
	var previous := float(_stats[key])
	var next := clampf(previous + amount, 0.0, 100.0)
	if not is_equal_approx(previous, next):
		_stats[key] = next
		_stats_dirty = true


func _effect_for_action(action: String) -> String:
	match action:
		"meal":
			return "fullness"
		"drink":
			return "hydration"
		"play":
			return "mood"
		"gift":
			return "affection"
	return "sparkle"


func _failed_result(action: String, message: String, emoji: String) -> Dictionary:
	var result := {
		"success": false,
		"action": action,
		"message": message,
		"emoji": emoji,
		"effect": "sparkle",
		"feedback": ""
	}
	action_performed.emit(result)
	return result
