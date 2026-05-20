class_name player extends Node

var playerName:String
var money:float

var inventory = {
	"mercury": [],
	"venus": [],
	"earth": [],
	"mars": [],
	"jupiter": [],
	"saturn": [],
	"uranus": [],
	"neptune": [],
}

func _init(playerName_:String = ""):
	playerName = playerName_
