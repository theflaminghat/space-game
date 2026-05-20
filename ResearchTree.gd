# ResearchTree.gd
# Autoload / singleton that manages the entire research tree state.
# Add this as an Autoload named "ResearchTree" in Project > Project Settings > Autoload.
#
# Usage:
#   ResearchTree.load_tree(my_nodes_array)
#   ResearchTree.start_research("laser_cannon")
#   ResearchTree.tick(delta)
#   ResearchTree.on_research_completed.connect(my_callback)

extends Node

## Emitted when any node changes state.
signal node_state_changed(node: ResearchNode)

## Emitted when a research job finishes.
signal research_completed(node: ResearchNode)

## Emitted when a research job is cancelled.
signal research_cancelled(node: ResearchNode)

## All nodes keyed by their id.
var nodes: Dictionary = {}  # id -> ResearchNode

## The node currently being researched (null if idle).
var active_research: ResearchNode = null

## Optional: allow queuing multiple research jobs.
var research_queue: Array = []

## Resources available to spend, e.g. {"science": 100, "gold": 200}
var resources: Dictionary = {}

var initialized: bool = false


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Load (or reload) the tree from an array of ResearchNode objects.
## Automatically computes tiers and reverse-populates `unlocks` arrays.
func load_tree(node_list: Array) -> void:
	if initialized:
		return
	initialized = true

	nodes.clear()
	active_research = null
	research_queue.clear()

	for node in node_list:
		assert(node is ResearchNode, "load_tree expects ResearchNode instances.")
		nodes[node.id] = node
		node.state = ResearchNode.State.LOCKED
		node.progress = 0.0
		node.unlocks.clear()
		node.tier = 0

	for node in nodes.values():
		for prereq_id in node.prerequisites:
			if nodes.has(prereq_id):
				nodes[prereq_id].unlocks.append(node.id)

	var roots: Array = nodes.values().filter(func(n): return n.prerequisites.is_empty())
	for root in roots:
		root.state = ResearchNode.State.AVAILABLE
		root.tier = 0

	var visited: Dictionary = {}
	var queue: Array = roots.duplicate()
	while not queue.is_empty():
		var current: ResearchNode = queue.pop_front()
		if visited.has(current.id):
			continue
		visited[current.id] = true
		for child_id in current.unlocks:
			var child: ResearchNode = nodes[child_id]
			child.tier = max(child.tier, current.tier + 1)
			queue.append(child)

	_refresh_all_availability()
	initialized = true


# ---------------------------------------------------------------------------
# Research actions
# ---------------------------------------------------------------------------

## Attempt to start researching `node_id`.
## Returns true on success, false if prerequisites / resources not met.
func start_research(node_id: String, force: bool = false) -> bool:
	if not nodes.has(node_id):
		push_warning("ResearchTree: unknown node '%s'" % node_id)
		return false

	var node: ResearchNode = nodes[node_id]

	if node.state == ResearchNode.State.UNLOCKED:
		push_warning("ResearchTree: '%s' is already unlocked." % node_id)
		return false

	if node.state == ResearchNode.State.LOCKED:
		push_warning("ResearchTree: '%s' is locked (prerequisites unmet)." % node_id)
		return false

	if not _can_afford(node) and not force:
		push_warning("ResearchTree: cannot afford '%s'." % node_id)
		return false

	# Queue it if something is already running
	if active_research != null:
		if not research_queue.has(node_id):
			research_queue.append(node_id)
		return true

	_spend_resources(node)
	active_research = node
	node.state = ResearchNode.State.RESEARCHING
	node.progress = 0.0
	node_state_changed.emit(node)
	return true


## Cancel the active research job and refund resources.
func cancel_research() -> void:
	if active_research == null:
		return
	var node := active_research
	_refund_resources(node)
	node.state = ResearchNode.State.AVAILABLE
	node.progress = 0.0
	active_research = null
	node_state_changed.emit(node)
	research_cancelled.emit(node)
	_advance_queue()


## Immediately unlock a node (cheat / debug / save-game restoration).
func force_unlock(node_id: String) -> void:
	if not nodes.has(node_id):
		return
	var node: ResearchNode = nodes[node_id]
	node.state = ResearchNode.State.UNLOCKED
	node.progress = 1.0
	node_state_changed.emit(node)
	_refresh_children_availability(node)


## Reset a node back to its computed availability state.
func reset_node(node_id: String) -> void:
	if not nodes.has(node_id):
		return
	var node: ResearchNode = nodes[node_id]
	node.progress = 0.0
	_refresh_single_availability(node)
	node_state_changed.emit(node)


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

