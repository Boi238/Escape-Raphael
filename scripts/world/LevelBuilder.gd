extends Node3D
## LevelBuilder
##
## Builds the entire house greybox (basement + upper floor) at runtime from
## data/level_data.json. Nothing here is hand-placed in the .tscn - every
## wall, floor, ceiling and the basement->upper stairwell ramp is generated
## from that data file, so the whole layout can be tweaked by editing JSON
## instead of hunting through scene nodes.
##
## Coordinate convention used by the data file:
##   -Z = "north" (deeper into the house, away from where the player wakes up)
##   +X = "east"
##   Y  = up. Basement floor is Y=0, upper floor is Y=3.3.

const DATA_PATH := "res://data/level_data.json"
const UPPER_FLOOR_Y := 3.0  # boxes at/above this Y are treated as "upstairs" for material tinting

var rooms: Array = []
var spawns: Dictionary = {}

# Materials - basement is damp/cold, upstairs is a warmer (but still grim) tone.
var mat_wall_basement := _make_mat(Color(0.16, 0.17, 0.19), 0.95)
var mat_floor_basement := _make_mat(Color(0.11, 0.12, 0.13), 0.98)
var mat_ceiling_basement := _make_mat(Color(0.08, 0.08, 0.09), 0.98)
var mat_wall_upper := _make_mat(Color(0.24, 0.20, 0.17), 0.9)
var mat_floor_upper := _make_mat(Color(0.18, 0.15, 0.12), 0.92)
var mat_ceiling_upper := _make_mat(Color(0.14, 0.12, 0.10), 0.96)
var mat_ramp := _make_mat(Color(0.15, 0.14, 0.13), 0.95)

func _make_mat(albedo: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = 0.0
	return m

func _ready() -> void:
	var data := _load_data()
	if data.is_empty():
		push_error("LevelBuilder: failed to load %s - level will be empty." % DATA_PATH)
		return
	rooms = data.get("rooms", [])
	spawns = data.get("spawns", {})

	var boxes: Array = data.get("boxes", [])
	for box in boxes:
		_build_box(box)

	_place_spawn_markers()

func _load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		return {}
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _build_box(box: Dictionary) -> void:
	var type: String = box.get("type", "wall")
	if type == "ramp":
		_build_ramp(box)
		return

	var pos: Array = box["pos"]
	var size: Array = box["size"]
	var position := Vector3(pos[0], pos[1], pos[2])
	var extents := Vector3(size[0], size[1], size[2])

	var body := StaticBody3D.new()
	body.name = "%s_%s" % [type, box.get("note", "").replace(" ", "_")]
	body.position = position
	add_child(body)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = extents
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = _material_for(type, position.y)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extents
	col.shape = shape
	body.add_child(col)

func _material_for(type: String, world_y: float) -> StandardMaterial3D:
	var upstairs := world_y >= UPPER_FLOOR_Y
	match type:
		"wall":
			return mat_wall_upper if upstairs else mat_wall_basement
		"floor":
			return mat_floor_upper if upstairs else mat_floor_basement
		"ceiling":
			return mat_ceiling_upper if upstairs else mat_ceiling_basement
		_:
			return mat_wall_basement

func _build_ramp(box: Dictionary) -> void:
	var b: Array = box["bottom"]
	var t: Array = box["top"]
	var bottom := Vector3(b[0], b[1], b[2])
	var top := Vector3(t[0], t[1], t[2])
	var width: float = box.get("width", 3.0)
	var thickness: float = box.get("thickness", 0.3)

	var mid := (bottom + top) / 2.0
	# Extended past the true bottom/top points on purpose: a ramp box
	# sized to end exactly where the flat basement/upper floors begin can
	# leave a razor-thin seam or lip between the two surfaces (rounding,
	# or the ramp's tilted thickness not projecting to exactly y=0/y=top
	# at the very edge). CharacterBody3D doesn't auto-step over ledges,
	# so a seam that's invisible on the mesh can still stop the player
	# cold. Extending length symmetrically overlaps ~0.5m into each
	# floor slab, guaranteeing continuous walkable collision.
	const RAMP_OVERLAP := 1.0
	var length := bottom.distance_to(top) + RAMP_OVERLAP

	var body := StaticBody3D.new()
	body.name = "ramp_basement_to_upper"
	body.collision_layer = 1  # "world" - matches walls/floors/ceilings
	body.collision_mask = 0
	add_child(body)
	body.global_position = mid
	# Orient so the ramp's local -Z axis points from mid toward "top". This
	# avoids hand-computing a rotation angle/sign - look_at does it correctly
	# for any incline as long as it isn't perfectly vertical.
	body.look_at(top, Vector3.UP)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, thickness, length)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = mat_ramp
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	col.shape = shape
	body.add_child(col)

func _place_spawn_markers() -> void:
	var markers_root := Node3D.new()
	markers_root.name = "Spawns"
	add_child(markers_root)

	for key in spawns.keys():
		var v: Array = spawns[key]
		var marker := Marker3D.new()
		marker.name = key
		marker.position = Vector3(v[0], v[1], v[2])
		markers_root.add_child(marker)

## Convenience lookup used by other systems (player spawn, monster AI, etc.)
## once they exist. Returns Vector3.ZERO if the key isn't present.
func get_spawn(key: String) -> Vector3:
	var markers_root := get_node_or_null("Spawns")
	if markers_root == null:
		return Vector3.ZERO
	var marker := markers_root.get_node_or_null(key)
	if marker == null:
		return Vector3.ZERO
	return marker.position
