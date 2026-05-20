extends HBoxContainer

func hide_all() -> void:
	$planet_buttons_container.hide()
	$research_tree.hide()

func _on_planets_pressed() -> void:
	hide_all()
	$planet_buttons_container.show()


func _on_research_pressed() -> void:
	hide_all()
	$research_tree.show()
