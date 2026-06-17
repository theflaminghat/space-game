extends Node

## In-game year at which orbital motion stops and all non-star bodies are hidden.
## Past this threshold the game runs at extreme fast-forward; individual planet
## positions are meaningless and the simulation saves the CPU by not computing them.
## Planets reappear whenever the game is paused so the player can still interact.
const ORBIT_FREEZE_YEAR: int = 1_000_000

var seconds_per_day: float = 0.1
var paused: bool = false
var ui_paused: bool = false

## Current in-game year — written by Game.gd each year tick so any node can
## read it without depending on Game directly.
var current_year: int = 1945

## Year the frozen planets snap to when shown.  Normally tracks current_year, but
## Game.gd overrides it just before a pause so the planet the player is viewing
## keeps its exact position (the others fall into their relative places for that
## time).  See Planet._snap_to_year / Planet.compute_anchor_year.
var snap_year: float = 1945.0

## False once the year passes ORBIT_FREEZE_YEAR.  Planets watch this via signals.
var solar_system_active: bool = true

## Emitted when solar_system_active flips.
signal active_changed

## Emitted when either pause flag changes so planets can update their visibility.
signal paused_changed


func toggle_pause() -> void:
	paused = !paused
	paused_changed.emit()


func toggle_ui_pause() -> void:
	ui_paused = !ui_paused
	paused_changed.emit()


## Call this instead of writing solar_system_active directly so the signal fires.
func set_solar_system_active(v: bool) -> void:
	if solar_system_active == v:
		return
	solar_system_active = v
	active_changed.emit()
