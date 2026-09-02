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

## Emitted whenever the queue array changes (add / remove / advance).
signal queue_changed

## Emitted when research is paused or resumed by the player.
signal research_pause_changed(paused: bool)

## All nodes keyed by their id.
var nodes: Dictionary = {}  # id -> ResearchNode

## The node currently being researched (null if idle).
var active_research: ResearchNode = null

## When true the active job is HELD: progress is frozen (but kept), and the queue does not
## advance, until the player resumes.  Distinct from cancelling — nothing is refunded or reset.
var research_paused: bool = false

## Optional: allow queuing multiple research jobs.
var research_queue: Array = []

## Resources available to spend, e.g. {"science": 100, "gold": 200}
var resources: Dictionary = {}

## Aggregated active boosts from all unlocked nodes.
var active_boosts: Dictionary = {}

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

## Begin `node_id`, or add it to the queue when the bench is busy or its prerequisites are
## still pending.  Returns false only for an unknown node, one already unlocked, or a locked
## one whose prerequisites are not even scheduled — a click that gets past those always ends
## with the project either running or planned.
func start_research(node_id: String) -> bool:
	if not nodes.has(node_id):
		push_warning("ResearchTree: unknown node '%s'" % node_id)
		return false

	var node: ResearchNode = nodes[node_id]

	if node.state == ResearchNode.State.UNLOCKED:
		push_warning("ResearchTree: '%s' is already unlocked." % node_id)
		return false

	# A LOCKED node may still be QUEUED, as long as everything it depends on is already lined
	# up ahead of it — that lets the player plan a whole branch in one go instead of coming back
	# after every step.  It just can't BEGIN yet, so it always goes to the queue below.
	var locked: bool = node.state == ResearchNode.State.LOCKED
	if locked and not _prereqs_scheduled(node):
		push_warning("ResearchTree: '%s' is locked (prerequisites unmet)." % node_id)
		return false

	# A project BEGINS only if nothing else is running, its prerequisites are already met, and
	# the opening cost can be paid.  Anything else is QUEUED — including a project the grid
	# cannot currently afford, which is planned now and started when the power is there.
	#
	# Queueing must never fail where can_queue() said yes.  It used to: can_queue() says nothing
	# about resources, so the UI enabled "Add to Queue", then this returned false on the
	# affordability check and the node silently never arrived — pressing the button did
	# visibly nothing, which is exactly what it looked like.
	# Research costs science and nothing else, and science is poured in over time by tick() —
	# so there is no up-front bill to pay and nothing that can refuse a project.  A node begins
	# the moment the bench is free and its prerequisites are met; otherwise it is planned.
	var can_begin_now: bool = active_research == null and not locked
	if not can_begin_now:
		if not research_queue.has(node_id):
			research_queue.append(node_id)
			queue_changed.emit()
		return true

	active_research = node
	node.state = ResearchNode.State.RESEARCHING
	node.progress = 0.0
	node_state_changed.emit(node)
	return true


## Hold or resume the active research job WITHOUT losing progress (unlike cancel_research,
## which refunds and resets to zero).  Progress persists across saves regardless.
func set_research_paused(paused: bool) -> void:
	if research_paused == paused:
		return
	research_paused = paused
	research_pause_changed.emit(research_paused)

## Flip the pause state; returns the new value.
func toggle_research_paused() -> bool:
	set_research_paused(not research_paused)
	return research_paused


## Cancel the active research job.  Nothing is refunded because nothing was charged up front:
## the science already poured in is simply lost, which is what makes cancelling a real decision
## rather than a free reroll.
func cancel_research() -> void:
	if active_research == null:
		return
	var node := active_research
	node.state = ResearchNode.State.AVAILABLE
	node.progress = 0.0
	active_research = null
	set_research_paused(false)   # nothing active to hold
	node_state_changed.emit(node)
	research_cancelled.emit(node)
	# Anything queued behind this that was counting on it is no longer reachable.
	_drop_orphaned_queue_entries()
	_advance_queue()


## Remove a node from the queue (no-op if not queued).
func remove_from_queue(node_id: String) -> void:
	if not research_queue.has(node_id):
		return
	research_queue.erase(node_id)
	_drop_orphaned_queue_entries()
	queue_changed.emit()


## Every prerequisite of `node` is either already unlocked, being researched now, or queued
## ahead of it — i.e. the node has a path to actually starting.
func _prereqs_scheduled(node: ResearchNode) -> bool:
	for pre_v: Variant in node.prerequisites:
		var pre_id: String = pre_v as String
		var pre: ResearchNode = nodes.get(pre_id)
		if pre == null:
			continue
		if pre.state == ResearchNode.State.UNLOCKED or pre.state == ResearchNode.State.RESEARCHING or research_queue.has(pre_id):
			continue
		return false
	return true


## True when `node_id` could be ADDED to the queue right now.  Looser than "available": a locked
## node qualifies as long as its prerequisites are scheduled.
func can_queue(node_id: String) -> bool:
	var node: ResearchNode = nodes.get(node_id)
	if node == null:
		return false
	if node.state == ResearchNode.State.UNLOCKED or node.state == ResearchNode.State.RESEARCHING:
		return false
	if research_queue.has(node_id):
		return false
	return _prereqs_scheduled(node)


