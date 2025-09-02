extends Control

@export var air: PravdaSempaiAir
@export var engine_powerText: Label
@export var speedText: Label 

func _process(delta):
	if air:
		var throttle = "%d%%" % air.throttle_percentage
		engine_powerText.text = "Газ: " + throttle
		
		var speed = "%d км/ч" % air.current_speed
		speedText.text = "Скорость: " + speed
