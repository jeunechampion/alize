## Oiseau factice pour le catalogue : juste l'état et le modèle de vol lus par BirdModel.
extends Node
var pose := "plane"
var model := FlightModel.new()
var state: int:
	get:
		return Bird.State.FLYING if pose != "pose" else Bird.State.LANDED
func _process(_dt: float) -> void:
	model.flapping = pose == "battement"
	model.braking = pose == "frein"
	model.diving = false
	model.energy = 100.0
