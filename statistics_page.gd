# StatisticsPage.gd
# Godot 4.x
# Attach to a Control node.
#
# Single-page version:
# Shows all statistic sections at once in one vertical scroll view.

extends Control

const SECTION_ORDER: Array[String] = [
	"Population",
	"Survival",
	"Technology",
	"Society",
	"Economy",
	"AI",
	"Expansion",
	"Evolution",
	"Risks",
	"LongTerm"
]

const SECTION_METRICS: Dictionary = {
	"Population": [
		{"key":"current_population", "label":"Current Population", "type":"int"},
		{"key":"total_humans_ever_lived", "label":"Total Humans Ever Lived", "type":"int"},
		{"key":"projected_total_humans", "label":"Projected Total Humans", "type":"int"},
		{"key":"birth_rate", "label":"Birth Rate", "type":"float"},
		{"key":"death_rate", "label":"Death Rate", "type":"float"},
		{"key":"average_lifespan", "label":"Average Lifespan", "type":"float"},
		{"key":"fertility_rate", "label":"Fertility Rate", "type":"float"},
		{"key":"offworld_population", "label":"Off-World Population", "type":"int"},
		{"key":"uploaded_population", "label":"Uploaded Population", "type":"int"},
		{"key":"biological_population", "label":"Biological Population", "type":"int"}
	],
	"Survival": [
		{"key":"survival_1000y", "label":"Survival Probability (1,000y)", "type":"percent"},
		{"key":"survival_10000y", "label":"Survival Probability (10,000y)", "type":"percent"},
		{"key":"extinction_risk", "label":"Extinction Risk", "type":"percent"},
		{"key":"collapse_risk", "label":"Collapse Risk", "type":"percent"},
		{"key":"years_survived", "label":"Years Civilization Survived", "type":"int"},
		{"key":"collapses_survived", "label":"Collapse Events Survived", "type":"int"},
		{"key":"knowledge_preserved", "label":"Knowledge Preserved", "type":"percent"},
		{"key":"redundancy_level", "label":"Redundancy Level", "type":"percent"},
		{"key":"self_sufficiency", "label":"Self-Sufficiency", "type":"percent"},
		{"key":"infrastructure_resilience", "label":"Infrastructure Resilience", "type":"percent"},
		{"key":"centralization", "label":"Centralization", "type":"percent"}
	],
	"Technology": [
		{"key":"technology_level", "label":"Technology Level", "type":"float"},
		{"key":"energy_production", "label":"Energy Production", "type":"float"},
		{"key":"computing_power", "label":"Computing Power", "type":"float"},
		{"key":"automation_level", "label":"Automation Level", "type":"percent"},
		{"key":"research_speed", "label":"Research Speed", "type":"float"},
		{"key":"space_industry", "label":"Space Industry", "type":"percent"},
		{"key":"biotechnology_level", "label":"Biotechnology", "type":"percent"},
		{"key":"nanotechnology_level", "label":"Nanotechnology", "type":"percent"},
		{"key":"interstellar_capability", "label":"Interstellar Capability", "type":"percent"},
		{"key":"post_biological_transition", "label":"Post-Biological Transition", "type":"percent"},
		{"key":"entropy_management", "label":"Entropy Management", "type":"percent"}
	],
	"Society": [
		{"key":"happiness", "label":"Happiness", "type":"percent"},
		{"key":"inequality", "label":"Inequality", "type":"percent"},
		{"key":"stability", "label":"Stability", "type":"percent"},
		{"key":"freedom", "label":"Freedom", "type":"percent"},
		{"key":"surveillance", "label":"Surveillance", "type":"percent"},
		{"key":"cultural_unity", "label":"Cultural Unity", "type":"percent"},
		{"key":"political_engagement", "label":"Political Engagement", "type":"percent"},
		{"key":"education", "label":"Education", "type":"percent"},
		{"key":"scientific_literacy", "label":"Scientific Literacy", "type":"percent"},
		{"key":"trust_in_institutions", "label":"Trust in Institutions", "type":"percent"},
		{"key":"hyperreality_adoption", "label":"Hyperreality Adoption", "type":"percent"},
		{"key":"real_world_engagement", "label":"Real-World Engagement", "type":"percent"},
		{"key":"risk_tolerance", "label":"Risk Tolerance", "type":"percent"},
		{"key":"innovation_culture", "label":"Innovation Culture", "type":"percent"},
		{"key":"cooperation", "label":"Cooperation", "type":"percent"},
		{"key":"aggression", "label":"Aggression", "type":"percent"}
	],
	"Economy": [
		{"key":"economic_output", "label":"Economic Output", "type":"float"},
		{"key":"energy_consumption", "label":"Energy Consumption", "type":"float"},
		{"key":"resource_reserves", "label":"Resource Reserves", "type":"float"},
		{"key":"resource_depletion_rate", "label":"Resource Depletion Rate", "type":"float"},
		{"key":"automation_unemployment", "label":"Automation Unemployment", "type":"percent"},
		{"key":"industrial_capacity", "label":"Industrial Capacity", "type":"percent"},
		{"key":"supply_chain_stability", "label":"Supply Chain Stability", "type":"percent"},
		{"key":"food_production", "label":"Food Production", "type":"float"},
		{"key":"water_security", "label":"Water Security", "type":"percent"},
		{"key":"space_mining_output", "label":"Space Mining Output", "type":"float"},
		{"key":"economic_stability", "label":"Economic Stability", "type":"percent"}
	],
	"AI": [
		{"key":"ai_vs_human_intelligence", "label":"AI vs Human Intelligence", "type":"float"},
		{"key":"ai_autonomy", "label":"AI Autonomy", "type":"percent"},
		{"key":"ai_alignment", "label":"AI Alignment", "type":"percent"},
		{"key":"ai_control", "label":"AI Control", "type":"percent"},
		{"key":"ai_infrastructure_dependence", "label":"Infrastructure Dependence on AI", "type":"percent"},
		{"key":"ai_economic_control", "label":"AI Economic Control", "type":"percent"},
		{"key":"ai_governance_involvement", "label":"AI Governance Involvement", "type":"percent"},
		{"key":"superintelligence_probability", "label":"Superintelligence Emergence Probability", "type":"percent"},
		{"key":"years_until_possible_superintelligence", "label":"Years Until Possible Superintelligence", "type":"int"},
		{"key":"human_ai_integration", "label":"Human-AI Integration", "type":"percent"},
		{"key":"ai_monitoring", "label":"AI Monitoring Capability", "type":"percent"},
		{"key":"ai_containment", "label":"AI Containment Capability", "type":"percent"}
	],
	"Expansion": [
		{"key":"colony_count", "label":"Colonies", "type":"int"},
		{"key":"star_systems_settled", "label":"Star Systems Settled", "type":"int"},
		{"key":"self_sufficient_colonies", "label":"Self-Sufficient Colonies", "type":"int"},
		{"key":"interstellar_probes", "label":"Interstellar Probes", "type":"int"},
		{"key":"dyson_swarm_completion", "label":"Dyson Swarm Completion", "type":"percent"},
		{"key":"galactic_expansion_rate", "label":"Galactic Expansion Rate", "type":"float"},
		{"key":"backup_archive_sites", "label":"Backup Archive Sites", "type":"int"},
		{"key":"independent_civilizations", "label":"Independent Civilizations", "type":"int"},
		{"key":"civilization_span_ly", "label":"Civilization Span (ly)", "type":"float"},
		{"key":"max_comm_delay_years", "label":"Max Communication Delay (years)", "type":"float"}
	],
	"Evolution": [
		{"key":"trait_intelligence", "label":"Trait: Intelligence", "type":"percent"},
		{"key":"trait_cooperation", "label":"Trait: Cooperation", "type":"percent"},
		{"key":"trait_aggression", "label":"Trait: Aggression", "type":"percent"},
		{"key":"trait_conformity", "label":"Trait: Conformity", "type":"percent"},
		{"key":"trait_creativity", "label":"Trait: Creativity", "type":"percent"},
		{"key":"trait_risk_tolerance", "label":"Trait: Risk Tolerance", "type":"percent"},
		{"key":"trait_empathy", "label":"Trait: Empathy", "type":"percent"},
		{"key":"trait_longevity", "label":"Trait: Longevity", "type":"percent"},
		{"key":"trait_fertility", "label":"Trait: Fertility", "type":"percent"},
		{"key":"trait_adaptability", "label":"Trait: Adaptability", "type":"percent"},
		{"key":"trait_curiosity", "label":"Trait: Curiosity", "type":"percent"},
		{"key":"trait_independence", "label":"Trait: Independence", "type":"percent"},
		{"key":"trait_obedience", "label":"Trait: Obedience", "type":"percent"},
		{"key":"trait_hyperreality_preference", "label":"Trait: Hyperreality Preference", "type":"percent"},
		{"key":"trait_tech_affinity", "label":"Trait: Tech Affinity", "type":"percent"},
		{"key":"trait_stress_tolerance", "label":"Trait: Stress Tolerance", "type":"percent"},
		{"key":"trait_global_identity", "label":"Trait: Global Identity", "type":"percent"}
	],
	"Risks": [
		{"key":"risk_climate", "label":"Climate Risk", "type":"percent"},
		{"key":"risk_resource_depletion", "label":"Resource Depletion Risk", "type":"percent"},
		{"key":"risk_war", "label":"War Risk", "type":"percent"},
		{"key":"risk_inequality", "label":"Inequality Risk", "type":"percent"},
		{"key":"risk_political_instability", "label":"Political Instability Risk", "type":"percent"},
		{"key":"risk_ai_takeover", "label":"AI Takeover Risk", "type":"percent"},
		{"key":"risk_biotech", "label":"Biotechnology Risk", "type":"percent"},
		{"key":"risk_nanotech", "label":"Nanotechnology Risk", "type":"percent"},
		{"key":"risk_economic_collapse", "label":"Economic Collapse Risk", "type":"percent"},
		{"key":"risk_pandemic", "label":"Pandemic Risk", "type":"percent"},
		{"key":"risk_infrastructure", "label":"Infrastructure Collapse Risk", "type":"percent"},
		{"key":"risk_stagnation", "label":"Hyperreality / Stagnation Risk", "type":"percent"},
		{"key":"risk_colony_rebellion", "label":"Colony Rebellion Risk", "type":"percent"},
		{"key":"risk_external_threat", "label":"External Threat Risk", "type":"percent"},
		{"key":"risk_entropy", "label":"Entropy Risk", "type":"percent"},
		{"key":"collapse_pressure", "label":"Collapse Pressure", "type":"percent"},
		{"key":"existential_risk", "label":"Total Existential Risk", "type":"percent"}
	],
	"LongTerm": [
		{"key":"total_conscious_minds_created", "label":"Total Conscious Minds Created", "type":"int"},
		{"key":"total_knowledge_stored", "label":"Total Knowledge Stored", "type":"float"},
		{"key":"civilization_lifespan_projection", "label":"Projected Civilization Lifespan", "type":"int"},
		{"key":"stars_colonized", "label":"Stars Colonized", "type":"int"},
		{"key":"information_preserved", "label":"Information Preserved", "type":"percent"},
		{"key":"descendant_civilizations", "label":"Descendant Civilizations", "type":"int"},
		{"key":"intelligence_spread", "label":"Intelligence Spread Through Galaxy", "type":"percent"},
		{"key":"survival_1m_years", "label":"Survival Probability (1M years)", "type":"percent"},
		{"key":"survival_heat_death", "label":"Survival Probability to Heat Death", "type":"percent"},
		{"key":"total_suffering", "label":"Total Suffering Index", "type":"float"},
		{"key":"total_happiness", "label":"Total Happiness Index", "type":"float"},
		{"key":"civilization_impact_score", "label":"Civilization Impact Score", "type":"float"}
	]
}

