extends Node
## Notification queue (Part 22.4). The HUD listens to `posted`; history is kept for the computer.

signal posted(text: String, kind: int)

enum { INFO, GOOD, WARN, BAD }

var history: Array = []


func push(text: String, kind: int = INFO) -> void:
	history.append({"text": text, "kind": kind, "time": Clock.minutes})
	if history.size() > 60:
		history.pop_front()
	posted.emit(text, kind)
	if OS.is_debug_build() and DisplayServer.get_name() == "headless":
		print("[notify] ", text)


func clear() -> void:
	history.clear()
