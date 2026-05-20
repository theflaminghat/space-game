# ResearchNode.gd
# Represents a single node in the research tree.
# Attach this as a resource or use it as a plain class.

extends Resource
class_name ResearchNode

var id: String
var display_name: String
var description: String
var prerequisites: Array = []
var cost: Dictionary = {}
var research_time: float = 0.0
var position: Vector2 = Vector2.ZERO


## IDs of nodes that this node unlocks (populated automatically by ResearchTree)
var unlocks: Array = []

## Current state of this node
enum State { LOCKED, AVAILABLE, RESEARCHING, UNLOCKED }
var state: State = State.LOCKED

## Progress toward completion (0.0 – 1.0) when state == RESEARCHING
var progress: float = 0.0

## How many "ticks" of research this costs

## Tier in the tree (0 = root tier). Set automatically by ResearchTree.
var tier: int = 0


func _to_string() -> String:
	return "ResearchNode(%s, state=%s)" % [id, State.keys()[state]]
