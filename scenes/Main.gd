extends Node2D

## Owns the world, drives the fixed tick, routes input.

const SAVE_PATH := "user://ascension.json"

## After a stall, catch up rather than fast-forwarding forever.
const MAX_TICKS_PER_FRAME := 240

const START_ZOOM := 0.9

## How near a click has to land to count as picking a cell. Matches the hex the
## board draws.
const CLICK_RADIUS := 44.0

@onready var _camera: Camera2D = $Camera2D
@onready var _graph_view: Node2D = $Board/GraphView
@onready var _orb_layer: Node2D = $Board/OrbLayer
@onready var _splash_layer: Node2D = $Board/SplashLayer
@onready var _float_layer: Node2D = $Board/FloatingTextLayer
@onready var _hud: Control = $UI/HUD
@onready var _shop: Control = $UI/AscensionShop

## The two phases of the loop. RUNNING is a board that ticks; SHOPPING is the
## next board, built and frozen, behind the shop. Nothing else is in between, so
## a purchase always lands on the run you are about to start.
enum Phase { RUNNING, SHOPPING }

var world: World
var meta: MetaState

var phase: int = Phase.RUNNING
var paused: bool = false
var speed: int = 1

## What the last run paid, for the shop to state. Presentation only — the wallet
## itself lives on `MetaState`.
var last_run_banked: int = 0

var _accumulator: float = 0.0

## The seed the board on screen was built from. Kept so a purchase can re-place
## nodes on that same board rather than dealing a different one.
var _seed: int = 0


func _ready() -> void:
	meta = MetaStore.load_from(SAVE_PATH)
	_hud.main = self
	_shop.main = self
	_start_run(_new_seed())
	_camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	_camera.position = Vector2.ZERO


func _notification(what: int) -> void:
	# Closing the window banks what the run earned. The dig itself is lost, which
	# is the same deal ascending offers.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_bank_and_save()


func _new_seed() -> int:
	return int(Time.get_unix_time_from_system())


## Build a board. Called for the run that is starting and again for the dark one
## the shop sits in front of, so the two can never diverge.
func _start_run(seed_value: int) -> void:
	_seed = seed_value
	var graph := HexMap.build()
	HexMap.place_nodes(graph, seed_value, meta)
	world = World.new(graph, meta, seed_value)
	_accumulator = 0.0

	_graph_view.world = world
	_graph_view.camera = _camera
	_orb_layer.world = world


func _process(delta: float) -> void:
	# A shopping board is frozen, and that is separate from the player's own
	# pause — clobbering `paused` here would resume the next run paused.
	if world != null and not paused and phase == Phase.RUNNING:
		_accumulator += delta * float(speed)
		var budget := MAX_TICKS_PER_FRAME
		while _accumulator >= World.TICK_SECONDS and budget > 0:
			_accumulator -= World.TICK_SECONDS
			budget -= 1
			world.tick()
		_drain_events()

	_orb_layer.render_alpha = clampf(_accumulator / World.TICK_SECONDS, 0.0, 1.0)
	var running := not paused and phase == Phase.RUNNING
	_graph_view.advance(delta if running else 0.0)
	_splash_layer.advance(delta)
	_float_layer.advance(delta)

	# ⚠️ All four, every frame. A `Node2D` draws only when asked, and neither
	# layer's `spawn()` nor `advance()` asks — so leaving the splash and text
	# layers out here does not make them *quieter*, it makes them **invisible**:
	# they draw once, empty, on entering the tree and never again. Every splash
	# and every floating number in the game was dark for exactly this reason.
	_graph_view.queue_redraw()
	_orb_layer.queue_redraw()
	_splash_layer.queue_redraw()
	_float_layer.queue_redraw()


