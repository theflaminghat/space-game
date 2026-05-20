extends Node

var seconds_per_day: float = 0.1
var paused: bool = false
var ui_paused: bool = false

func toggle_pause() -> void:
	paused = !paused

func toggle_ui_pause() -> void:
	ui_paused = !ui_paused
