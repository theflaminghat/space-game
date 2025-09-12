extends Node

class_name sattelite

var inventory:Array
var position:String

func _init(initposition: String = "earth"):
	var inventory = []
	var position = initposition
	