var stats: Dictionary = {}
var metric_widgets: Dictionary = {}
var summary_value_labels: Dictionary = {}

var year_label: Label = null
var main_scroll: ScrollContainer = null
var sections_root: VBoxContainer = null

func _ready() -> void:
	_ensure_base_layout()
	_build_sections()
	load_demo_stats()
	refresh()

func _ensure_base_layout() -> void:
	var margin: MarginContainer = get_node_or_null("MarginContainer") as MarginContainer
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "MarginContainer"
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(margin)

	var root_vbox: VBoxContainer = margin.get_node_or_null("VBoxContainer") as VBoxContainer
	if root_vbox == null:
		root_vbox = VBoxContainer.new()
		root_vbox.name = "VBoxContainer"
		root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_vbox.add_theme_constant_override("separation", 12)
		margin.add_child(root_vbox)

	var header: HBoxContainer = root_vbox.get_node_or_null("HeaderBar") as HBoxContainer
	if header == null:
		header = HBoxContainer.new()
		header.name = "HeaderBar"
		root_vbox.add_child(header)

	var title: Label = header.get_node_or_null("TitleLabel") as Label
	if title == null:
		title = Label.new()
		title.name = "TitleLabel"
		title.text = "Civilization Statistics"
		title.add_theme_font_size_override("font_size", 28)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)

	year_label = header.get_node_or_null("YearLabel") as Label
	if year_label == null:
		year_label = Label.new()
		year_label.name = "YearLabel"
		year_label.text = "Year: 2026"
		year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(year_label)

	var summary_panel: PanelContainer = root_vbox.get_node_or_null("SummaryPanel") as PanelContainer
	if summary_panel == null:
		summary_panel = PanelContainer.new()
		summary_panel.name = "SummaryPanel"
		root_vbox.add_child(summary_panel)

	var summary_grid: GridContainer = summary_panel.get_node_or_null("SummaryGrid") as GridContainer
	if summary_grid == null:
		summary_grid = GridContainer.new()
		summary_grid.name = "SummaryGrid"
		summary_grid.columns = 4
		summary_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_panel.add_child(summary_grid)

	_build_summary(summary_grid)

	main_scroll = root_vbox.get_node_or_null("MainScroll") as ScrollContainer
	if main_scroll == null:
		main_scroll = ScrollContainer.new()
		main_scroll.name = "MainScroll"
		main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root_vbox.add_child(main_scroll)

	sections_root = main_scroll.get_node_or_null("SectionsRoot") as VBoxContainer
	if sections_root == null:
		sections_root = VBoxContainer.new()
		sections_root.name = "SectionsRoot"
		sections_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sections_root.add_theme_constant_override("separation", 16)
		main_scroll.add_child(sections_root)