## The only data path out of `sim/`: drain, never subscribe. A frame can advance
## the simulation several ticks before it draws, and every event in that window
## has to survive to be shown.
func _drain_events() -> void:
	for event in world.take_delivery_events():
		var cell := world.graph.get_cell(event.cell_id)
		if cell == null:
			continue
		# Born already part-aged, by however long ago the tick was. A frame can
		# advance the simulation many ticks — routinely at speed, up to
		# MAX_TICKS_PER_FRAME after a stall — and spawning the whole batch at
		# age 0 fires a hundred landings as one flash. This is what
		# `DeliveryEvent.tick` is carried for.
		var age := float(world.tick_count - event.tick) \
			* World.TICK_SECONDS / float(speed)
		var hue := Bands.color_of(event.band)
		if event.is_crit:
			_splash_layer.spawn(cell.position, Color(1.0, 0.98, 0.9), 1.6, age)
			_float_layer.spawn("+%s x%d" % [Format.thousands(event.amount),
				World.CRIT_MULTIPLIER], Color(1.0, 0.95, 0.7), cell.position, age)
		else:
			_splash_layer.spawn(cell.position, hue, 0.7, age)
			_float_layer.spawn("+%s" % Format.thousands(event.amount),
				hue.lerp(Color.WHITE, 0.5), cell.position, age)

	for cell_id in world.take_mine_events():
		var cell := world.graph.get_cell(cell_id)
		if cell == null:
			continue
		_graph_view.pop(cell_id)
		_splash_layer.spawn(cell.position, Bands.color_of(cell.band), 1.4)
		_float_layer.spawn("\u25c6 %s" % Format.thousands(cell.cost),
			Color(0.95, 0.90, 0.70), cell.position)
		if cell.has_node():
			var type := NodeCatalog.get_type(cell.node_id)
			if type != null:
				var text := type.display_name
				if cell.is_keystone():
					text = "%s x%d" % [type.display_name, cell.node_levels]
				_float_layer.spawn(text, Color(1.0, 0.98, 0.88), cell.position)


## One board gesture: aim the lance. Everything else on screen runs itself.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := _cell_at(_camera.screen_to_world(event.position))
		_graph_view.hovered_id = over
		_hud.hovered_cell = over
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT \
				and _hud.end_run_rect.has_point(event.position):
			end_run()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_fire_ram(_cell_at(_camera.screen_to_world(event.position)))
		return

	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			paused = not paused
		KEY_1:
			speed = 1
		KEY_2:
			speed = 4
		KEY_3:
			speed = 16
		KEY_ENTER, KEY_KP_ENTER:
			if phase == Phase.SHOPPING:
				start_run()


# --- The two phases -----------------------------------------------------

## Ending a run has no key. It is a click and only a click — a stray keystroke
## should not be able to throw a board away.


func _bank_and_save() -> void:
	if world == null:
		return
	last_run_banked = world.earned
	meta.deposit(world.earned)
	world.earned = 0
	MetaStore.save_to(meta, SAVE_PATH)


## End the run in one press: bank it, deal the next board dark and frozen, and
## open the shop over it. The deposit lands before the shop draws, so the wallet
## it shows is already the one you are about to spend.
func end_run() -> void:
	_bank_and_save()
	_start_run(_new_seed())
	phase = Phase.SHOPPING
	_shop.open()


## Begin the board that has been sitting behind the shop. Every purchase is
## already on it, so there is nothing to apply here.
func start_run() -> void:
	_shop.close()
	phase = Phase.RUNNING


## Wipe the ladder: empty wallet, nothing bought. Reachable only between runs,
## so it re-deals the waiting board and leaves you in the shop.
func reset_progress() -> void:
	meta.reset()
	MetaStore.save_to(meta, SAVE_PATH)
	_start_run(_seed)


## A purchase lands on the board waiting behind the shop. Buffs re-resolve, and
## nodes are re-placed on the same seed — a newly unlocked type has to be dealt
## into the ground, and the ground was dealt before it was bought.
func buy_upgrade(key: String) -> bool:
	if not meta.buy(key):
		return false
	MetaStore.save_to(meta, SAVE_PATH)
	if world != null:
		HexMap.place_nodes(world.graph, _seed, meta)
		world.on_meta_changed()
	return true


func _fire_ram(cell_id: int) -> void:
	# The shop is a full-screen modal; a right-click over it is not an aim.
	if _shop.visible or world == null or cell_id < 0 \
			or not world.can_ram_at(cell_id):
		return
	var target: GraphCell = world.graph.cells[cell_id]
	var origin := _nearest_frontier_to(target.position)
	var damage := world.ram_damage()
	if not world.fire_ram(cell_id):
		return
	_graph_view.fire_beam(origin, target.position)
	_splash_layer.spawn(target.position, Color(1.0, 0.97, 0.85), 1.8)
	_float_layer.spawn("RAM %s" % Format.thousands(damage),
		Color(1.0, 0.97, 0.85), target.position)


## Where the shot appears to come from. Presentation only — the simulation has
## no opinion about which cell fired it.
func _nearest_frontier_to(at: Vector2) -> Vector2:
	var best := at
	var best_distance := INF
	for id in world.frontier():
		var cell: GraphCell = world.graph.cells[id]
		var distance := cell.position.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = cell.position
	return best


## The cell under a world position, or -1. Cheap enough at 1,801 cells because
## it runs on a click and on cursor motion, not per tick.
func _cell_at(at: Vector2) -> int:
	if world == null:
		return -1
	var best := -1
	var best_distance := CLICK_RADIUS * CLICK_RADIUS
	for id in world.graph.cell_ids:
		var cell: GraphCell = world.graph.cells[id]
		var distance := cell.position.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best