## Call this from _process(delta) (or a timer) to advance active research.
## `research_speed` multiplies progress rate (default 1.0).
func tick(delta: float, research_speed: float = 1.0) -> void:
	if active_research == null or SolarSystem.paused:
		return

	active_research.progress += (delta * research_speed) / active_research.research_time
	active_research.progress = clampf(active_research.progress, 0.0, 1.0)

	if active_research.progress >= 1.0:
		_complete_research(active_research)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_research_node(node_id: String) -> ResearchNode:
	return nodes.get(node_id, null)

func is_unlocked(node_id: String) -> bool:
	var n = nodes.get(node_id)
	return n != null and n.state == ResearchNode.State.UNLOCKED

func is_available(node_id: String) -> bool:
	var n = nodes.get(node_id)
	return n != null and n.state == ResearchNode.State.AVAILABLE

func get_unlocked_nodes() -> Array:
	return nodes.values().filter(func(n): return n.state == ResearchNode.State.UNLOCKED)

func get_available_nodes() -> Array:
	return nodes.values().filter(func(n): return n.state == ResearchNode.State.AVAILABLE)

func get_nodes_by_tier(tier: int) -> Array:
	return nodes.values().filter(func(n): return n.tier == tier)

func get_max_tier() -> int:
	var max_t := 0
	for n in nodes.values():
		if n.tier > max_t:
			max_t = n.tier
	return max_t


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

## Returns a Dictionary that can be serialised with JSON or ConfigFile.
func save_state() -> Dictionary:
	var state_data := {}
	for id in nodes:
		var n: ResearchNode = nodes[id]
		state_data[id] = {
			"state": n.state,
			"progress": n.progress
		}
	return {
		"nodes": state_data,
		"resources": resources.duplicate(),
		"active_research": active_research.id if active_research else "",
		"research_queue": research_queue.duplicate()
	}


## Restores tree state from a previously saved Dictionary.
func load_state(saved: Dictionary) -> void:
	resources = saved.get("resources", {}).duplicate()

	var node_data: Dictionary = saved.get("nodes", {})
	for id in node_data:
		if not nodes.has(id):
			continue
		var n: ResearchNode = nodes[id]
		n.state = node_data[id].get("state", ResearchNode.State.LOCKED)
		n.progress = node_data[id].get("progress", 0.0)
		node_state_changed.emit(n)

	research_queue = saved.get("research_queue", []).duplicate()

	var active_id: String = saved.get("active_research", "")
	if active_id != "" and nodes.has(active_id):
		active_research = nodes[active_id]
	else:
		active_research = null


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _complete_research(node: ResearchNode) -> void:
	node.state = ResearchNode.State.UNLOCKED
	node.progress = 1.0
	active_research = null
	node_state_changed.emit(node)
	research_completed.emit(node)
	_refresh_children_availability(node)
	_advance_queue()


func _advance_queue() -> void:
	while not research_queue.is_empty():
		var next_id: String = research_queue.pop_front()
		if start_research(next_id):
			break


func _refresh_all_availability() -> void:
	for node in nodes.values():
		if node.state != ResearchNode.State.UNLOCKED:
			_refresh_single_availability(node)


func _refresh_children_availability(parent: ResearchNode) -> void:
	for child_id in parent.unlocks:
		if nodes.has(child_id):
			_refresh_single_availability(nodes[child_id])


func _refresh_single_availability(node: ResearchNode) -> void:
	if node.state == ResearchNode.State.UNLOCKED:
		return
	if node.state == ResearchNode.State.RESEARCHING:
		return

	var all_met := true
	for prereq_id in node.prerequisites:
		if not is_unlocked(prereq_id):
			all_met = false
			break

	node.state = ResearchNode.State.AVAILABLE if all_met else ResearchNode.State.LOCKED


func _can_afford(node: ResearchNode) -> bool:
	for resource_type in node.cost:
		var needed: float = node.cost[resource_type]
		var have: float = resources.get(resource_type, 0.0)
		if have < needed:
			return false
	return true


func _spend_resources(node: ResearchNode) -> void:
	for resource_type in node.cost:
		resources[resource_type] = resources.get(resource_type, 0.0) - node.cost[resource_type]


func _refund_resources(node: ResearchNode) -> void:
	for resource_type in node.cost:
		resources[resource_type] = resources.get(resource_type, 0.0) + node.cost[resource_type]