func _build_summary(summary_grid: GridContainer) -> void:
	var summary_metrics: Array[Dictionary] = [
		{"key":"current_population", "label":"Population"},
		{"key":"survival_10000y", "label":"10k Survival"},
		{"key":"collapse_pressure", "label":"Collapse Pressure"},
		{"key":"ai_autonomy", "label":"AI Autonomy"},
		{"key":"hyperreality_adoption", "label":"Hyperreality"},
		{"key":"colony_count", "label":"Colonies"},
		{"key":"existential_risk", "label":"Existential Risk"},
		{"key":"civilization_impact_score", "label":"Impact Score"}
	]

	for child: Node in summary_grid.get_children():
		child.queue_free()

	summary_value_labels.clear()

	for entry: Dictionary in summary_metrics:
		var card: PanelContainer = PanelContainer.new()
		card.custom_minimum_size = Vector2(180, 70)
		summary_grid.add_child(card)

		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		var name_label: Label = Label.new()
		name_label.text = str(entry["label"])
		name_label.modulate = Color(0.75, 0.78, 0.85)
		box.add_child(name_label)

		var value_label: Label = Label.new()
		value_label.text = "-"
		value_label.add_theme_font_size_override("font_size", 22)
		box.add_child(value_label)

		summary_value_labels[str(entry["key"])] = value_label

