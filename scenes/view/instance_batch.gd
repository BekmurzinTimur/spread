class_name InstanceBatch
extends MultiMeshInstance2D

## A MultiMesh of 1×1 quads, refilled wholesale every frame. One draw call for
## however many instances. Scale a quad through its transform.

## Floats per instance: a 2D transform (8), then a colour (4).
const STRIDE := 12

## Never culled. Godot measures a 2D MultiMesh's bounds once and keeps them, so
## real bounds go stale as instances move and the whole batch vanishes off-screen.
const BOUNDS := AABB(Vector3(-1e6, -1e6, 0.0), Vector3(2e6, 2e6, 0.0))

var _data := PackedFloat32Array()
var _count := 0


func _init(p_texture: Texture2D = null) -> void:
	texture = p_texture
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = QuadMesh.new()
	multimesh.custom_aabb = BOUNDS


## Start a frame with room for `capacity` instances.
func begin(capacity: int) -> void:
	_count = 0
	if capacity > multimesh.instance_count:
		multimesh.instance_count = nearest_po2(capacity)
		_data.resize(multimesh.instance_count * STRIDE)


func add(xform: Transform2D, color: Color) -> void:
	var o := _count * STRIDE
	_data[o] = xform.x.x
	_data[o + 1] = xform.y.x
	_data[o + 2] = 0.0
	_data[o + 3] = xform.origin.x
	_data[o + 4] = xform.x.y
	_data[o + 5] = xform.y.y
	_data[o + 6] = 0.0
	_data[o + 7] = xform.origin.y
	_data[o + 8] = color.r
	_data[o + 9] = color.g
	_data[o + 10] = color.b
	_data[o + 11] = color.a
	_count += 1


func commit() -> void:
	if _count > 0:
		multimesh.buffer = _data
	multimesh.visible_instance_count = _count


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
