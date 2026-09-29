extends RefCounted
## The one save slot (phase 10): the whole run in user://run.save, written on
## quit, on going back to the title and every few minutes of play, and read by
## Continue. A lost run's save is erased; a won one stays.
##
## The file: a small header (for the title screen), then the engine's state
## (sim.save_state, compressed) and the game's (every variable in GAME_VARS and
## every building's own, compressed). Buildings and packets are stored by value,
## references to buildings by id, so a loaded game has the same objects wired the
## same way. Caches (the network's routes, the hazard scan's lists, light) are
## rebuilt after loading.

const Building = preload("res://scripts/building.gd")

const PATH := "user://run.save"
const MAGIC := 0x43525553           # "CRUS"
const VERSION := 1
const AUTOSAVE_S := 300.0           # seconds of play between autosaves

## What the game node keeps that a run needs back. Everything else is a cache
## rebuilt on load, the camera, or the player's hand (tool, selection).
const GAME_VARS := [
	"info", "seed_value", "stock", "packets", "spring_tops", "dispatch_wait", "next_id", "next_order",
	"send_log", "spout_rr", "spring_acc", "power_made", "power_used", "used_acc",
	"link_hp", "broken_links", "link_fixes", "link_ends", "damaged", "fallers", "fliers", "crushed",
	"body_seen", "body_seen_tick", "scan_stale",
	"game_time", "ticks", "won", "carry_on", "run_lost", "lost_cause", "buildings_lost", "cells_drilled",
	"milestones", "firsts", "deepest", "hub_fix_t", "hub_warned",
	"researched", "levels", "tech_power", "tech_mats", "current_tech", "tiers_open", "research_rate", "research_acc",
	"cstate", "c_delivered", "c_inflight", "c_tokens", "c_last_packet", "c_draining", "c_power", "c_powered_t",
	"c_starved", "tremor_timer", "tremor_left", "cave_cells", "cave_t", "crucible_linked_once",
	"alerts", "seen_kinds", "seen_mats", "pause_on_breach",
	"known", "vis", "seen", "sense", "plans", "next_line",
	"cam_y", "cam_target", "cam_x", "cam_x_target", "zoom",
]
## A building's own variables that are caches, rebuilt with the hazard scan.
const SKIP_BUILDING := ["scan_idx", "seg_idx"]


static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path)


static func erase(path := PATH) -> void:
	if exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The header of the saved run ({seed, time, won}), or {} if there's none.
static func peek() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null or f.get_32() != MAGIC or f.get_32() != VERSION:
		return {}
	var head = f.get_var()
	return head if head is Dictionary else {}


## Write the run (to the slot, or `path` for the bot's checkpoints). False (and
## nothing changed on disk) if the sim can't be saved.
static func write(game, path := PATH) -> bool:
	if not game.sim.has_method("save_state"):
		return false
	var raw: PackedByteArray = game.sim.save_state()
	var sim_z := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var state := {}
	for v: String in GAME_VARS:
		state[v] = _enc(game.get(v))
	var blds: Array = []
	for b: Building in game.buildings:
		blds.append(_building(b))
	state["buildings"] = blds
	state["hub"] = game.hub.id
	state["crucible"] = game.crucible.id
	state["drill"] = game.drill.id
	state["rng"] = [game.rng.seed, game.rng.state]
	var gbytes := var_to_bytes(state)
	var game_z := gbytes.compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(MAGIC)
	f.store_32(VERSION)
	f.store_var({"seed": game.seed_value, "time": game.game_time, "won": game.won})
	f.store_32(raw.size())
	f.store_32(sim_z.size())
	f.store_buffer(sim_z)
	f.store_32(gbytes.size())
	f.store_32(game_z.size())
	f.store_buffer(game_z)
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## The saved run's two parts, {"sim": bytes, "game": Dictionary}, or {} if
## there's no readable save.
static func read(path := PATH) -> Dictionary:
	if not exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != MAGIC or f.get_32() != VERSION:
		return {}
	f.get_var()
	var sim_n := f.get_32()
	var sim_z := f.get_buffer(f.get_32())
	var game_n := f.get_32()
	var game_z := f.get_buffer(f.get_32())
	if f.get_error() != OK:
		return {}
	var sim_raw := sim_z.decompress(sim_n, FileAccess.COMPRESSION_ZSTD)
	var state = bytes_to_var(game_z.decompress(game_n, FileAccess.COMPRESSION_ZSTD))
	if sim_raw.size() != sim_n or not state is Dictionary:
		return {}
	return {"sim": sim_raw, "game": state}


## Put a read save's game side back into `game` (whose sim has already loaded
## the engine side). Buildings first, so references to them resolve.
static func restore(game, state: Dictionary) -> void:
	var by_id := {}
	var blds: Array = state["buildings"]
	for d: Dictionary in blds:
		var b := Building.new()
		b.id = d["id"]
		by_id[b.id] = b
	game.buildings.clear()
	for d: Dictionary in blds:
		var b: Building = by_id[d["id"]]
		for k: String in d:
			b.set(k, _dec(d[k], by_id, game))
		game.buildings.append(b)
	for v: String in GAME_VARS:
		if state.has(v):
			game.set(v, _dec(state[v], by_id, game))
	game.hub = by_id[state["hub"]]
	game.crucible = by_id[state["crucible"]]
	game.drill = by_id[state["drill"]]
	game.rng.seed = state["rng"][0]
	game.rng.state = state["rng"][1]


static func _building(b: Building) -> Dictionary:
	var d := {}
	for p: Dictionary in b.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if not SKIP_BUILDING.has(n):
			d[n] = _enc(b.get(n))
	return d


## A value as plain data: buildings become {"$b": id}, packets {"$p": fields},
## and every Dictionary {"$d": [[key, value], ...]} (its keys may be buildings).
static func _enc(v: Variant) -> Variant:
	if v is Object:
		if v is Building:
			return {"$b": v.id}
		var fields := {}
		for p: Dictionary in v.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields[p["name"]] = _enc(v.get(p["name"]))
		return {"$p": fields}
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_enc(e))
		return out
	if v is Dictionary:
		var pairs: Array = []
		for k: Variant in v:
			pairs.append([_enc(k), _enc(v[k])])
		return {"$d": pairs}
	return v


static func _dec(v: Variant, by_id: Dictionary, game) -> Variant:
	if v is Array:
		var out: Array = []
		for e: Variant in v:
			out.append(_dec(e, by_id, game))
		return out
	if v is Dictionary:
		if v.has("$b"):
			return by_id.get(v["$b"])
		if v.has("$p"):
			var p = game.make_packet()
			var fields: Dictionary = v["$p"]
			for k: String in fields:
				p.set(k, _dec(fields[k], by_id, game))
			return p
		var out := {}
		for kv: Array in v["$d"]:
			out[_dec(kv[0], by_id, game)] = _dec(kv[1], by_id, game)
		return out
	return v
