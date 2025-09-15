class_name player extends Node

var playerName:String

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

func addItem(planet:String,itemID:int,amount:float):
	for i in inventory[planet]:
		if i[0] == itemID:
			i[1] = i[1] + amount
			return
	inventory[planet].append([itemID,amount])