func _build_sections() -> void:
	for child: Node in sections_root.get_children():
		child.queue_free()

	metric_widgets.clear()

	for section_name: String in SECTION_ORDER:
		var section_panel: PanelContainer = PanelContainer.new()
		section_panel.custom_minimum_size = Vector2(0, 0)
		sections_root.add_child(section_panel)

		var section_box: VBoxContainer = VBoxContainer.new()
		section_box.add_theme_constant_override("separation", 8)
		section_panel.add_child(section_box)

		var title: Label = Label.new()
		title.text = section_name
		title.add_theme_font_size_override("font_size", 22)
		section_box.add_child(title)

		var grid: GridContainer = GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 8)
		section_box.add_child(grid)

		metric_widgets[section_name] = {}

		var metrics_variant: Variant = SECTION_METRICS.get(section_name, [])
		var metrics: Array = metrics_variant as Array

		for metric_variant: Variant in metrics:
			var metric: Dictionary = metric_variant as Dictionary
			var label_text: String = str(metric["label"])
			var metric_type: String = str(metric["type"])
			var row: Dictionary = _create_metric_row(label_text, metric_type)
			grid.add_child(row["root"] as Control)
			(metric_widgets[section_name] as Dictionary)[str(metric["key"])] = row

func _create_metric_row(metric_label: String, metric_type: String) -> Dictionary:
	var root: PanelContainer = PanelContainer.new()
	root.custom_minimum_size = Vector2(320, 60)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	root.add_child(outer)

	var top: HBoxContainer = HBoxContainer.new()
	outer.add_child(top)

	var label: Label = Label.new()
	label.text = metric_label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(label)

	var value: Label = Label.new()
	value.text = "-"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(140, 0)
	top.add_child(value)

	var bar: ProgressBar = null
	if metric_type == "percent":
		bar = ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		outer.add_child(bar)

	return {
		"root": root,
		"label": label,
		"value": value,
		"bar": bar,
		"type": metric_type
	}

