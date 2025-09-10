extends Node
class_name SaverLoader

func save_game():
	var file = FileAccess.open("res://savegame.data", FileAccess.WRITE)
	file.store_var(Time)
	pass

func load_game():
	pass
