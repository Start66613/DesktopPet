extends Node
class_name PetMusicInfoService

signal info_ready(track_id: String, info: Dictionary)

const WIKIPEDIA_API := "https://zh.wikipedia.org/w/api.php"
const USER_AGENT := "DesktopPet/0.1 (music companion)"

var _request: HTTPRequest
var _pending_track_id := ""
var _pending_cache_key := ""
var _cache: Dictionary = {}


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 12.0
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)


func request_info(session: Dictionary) -> void:
	var track_id := String(session.get("track_id", "")).strip_edges()
	var title := String(session.get("title", "")).strip_edges()
	var artist := String(session.get("artist", "")).strip_edges()
	if track_id.is_empty() or title.is_empty():
		return
	var cache_key := (title + "|" + artist).to_lower()
	if _cache.has(cache_key):
		call_deferred("_emit_cached", track_id, Dictionary(_cache[cache_key]))
		return
	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_request.cancel_request()
	_pending_track_id = track_id
	_pending_cache_key = cache_key
	var query := "%s %s 歌曲" % [title, artist]
	var url := WIKIPEDIA_API + "?action=query&generator=search&gsrnamespace=0&gsrlimit=1&gsrsearch=" \
		+ query.uri_encode() + "&prop=extracts&exintro=1&explaintext=1&exsentences=3&redirects=1&format=json&formatversion=2&origin=*"
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: " + USER_AGENT])
	var error := _request.request(url, headers)
	if error != OK:
		_pending_track_id = ""
		_pending_cache_key = ""


func _emit_cached(track_id: String, info: Dictionary) -> void:
	info_ready.emit(track_id, info)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var track_id := _pending_track_id
	var cache_key := _pending_cache_key
	_pending_track_id = ""
	_pending_cache_key = ""
	if track_id.is_empty() or result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var query: Dictionary = parsed.get("query", {})
	var pages: Array = query.get("pages", [])
	if pages.is_empty() or not pages[0] is Dictionary:
		return
	var page: Dictionary = pages[0]
	var summary := String(page.get("extract", "")).replace("\n", " ").strip_edges()
	if summary.is_empty():
		return
	var info := {
		"title": String(page.get("title", "")),
		"summary": summary.left(600),
		"source": "中文维基百科"
	}
	_cache[cache_key] = info
	info_ready.emit(track_id, info)