## Drop any queued node whose prerequisites are no longer scheduled.  Pulling one step out of a
## planned branch takes everything that was relying on it with it, rather than leaving entries
## stranded that could never start.  Loops until stable, so removing the root of a chain clears
## the whole chain rather than just its first dependent.
func _drop_orphaned_queue_entries() -> void:
	var changed: bool = true
	while changed:
		changed = false
		for id: String in research_queue.duplicate():
			var n: ResearchNode = nodes.get(id)
			if n != null and not _prereqs_scheduled(n):
				research_queue.erase(id)
				changed = true


## Immediately unlock a node (cheat / debug / save-game restoration).
func force_unlock(node_id: String) -> void:
	if not nodes.has(node_id):
		return
	var node: ResearchNode = nodes[node_id]
	node.state = ResearchNode.State.UNLOCKED
	node.progress = 1.0
	node_state_changed.emit(node)
	_refresh_children_availability(node)
	_recompute_boosts()


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
	if active_research == null or SolarSystem.paused or research_paused:
		return

	# A project advances exactly as fast as the civilisation can FILL ITS SCIENCE REQUIREMENT:
	# every point of science banked is poured into the active node until the requirement is met.
	# Nothing is on a wall clock — double your research output and everything finishes twice as
	# fast; let it collapse and progress simply stalls where it stands.
	var need: float = float(active_research.cost.get("science", 0.0))
	if need <= 0.0:
		_complete_research(active_research)
		return
	var pool: float = float(resources.get("science", 0.0))
	if pool <= 0.0:
		return
	# research_speed makes each point of science count for more, rather than adding time.
	var effective_speed: float = maxf(0.01, research_speed * (1.0 + get_boost("research_speed")))
	var remaining_frac: float = 1.0 - active_research.progress
	var gained: float = minf(pool * effective_speed / need, remaining_frac)
	resources["science"] = maxf(0.0, pool - (gained * need) / effective_speed)
	active_research.progress = clampf(active_research.progress + gained, 0.0, 1.0)

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
		"research_paused": research_paused,
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

	# A held research job stays held after loading (only meaningful with an active job).
	research_paused = bool(saved.get("research_paused", false)) and active_research != null
	research_pause_changed.emit(research_paused)

	_recompute_boosts()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _complete_research(node: ResearchNode) -> void:
	node.state = ResearchNode.State.UNLOCKED
	node.progress = 1.0
	active_research = null
	set_research_paused(false)   # job done; the next queued one starts running, not held
	node_state_changed.emit(node)
	research_completed.emit(node)
	_refresh_children_availability(node)
	_recompute_boosts()
	_advance_queue()


## Start the first queued project that can actually BEGIN.  Entries whose prerequisites are
## still pending are left in place — popping them blindly would either drop them or bounce them
## straight back to the end of the queue, and nothing would ever run.
func _advance_queue() -> void:
	# Candidates already attempted this pass, so a project that cannot start is tried once and
	# then left alone instead of being picked forever.
	var tried: Dictionary = {}
	while true:
		var idx: int = -1
		for i in range(research_queue.size()):
			var qid: String = str(research_queue[i])
			if tried.has(qid):
				continue
			var n: ResearchNode = nodes.get(qid)
			if n != null and n.state != ResearchNode.State.LOCKED:
				idx = i
				break
		if idx == -1:
			break                       # everything left is still waiting on a prerequisite
		var next_id: String = str(research_queue[idx])
		tried[next_id] = true
		research_queue.remove_at(idx)
		start_research(next_id)
		if active_research != null:
			break                       # it began; the queue moves on
		# It could not begin — it is still PLANNED, so put it back exactly where it was.
		# start_research may have re-appended it at the tail; take that out first so the
		# player's ordering survives a project that simply could not afford to start.
		research_queue.erase(next_id)
		research_queue.insert(mini(idx, research_queue.size()), next_id)
	queue_changed.emit()


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

	var old_state: ResearchNode.State = node.state
	var all_met := true
	for prereq_id in node.prerequisites:
		if not is_unlocked(prereq_id):
			all_met = false
			break

	node.state = ResearchNode.State.AVAILABLE if all_met else ResearchNode.State.LOCKED
	if node.state != old_state:
		node_state_changed.emit(node)


func _recompute_boosts() -> void:
	active_boosts.clear()
	for n_v: Variant in nodes.values():
		var n: ResearchNode = n_v as ResearchNode
		if n.state != ResearchNode.State.UNLOCKED:
			continue
		for boost_type_v: Variant in n.boosts.keys():
			var boost_type: String = boost_type_v as String
			active_boosts[boost_type] = active_boosts.get(boost_type, 0.0) + float(n.boosts[boost_type])


## Returns the total additive bonus for a boost type (0.0 if none active).
func get_boost(boost_type: String) -> float:
	return float(active_boosts.get(boost_type, 0.0))
