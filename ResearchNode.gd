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
var boosts: Dictionary = {}   # e.g. {"ai_research_efficiency": 0.35, "energy_production": 0.15}
var position: Vector2 = Vector2.ZERO


## IDs of nodes that this node unlocks (populated automatically by ResearchTree)
var unlocks: Array = []

## Current state of this node
enum State { LOCKED, AVAILABLE, RESEARCHING, UNLOCKED }
var state: State = State.LOCKED

## Progress toward completion (0.0 – 1.0) when state == RESEARCHING
var progress: float = 0.0

## Tier in the tree (0 = root tier). Set automatically by ResearchTree.
##
## DEPTH, not rank: this is how far along the prerequisite chain the node sits, and it is what
## ResearchTreeData's cost surcharge is keyed on.  The repeatable-research levels below are a
## different axis entirely, which is why they are not called tiers in the code.
var tier: int = 0


# ── Repeatable research ───────────────────────────────────────────────────────
#
# Most nodes are a single discovery: researched once, and then they are simply known.  Some are
# a line of work that keeps paying — better telescopes, better radiators, better forecasting
# models — and those can be taken more than once, each pass costing more than the last and
# adding its boosts again.
#
# `max_level` is how many times the node can be taken AT ALL (1 = an ordinary one-shot node),
# and `level` is how many times it has been.  Everything in the game that gates on a node asks
# is_unlocked(), which is true from level 1, so adding levels to a node never changes what it
# opens — only how far it can be pushed.

## How many times this node can be researched.  1 is an ordinary node.
var max_level: int = 1

## How many times it HAS been researched.  0 until the first pass completes.
var level: int = 0

## What each pass costs relative to the one before it.  Overridable per node; ResearchTreeData
## supplies the default.
var level_cost_growth: float = 2.0


## Whether the civilisation KNOWS this node — which is what every gate in the game means by
## "unlocked", and what the prerequisite graph is built on.
##
## Keyed on the level, not on the state, and that distinction is load-bearing: taking a second
## pass at a repeatable node puts it back into RESEARCHING, and if being known meant being in
## the UNLOCKED state then starting that pass would close the gate again — detection would fall
## to zero, dependent nodes would re-lock, and buildings would vanish from the build panel for
## as long as the upgrade ran.  Once a thing is known it stays known.
func is_known() -> bool:
	return level >= 1


## Whether this node is a line of work rather than a single discovery.
func is_repeatable() -> bool:
	return max_level > 1


## Whether another pass is available.
func has_next_level() -> bool:
	return level < max_level


## Science for pass `n`, counting from 1.  `cost` holds the first pass; each one after it
## multiplies by level_cost_growth, so a five-level node's last pass costs sixteen times its
## first.
func cost_for_level(n: int) -> Dictionary:
	var step: int = maxi(n, 1) - 1
	if step <= 0:
		return cost
	var out: Dictionary = {}
	var mult: float = pow(maxf(level_cost_growth, 1.0), float(step))
	for k: String in cost:
		out[k] = float(cost[k]) * mult
	return out


## Science for the pass that would be bought next — and, while one is running, the pass being
## paid for, since `level` counts only completed ones.
func cost_for_next_level() -> Dictionary:
	return cost_for_level(level + 1)


## The bill worth showing the player: the next pass where there is one, and otherwise the last
## one taken.
##
## Not cost_for_next_level(), which for a finished node names a pass that does not exist — on a
## maxed repeatable line that is a price nothing can be bought at, and on an ordinary unlocked
## node it is double what the node actually cost.
func cost_shown() -> Dictionary:
	return cost_for_level(level + 1) if has_next_level() else cost_for_level(maxi(level, 1))


## The boosts this node is currently contributing: one pass' worth per level taken.
func boosts_at_level() -> Dictionary:
	if level <= 1:
		return boosts if level == 1 else {}
	var out: Dictionary = {}
	for k: String in boosts:
		out[k] = float(boosts[k]) * float(level)
	return out


func _to_string() -> String:
	if is_repeatable():
		return "ResearchNode(%s, state=%s, level=%d/%d)" % [
			id, State.keys()[state], level, max_level]
	return "ResearchNode(%s, state=%s)" % [id, State.keys()[state]]
