class_name InstanceBatch
extends RefCounted

## Shared pieces for the MultiMesh layers.

## Never culled. Godot measures a 2D MultiMesh's bounds once and keeps them, so
## real bounds go stale as instances move and the whole batch vanishes off-screen.
const BOUNDS := AABB(Vector3(-1e6, -1e6, 0.0), Vector3(2e6, 2e6, 0.0))


## A white radial disc: `alphas[i]` at `offsets[i]`, centre 0 to rim 1.
static func disc(offsets: PackedFloat32Array, alphas: PackedFloat32Array) -> GradientTexture2D:
	var colors := PackedColorArray()
	for alpha in alphas:
		colors.append(Color(1.0, 1.0, 1.0, alpha))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
