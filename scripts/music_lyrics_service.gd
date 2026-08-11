extends Node
class_name PetMusicLyricsService

signal lyrics_ready(track_id: String, lines: Array[Dictionary], source: String)
signal lyrics_failed(track_id: String, message: String)

const QQ_SEARCH_URL := "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=12&format=json&w="
const QQ_LYRIC_URL := "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?format=json&nobase64=1&songmid="
const REQUEST_HEADERS := [
	"User-Agent: Mozilla/5.0",
	"Referer: https://y.qq.com/",
	"Accept: application/json, text/plain, */*"
]

var _request: HTTPRequest
var _session: Dictionary = {}
var _track_id := ""
var _stage := ""
var _selected_mid := ""
var _cache: Dictionary = {}


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 12.0
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)


func request_lyrics(session: Dictionary) -> void:
	var track_id := String(session.get("track_id", ""))
	var title := _clean_metadata(String(session.get("title", "")))
	if track_id.is_empty() or title.is_empty():
		return
	if _cache.has(track_id):
		var cached: Dictionary = _cache[track_id]
		lyrics_ready.emit(track_id, cached.get("lines", []), String(cached.get("source", "QQ音乐歌词")))
		return
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_request.cancel_request()
	_session = session.duplicate(true)
	_track_id = track_id
	_stage = "search"
	_selected_mid = ""
	var artist := _clean_metadata(String(session.get("artist", "")))
	var query := title + (" " + artist if not artist.is_empty() else "")
	var error := _request.request(QQ_SEARCH_URL + query.uri_encode(), PackedStringArray(REQUEST_HEADERS))
	if error != OK:
		_fail("歌词搜索暂时不可用")


func clear_cache() -> void:
	_cache.clear()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_fail("歌词网络走神了一下")
		return
	var text := body.get_string_from_utf8().strip_edges()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_fail("歌词格式没有认出来")
		return
	if _stage == "search":
		_handle_search(parsed)
	elif _stage == "lyrics":
		_handle_lyrics(parsed)


func _handle_search(payload: Dictionary) -> void:
	var data: Dictionary = payload.get("data", {})
	var song_data: Dictionary = data.get("song", {})
	var songs: Array = song_data.get("list", [])
	var best_score := -1.0
	var best_mid := ""
	for value in songs:
		if not value is Dictionary:
			continue
		var song: Dictionary = value
		var score := _score_song(song)
		if score > best_score:
			best_score = score
			best_mid = String(song.get("songmid", ""))
	if best_mid.is_empty() or best_score < 70.0:
		_fail("这首歌暂时没有匹配到歌词")
		return
	_selected_mid = best_mid
	_stage = "lyrics"
	var error := _request.request(QQ_LYRIC_URL + best_mid.uri_encode(), PackedStringArray(REQUEST_HEADERS))
	if error != OK:
		_fail("歌词读取暂时不可用")


func _handle_lyrics(payload: Dictionary) -> void:
	var lyric := _decode_html(String(payload.get("lyric", "")))
	var lines := _parse_lrc(lyric)
	if lines.is_empty():
		_fail("这首歌暂时没有同步歌词")
		return
	_cache[_track_id] = {"lines": lines, "source": "QQ音乐歌词"}
	lyrics_ready.emit(_track_id, lines, "QQ音乐歌词")
	_stage = ""


func _score_song(song: Dictionary) -> float:
	var expected_title := _normalize_text(String(_session.get("title", "")))
	var candidate_title := _normalize_text(String(song.get("songname", "")))
	var score := 0.0
	if candidate_title == expected_title:
		score += 90.0
	elif candidate_title.contains(expected_title) or expected_title.contains(candidate_title):
		score += 48.0

	var expected_artist := _normalize_text(String(_session.get("artist", "")))
	var singers: Array = song.get("singer", [])
	for value in singers:
		if not value is Dictionary:
			continue
		var singer := _normalize_text(String(value.get("name", "")))
		if not singer.is_empty() and (expected_artist.contains(singer) or singer.contains(expected_artist)):
			score += 60.0
			break

	var expected_duration := float(_session.get("duration_ms", 0)) / 1000.0
	var candidate_duration := float(song.get("interval", 0))
	if expected_duration > 0.0 and candidate_duration > 0.0:
		var difference := absf(expected_duration - candidate_duration)
		if difference <= 2.5:
			score += 35.0
		elif difference <= 7.0:
			score += 18.0
		elif difference >= 25.0:
			score -= 25.0
	return score


func _parse_lrc(raw_lyric: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var timestamp_regex := RegEx.new()
	timestamp_regex.compile("\\[(\\d{1,2}):(\\d{2}(?:\\.\\d{1,3})?)\\]")
	for raw_line in raw_lyric.split("\n", false):
		var line := String(raw_line).strip_edges()
		var matches := timestamp_regex.search_all(line)
		if matches.is_empty():
			continue
		var content := timestamp_regex.sub(line, "", true).strip_edges()
		if content.is_empty():
			continue
		for match_result in matches:
			var minutes := float(match_result.get_string(1))
			var seconds := float(match_result.get_string(2))
			result.append({"time_ms": roundi((minutes * 60.0 + seconds) * 1000.0), "text": content})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["time_ms"]) < int(b["time_ms"]))
	return result


func _clean_metadata(value: String) -> String:
	return value.replace("\n", " ").strip_edges()


func _normalize_text(value: String) -> String:
	var normalized := _clean_metadata(value).to_lower()
	var punctuation := RegEx.new()
	punctuation.compile("[\\s\\-_/·・.,，。'\"!！?？:：()（）\\[\\]【】]+")
	return punctuation.sub(normalized, "", true)


func _decode_html(value: String) -> String:
	return value.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">")


func _fail(message: String) -> void:
	var failed_track := _track_id
	_stage = ""
	lyrics_failed.emit(failed_track, message)