func set_stats(new_stats: Dictionary) -> void:
	stats = new_stats.duplicate(true)
	refresh()

func refresh() -> void:
	if year_label != null:
		var year_value: int = int(stats.get("year", 2026))
		year_label.text = "Year: %s" % str(year_value)

	for section_name: String in SECTION_ORDER:
		var section_widgets_variant: Variant = metric_widgets.get(section_name, {})
		var section_widgets: Dictionary = section_widgets_variant as Dictionary

		var metrics_variant: Variant = SECTION_METRICS.get(section_name, [])
		var metrics: Array = metrics_variant as Array

		for metric_variant: Variant in metrics:
			var metric: Dictionary = metric_variant as Dictionary
			var key: String = str(metric["key"])

			if not section_widgets.has(key):
				continue

			var widget_variant: Variant = section_widgets[key]
			var widget: Dictionary = widget_variant as Dictionary

			var value: Variant = stats.get(key, 0)
			var widget_type: String = str(widget["type"])
			var formatted: String = _format_value(value, widget_type)

			var value_label: Label = widget["value"] as Label
			value_label.text = formatted

			var bar: ProgressBar = widget["bar"] as ProgressBar
			if bar != null:
				var numeric_value: float = float(value)
				if numeric_value <= 1.0:
					numeric_value *= 100.0
				bar.value = clampf(numeric_value, 0.0, 100.0)

	for key_variant: Variant in summary_value_labels.keys():
		var key: String = str(key_variant)
		var label_variant: Variant = summary_value_labels[key]
		var label: Label = label_variant as Label
		var summary_value: Variant = stats.get(key, 0)
		label.text = _format_summary_value(key, summary_value)

func _format_summary_value(key: String, value: Variant) -> String:
	match key:
		"survival_10000y", "collapse_pressure", "ai_autonomy", "hyperreality_adoption", "existential_risk":
			return _format_percent(float(value))
		"current_population":
			return _format_int(int(value))
		"colony_count":
			return str(int(value))
		"civilization_impact_score":
			return _format_float(float(value), 1)
		_:
			return str(value)

func _format_value(value: Variant, value_type: String) -> String:
	match value_type:
		"int":
			return _format_int(int(value))
		"float":
			return _format_float(float(value), 2)
		"percent":
			return _format_percent(float(value))
		_:
			return str(value)

func _format_percent(value: float) -> String:
	var f: float = value
	if f <= 1.0:
		f *= 100.0
	return "%.1f%%" % f

func _format_float(value: float, decimals: int = 2) -> String:
	if absf(value) >= 1_000_000_000.0:
		return "%.*fB" % [decimals, value / 1_000_000_000.0]
	if absf(value) >= 1_000_000.0:
		return "%.*fM" % [decimals, value / 1_000_000.0]
	if absf(value) >= 1_000.0:
		return "%.*fK" % [decimals, value / 1_000.0]
	return "%.*f" % [decimals, value]

func _format_int(value: int) -> String:
	var abs_value: int = absi(value)
	if abs_value >= 1_000_000_000_000:
		return "%.2fT" % (float(value) / 1_000_000_000_000.0)
	if abs_value >= 1_000_000_000:
		return "%.2fB" % (float(value) / 1_000_000_000.0)
	if abs_value >= 1_000_000:
		return "%.2fM" % (float(value) / 1_000_000.0)
	if abs_value >= 1_000:
		return "%.2fK" % (float(value) / 1_000.0)
	return str(value)

