extends GPUParticles3D

func _ready() -> void:
	emitting = true
	finished.connect(queue_free)

func set_burst_color(c: Color) -> void:
	var mat := draw_pass_1.material as StandardMaterial3D
	if mat:
		var dup := mat.duplicate() as StandardMaterial3D
		dup.albedo_color = c
		dup.emission = c
		draw_pass_1 = draw_pass_1.duplicate()
		draw_pass_1.material = dup