func load_demo_stats() -> void:
	stats = {
		"year": 2486,

		"current_population": 17400000000,
		"total_humans_ever_lived": 246000000000,
		"projected_total_humans": 3200000000000,
		"birth_rate": 1.82,
		"death_rate": 0.94,
		"average_lifespan": 113.4,
		"fertility_rate": 1.76,
		"offworld_population": 2400000000,
		"uploaded_population": 560000000,
		"biological_population": 16840000000,

		"survival_1000y": 0.84,
		"survival_10000y": 0.53,
		"extinction_risk": 0.11,
		"collapse_risk": 0.28,
		"years_survived": 460,
		"collapses_survived": 2,
		"knowledge_preserved": 0.88,
		"redundancy_level": 0.61,
		"self_sufficiency": 0.58,
		"infrastructure_resilience": 0.67,
		"centralization": 0.72,

		"technology_level": 8.6,
		"energy_production": 1840000000.0,
		"computing_power": 9300000000000.0,
		"automation_level": 0.79,
		"research_speed": 4.8,
		"space_industry": 0.49,
		"biotechnology_level": 0.74,
		"nanotechnology_level": 0.31,
		"interstellar_capability": 0.08,
		"post_biological_transition": 0.17,
		"entropy_management": 0.00,

		"happiness": 0.81,
		"inequality": 0.42,
		"stability": 0.69,
		"freedom": 0.54,
		"surveillance": 0.71,
		"cultural_unity": 0.63,
		"political_engagement": 0.38,
		"education": 0.87,
		"scientific_literacy": 0.76,
		"trust_in_institutions": 0.44,
		"hyperreality_adoption": 0.58,
		"real_world_engagement": 0.39,
		"risk_tolerance": 0.47,
		"innovation_culture": 0.65,
		"cooperation": 0.59,
		"aggression": 0.28,

		"economic_output": 1250000000000000.0,
		"energy_consumption": 1180000000.0,
		"resource_reserves": 920000000000.0,
		"resource_depletion_rate": 4200000.0,
		"automation_unemployment": 0.26,
		"industrial_capacity": 0.73,
		"supply_chain_stability": 0.66,
		"food_production": 21000000000.0,
		"water_security": 0.78,
		"space_mining_output": 1400000000.0,
		"economic_stability": 0.62,

		"ai_vs_human_intelligence": 14.7,
		"ai_autonomy": 0.64,
		"ai_alignment": 0.56,
		"ai_control": 0.48,
		"ai_infrastructure_dependence": 0.77,
		"ai_economic_control": 0.58,
		"ai_governance_involvement": 0.43,
		"superintelligence_probability": 0.37,
		"years_until_possible_superintelligence": 34,
		"human_ai_integration": 0.35,
		"ai_monitoring": 0.51,
		"ai_containment": 0.29,

		"colony_count": 18,
		"star_systems_settled": 1,
		"self_sufficient_colonies": 6,
		"interstellar_probes": 14,
		"dyson_swarm_completion": 0.12,
		"galactic_expansion_rate": 0.03,
		"backup_archive_sites": 11,
		"independent_civilizations": 3,
		"civilization_span_ly": 3.2,
		"max_comm_delay_years": 1.6,

		"trait_intelligence": 0.63,
		"trait_cooperation": 0.58,
		"trait_aggression": 0.31,
		"trait_conformity": 0.49,
		"trait_creativity": 0.61,
		"trait_risk_tolerance": 0.45,
		"trait_empathy": 0.55,
		"trait_longevity": 0.68,
		"trait_fertility": 0.36,
		"trait_adaptability": 0.57,
		"trait_curiosity": 0.60,
		"trait_independence": 0.47,
		"trait_obedience": 0.52,
		"trait_hyperreality_preference": 0.54,
		"trait_tech_affinity": 0.73,
		"trait_stress_tolerance": 0.46,
		"trait_global_identity": 0.62,

		"risk_climate": 0.24,
		"risk_resource_depletion": 0.43,
		"risk_war": 0.19,
		"risk_inequality": 0.37,
		"risk_political_instability": 0.33,
		"risk_ai_takeover": 0.29,
		"risk_biotech": 0.21,
		"risk_nanotech": 0.14,
		"risk_economic_collapse": 0.31,
		"risk_pandemic": 0.17,
		"risk_infrastructure": 0.27,
		"risk_stagnation": 0.46,
		"risk_colony_rebellion": 0.22,
		"risk_external_threat": 0.06,
		"risk_entropy": 0.00,
		"collapse_pressure": 0.57,
		"existential_risk": 0.34,

		"total_conscious_minds_created": 310000000000,
		"total_knowledge_stored": 8200000000000.0,
		"civilization_lifespan_projection": 14300,
		"stars_colonized": 1,
		"information_preserved": 0.88,
		"descendant_civilizations": 4,
		"intelligence_spread": 0.03,
		"survival_1m_years": 0.09,
		"survival_heat_death": 0.0001,
		"total_suffering": 42.7,
		"total_happiness": 71.2,
		"civilization_impact_score": 183.6
	}

func update_stat(key: String, value: Variant) -> void:
	stats[key] = value
	refresh()
