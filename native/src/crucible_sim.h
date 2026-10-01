// Crucible's falling-sand simulation, in C++.
//
// Built the way Noita's engine is described in Petri Purho's GDC 2019 talk:
//  - the grid is cut into 32x32 chunks, each with a dirty rectangle, so settled
//    ground costs nothing; a changed cell wakes its neighbourhood for next tick;
//  - cells update in place (no second buffer), bottom-up, alternating direction
//    row by row, and a per-cell stamp stops anything moving twice in a tick;
//  - chunks run in four checkerboard passes: in one pass, active chunks are two
//    apart, and nothing moves more than a few cells, so they never touch the same
//    cells and can run on separate threads without locks. Each chunk seeds its own
//    random stream from (seed, tick, chunk), so results don't depend on threads;
//  - materials and reactions are data (configure()), not code;
//  - every cell carries one extra byte (aux): how long a burning cell has left,
//    or how long a short-lived gas (fire, smoke, fumes) has left;
//  - pixels thrown out of the grid (blast debris, a crumbling ceiling) become free
//    particles with velocity and gravity, and rejoin the grid where they land;
//  - explosions cast rays that spend their energy on what they break, so hard rock
//    shadows what's behind it;
//  - light spreads from lamps, glowing materials and the sky, fading cell by cell
//    and much faster through rock than air, so walls cast shadows;
//  - every cell has a temperature (A1): a slow pass leaks heat between neighbours
//    by each material's conductivity, pulls rock back toward the depth's ambient,
//    and turns materials into their hot or cold forms at the points in their data
//    (water boils, hot rock cools to stone, stone near lava heats up).
//
// Material ids are shared with the game (scripts/defs.gd, data/materials.json).

#ifndef CRUCIBLE_SIM_H
#define CRUCIBLE_SIM_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector4i.hpp>

#include <atomic>
#include <bitset>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

namespace godot {

class CrucibleSim : public RefCounted {
	GDCLASS(CrucibleSim, RefCounted)

public:
	static constexpr int CSHIFT = 5; // chunks are 32 x 32
	static constexpr int CS = 1 << CSHIFT;
	static constexpr int NONE = 1 << 20;
	static constexpr uint32_t ONE = 65536; // chances are out of this
	static constexpr int LSTEP = 8; // light lost per straight step through air
	static constexpr int LDIAG = 11; // ... and per diagonal step
	static constexpr int LFULL = 480; // light at which a block is at full brightness (60 cells in)
	static constexpr int LMIN = 4; // light at which a block counts as lit
	static constexpr int LIGHT_MAX_R = 400; // the furthest any light reaches, in cells
	static constexpr int TSHIFT = 8; // render tiles are 256 x 256 cells
	static constexpr int NHAZ = 8; // values hazards_at writes per building
	static constexpr int BRIDGE_UP = 8; // a cohesive row bridges a notch its own kind roofs this near above
	static constexpr int T8 = 8; // temperatures are kept in eighths of a degree
	static constexpr int16_t T_NONE = INT16_MIN; // "no such point" for a material's temperature data

	enum Kind : uint8_t {
		K_EMPTY = 0,
		K_STATIC = 1,
		K_POWDER = 2,
		K_LIQUID = 3,
		K_GAS = 4,
	};

	struct Mat {
		uint8_t kind = K_STATIC;
		int16_t density = 100;
		// liquids: how far to look for a drop, how far to move, how often a surface
		// cell wanders (1 in 2^bits), and "moves only every Nth tick"
		uint8_t look = 0;
		uint8_t max_step = 0;
		uint8_t wander_bits = 0;
		uint8_t slow = 1;
		// gases: stage ageing (steam) - becomes age_to, 1 in age_chance updates
		int16_t age_to = -1;
		uint16_t age_chance = 0;
		bool vents = false; // vanishes at the top of the map
		// gases: rise (buoyancy > 0) or sink (< 0), 1 update in 8/|b|; drift sideways
		// `drift` in 256 updates
		int8_t buoyancy = 8;
		uint8_t drift = 64;
		// short-lived gases: life in aux, losing 1 with chance life_decay/256 per
		// update; then it becomes expires_to, or expires_alt with alt_chance
		uint8_t life_min = 0;
		uint8_t life_max = 0;
		uint16_t life_decay = 256;
		bool ages_exposed = false; // a gas cell ages (and wakes) only with open air beside it: sealed pockets keep (A2)
		int16_t expires_to = -1;
		int16_t expires_alt = -1;
		uint32_t alt_chance = 0;
		// statics: what they turn into when undermined, exposed (erode), shaken
		// (tremor), blasted (shatters_to) or dropped off a ceiling (crumble)
		int16_t loosens_to = -1;
		int16_t erodes_to = -1;
		int16_t crumbles_to = -1;
		int16_t shatters_to = -1;
		uint32_t crumble = 0;
		int16_t crumbles_into = -1;
		uint8_t durability = 0; // what a blast must beat; 255 = never
		// burning: aux set to burn_life when lit; loses 1 with burn_speed per update
		uint8_t burn_life = 0;
		uint32_t ignite = 0; // chance to catch when something hot checks it
		uint32_t burn_speed = 0;
		int16_t burns_to = -1;
		int16_t burn_gas = -1;
		uint32_t gas_chance = 0;
		uint32_t flame_chance = 0;
		bool quench = false; // puts out burning neighbours (water), becoming quench_to
		int16_t quench_to = -1;
		bool glows = false; // shows on the heat map
		bool hot = false; // lights what can burn, and burns buildings
		bool flame = false; // the Fire material burning things throw off
		bool corrosive = false; // eats buildings and links nearby
		bool scalds = false; // hurts Conduits it wraps (steam)
		bool reactive = false; // appears in a reaction (set by configure)
		uint8_t light = 0; // glows by itself: radius of its light, in cells
		uint8_t opacity = 0; // light lost per cell crossing it, in air cells (0: by kind)
		bool structure = false; // a building's cells: clear to light, not rock to anchor on
		// collapse: widest open run under it a ceiling of this spans (0: any), and how
		// far past the end of a run it reaches unsupported
		uint8_t span = 0;
		uint8_t overhang = 0;
		uint32_t cave = ONE / 3; // chance a sweep that an unsupported cell of it gives way
		bool cohesive = false; // hangs only from its own kind (or rock that never gives way)
		int16_t kin = -1; // what counts as its own kind for that (-1: itself)
		// water: a cell touching a liquid that isn't hot turns into wash_to (air: washed
		// away), with chance `wash` each time the wash pass checks it
		int16_t wash_to = -1;
		uint32_t wash = 0;
		// temperature (A1), in eighths of a degree: how readily heat crosses into
		// a neighbour (out of 1024, per pass, per neighbour: the pair takes the lower),
		// how strongly the depth's ambient pulls the cell back (out of 256), what it
		// holds itself at while it's a source (lava, a burning cell), and the points
		// where it becomes something else: above heats_at, below cools_at (each
		// costing or releasing `*_cost` of heat), and the heat at which it catches
		// fire (kindle, with an open side).
		uint16_t conduct = 100;
		uint8_t sink = 0;
		int16_t placed = T_NONE; // what a fresh cell of it arrives at from outside the sim (water: cold)
		int16_t hold = T_NONE;
		uint8_t hold_rate = 64;
		int16_t burn_temp = T_NONE;
		int16_t heats_at = T_NONE;
		int16_t heats_to = -1;
		int16_t heats_cost = 0;
		int16_t cools_at = T_NONE;
		int16_t cools_to = -1;
		int16_t cools_cost = 0;
		int16_t kindle = T_NONE;
		uint16_t family = 0; // family tags, a bit each (materials.gd assigns them)
		// A2 (wave 1). Heat capacity: a pass's change in degrees is shared among this many
		// cells' worth of mass (Rime takes 20 times the heat to move).
		uint8_t heat_mass = 1;
		// A setting stage: aux counts down (it starts at the material's life) and at
		// zero the cell becomes sets_to; each update it counts a step with chance
		// set_speed, times set_boost with a cell of the set_catalyst family beside it.
		int16_t sets_to = -1;
		uint32_t set_speed = 0;
		uint16_t set_catalyst = 0;
		uint16_t set_boost = 256;
		// A burning cell with a burn_catalyst cell beside it burns down burn_boost / 256 times as fast.
		uint16_t burn_catalyst = 0;
		uint16_t burn_boost = 256;
		bool burn_wet = false; // keeps burning beside water (oil on a pond); smothering gas still puts it out
		// A blast of blast_r cells (power blast_power) when it takes a hard landing
		// (blast_impact, sixteenths of a cell a tick), is hot (blast_temp) or has fire
		// beside it (blast_flame), unless a cell of the blast_inhibit family touches it.
		// It sets off the like of itself within its radius a few ticks later.
		uint8_t blast_r = 0;
		uint8_t blast_power = 0;
		uint8_t blast_impact = 0;
		int16_t blast_temp = T_NONE;
		bool blast_flame = false;
		uint16_t blast_inhibit = 0;
		// A swell: beside a liquid (not a hot one) it turns itself and that cell into
		// absorb_to, with the liquid's id in the aux byte, with chance absorb_chance.
		int16_t absorb_to = -1;
		uint32_t absorb_chance = 0;
		// What a swollen cell of this liquid bursts into, and for the swollen cell itself:
		// the heat it bursts at and the plume when the soaked liquid names none.
		int16_t plume = -1;
		int16_t bursts_at = T_NONE;
		// Growth: with chance grow_chance an update (and at least 5 degrees), a cell of it
		// takes over one of the four neighbours in grow_over if a grow_feed cell is within
		// grow_reach; that cell is used up.
		uint32_t grow_chance = 0;
		uint16_t grow_feed = 0;
		uint8_t grow_reach = 0;
		std::bitset<256> grow_over;
		// A material that comes out of a reaction as a rigid body of body_w x body_h cells.
		uint8_t body_w = 0;
		uint8_t body_h = 0;
		bool watch = false; // wakes when its temperature moves (reactions that wait on one, blasts, bursts)
	};

	struct Reaction {
		uint8_t a, b, out_a, out_b;
		uint32_t chance; // out of ONE
		// A1: only within [min_temp, max_temp] (eighths of a degree); `heat` goes
		// into both outputs; with a cell of a `catalyst` family among the eight
		// neighbours the chance is `boost` / 256 times as high.
		int16_t min_temp = INT16_MIN;
		int16_t max_temp = INT16_MAX;
		int16_t heat = 0;
		uint16_t catalyst = 0;
		uint16_t boost = 256;
		// A2: with chance emit_chance each time it fires, a rigid body of the `emit`
		// material is forged beside the cells (Ferrite bars from smelting).
		uint8_t emit = 0;
		uint32_t emit_chance = 0;
	};

	// A detonation waiting for its tick (a cell's blast, or one set off by another's).
	struct Blast {
		int x = 0, y = 0;
		int r = 0, power = 0;
		int due = 0;
	};
	struct Emit {
		int x = 0, y = 0;
		uint8_t mat = 0;
	};

	struct Particle {
		float x, y, vx, vy;
		uint8_t mat, aux;
	};

	// A rigid body: a piece of ground that broke off (bodies.cpp). Its pixels live in
	// the grid as ordinary cells tagged with its id (`owner`), so everything else
	// treats it as rock; each tick it's lifted out, moved and stamped back.
	struct Body {
		int id = 0;
		int w = 0, h = 0; // its own bitmap
		std::vector<uint8_t> mat, aux; // row-major, mat 0 is empty
		std::vector<int16_t> temp; // ... and each pixel's temperature (A1): a hot slab stays hot
		std::vector<int32_t> edge; // pixels with an empty side (what collides)
		float cx = 0, cy = 0; // centre of mass, in its bitmap
		float x = 0, y = 0, a = 0; // where the centre of mass is, and the angle
		float vx = 0, vy = 0, spin = 0; // cells and radians a tick
		float mass = 0, inertia = 0, radius = 0, toughness = 0;
		int count = 0;
		float sx = 0, sy = 0, sa = 0; // the pose it was last stamped at
		std::vector<int32_t> at; // grid cells it's stamped into
		std::vector<int32_t> from; // ... and the pixel each came from
		float ax = 0, ay = 0, aa = 0; // where it was when it last started being still
		bool creature = false; // a mite: never turns back into ground (the game takes it back when it's still)
		int age = 0, rest = 0, last_hit = -100;
	};

	struct Contact {
		int n = 0; // pixels in the way
		float px = 0, py = 0; // their sum
		float gx = 0, gy = 0; // which way the ground they hit lies
		int nb = 0; // ... of them in a building
		float bx = 0, by = 0;
		int other = 0; // a body it ran into (the first seen), or 0
	};

	// Dirty rectangles, one per chunk.
	struct Rects {
		int w = 0, h = 0, cw = 0, n = 0;
		std::vector<int32_t> x0, y0, x1, y1;
		void init(int width, int height);
		void reset();
		void touch(int x, int y);
		void merge(const Rects &o);
	};

	// Everything one worker writes besides cells: its own random stream, counters
	// and the rectangles it wakes for next tick (merged after the passes).
	struct Ctx {
		uint32_t rng = 1;
		int updates = 0;
		int reactions = 0;
		int ignitions = 0;
		int tchunks = 0; // chunks the temperature pass found still changing
		bool changed = false;
		Rects next;
		std::vector<uint8_t> tnext; // chunks the temperature pass must look at next time
		std::vector<Blast> blasts; // detonations this tick, run after the passes
		std::vector<Emit> emits; // bodies to forge, likewise
	};

private:
	// The grid's size, set by set_size (multiples of 32); chunks across and down.
	int W = 256;
	int H = 1024;
	int CW = 256 / CS;
	int CH = 1024 / CS;
	int NCH = CW * CH;

	std::vector<uint8_t> cells;
	std::vector<uint8_t> aux;
	std::vector<int32_t> settle; // tick until which a freshly exposed solid cell holds still
	std::vector<uint8_t> held; // how many Struts hold each cell still (weathering, loosening, collapse)
	std::vector<uint8_t> vel; // falling speed, in sixteenths of a cell a tick (powders and liquids in free fall)
	std::vector<uint8_t> mem; // the map as last seen: live blocks are copied in by light_update
	std::vector<uint8_t> tile_dirty; // render tiles whose cells (or aux) changed since take_dirty_tiles
	std::vector<uint8_t> mem_dirty; // render tiles whose remembered cells changed since take_mem_tiles
	int TW = 3, TH = 4; // render tiles across and down
	// Corrosive cells per chunk, recounted when the chunk has been touched (for
	// hazards_at's corrosion reach, which is wide at this scale).
	mutable std::vector<int32_t> corr_count;
	mutable std::vector<uint8_t> corr_valid;
	std::vector<int32_t> shields; // circles (x, y, r) that tremors leave alone
	std::vector<uint8_t> stamp;
	std::vector<std::atomic<uint8_t>> heat_dirty; // chunks whose heat map blocks need working out again
	std::vector<uint8_t> heat;
	// Temperature (A1): eighths of a degree per cell; the ambient each row's rock
	// settles back to; which chunks the next temperature pass looks at.
	std::vector<int16_t> temp;
	std::vector<int16_t> ambient;
	std::vector<uint8_t> tcur;
	std::vector<uint8_t> tnext;
	uint16_t cond[256]; // each material's conduct, packed for the pass
	int pass_mode = 0; // what a worker does with a chunk: 0 cells, 1 temperature
	int temp_every = 8; // ticks between temperature passes
	int sink_every = 1; // temperature passes between pulls toward the ambient...
	int sink_rate = 8; // ... and how hard each pulls (out of 4096 of the gap, times the material's sink;
		// rounded down, so a cell within 4096 / sink_rate eighths of it is left alone)
	int temp_passes = 0;
	int stat_tchunks = 0;
	std::vector<uint16_t> light_lv; // light left at each 4x4 block, LSTEP per cell of air
	std::vector<uint8_t> light_px; // brightness 0..255 per block, for the renderer
	std::vector<uint16_t> light_cost; // what crossing each block costs (sum of its cells' opacities)
	std::vector<int32_t> light_stamp; // light_gen when light_cost was worked out
	int light_gen = 0;
	std::vector<int32_t> spot_offsets; // (dx, dy) pairs within spot_radius, nearest first
	int spot_radius = -1;
	std::vector<std::vector<int32_t>> light_buckets;
	int view_x0 = 0, view_y0 = 0, view_x1 = 1 << 20, view_y1 = 1 << 20; // explored ground outside isn't lit
	uint8_t opq[256]; // light cost multiplier per material
	std::vector<Particle> parts;
	// Rigid bodies (bodies.cpp).
	std::vector<Body> bodies;
	std::vector<uint16_t> owner; // the body a cell belongs to (0: none)
	int next_body_id = 1;
	std::vector<int32_t> impacts; // x, y, speed (cells a second), mass, hit a building, body hit: 6 per hit
	float body_g = 0.25f; // cells a tick, per tick
	float body_max = 10.0f; // cells a tick
	float shatter_base = 1.5f; // impact speed (cells a tick) that breaks a body up...
	float shatter_per = 0.33f; // ... plus this per point of its ground's durability
	float crush_min = 1.0f; // slower impacts than this aren't reported
	float creature_tough = 8.0f; // impact speed (cells a tick) that kills a creature
	int body_min = 12; // pieces smaller than this crumble instead
	int piece_min = 24, piece_max = 64; // how wide a piece breaking off a ceiling is
	int thick_min = 6, thick_max = 20; // ... and how thick
	int piece_room = 20; // open cells a ceiling needs under it to drop a piece (else it crumbles)
	bool pieces = true; // collapse breaks ceilings off in pieces (false: cell by cell)
	int bodies_made = 0, bodies_shattered = 0, bodies_settled = 0;
	static constexpr int MAX_BODIES = 200;
	Rects cur;
	Rects next;
	Mat mats[256];
	std::vector<int16_t> react_idx; // 256 x 256: index into reacts, or -1
	std::vector<Reaction> reacts;
	std::vector<Ctx> ctxs;
	int fire_id = -1;
	std::vector<Blast> blast_queue; // detonations waiting for their tick
	int blasts_made = 0;
	int bodies_forged = 0;

	uint32_t seed = 22695477u;
	uint32_t grng = 22695477u; // game-side randomness (weathering, tremors, blasts)
	int tick = 0;
	int mark = 1;
	bool changed = true;
	bool heat_changed = true;
	int stat_chunks = 0;
	int stat_updates = 0;
	int reactions_total = 0;
	int ignitions_total = 0;
	int eroded = 0;
	int crumbled = 0;
	int caved = 0;
	int collapse_cursor = H - 4; // next row the collapse sweep looks at (bottom up)
	int min_span = 255; // smallest span among materials that have one
	bool any_cohesive = false;
	int washed = 0;
	int last_cave_x = -1, last_cave_y = -1;
	int threads_wanted = 1;
	// Free fall (set_fall): speed gained a tick and the most, in sixteenths of a cell
	// a tick. With fall_g 0 everything falls one cell a tick.
	int fall_g = 0;
	int fall_max = 16;
	static constexpr int FALL_CAP = 15 * 16; // cells a tick: checkerboard chunks sit 32 apart

	// Worker pool for the checkerboard passes.
	std::vector<std::thread> workers;
	std::mutex pool_mutex;
	std::condition_variable pool_cv;
	std::condition_variable pool_done_cv;
	const std::vector<int> *pool_jobs = nullptr;
	std::atomic<int> pool_next{ 0 };
	int pool_busy = 0;
	int pool_generation = 0;
	bool pool_quit = false;

	void default_materials();
	void rebuild_reactions();
	void rebuild_light();
	void start_pool(int n);
	void stop_pool();
	void worker_loop(int index);
	void run_pass(const std::vector<int> &list);
	void process_chunk(Ctx &cx, int c);

	inline bool solid(uint8_t m) const { return mats[m].kind == K_STATIC || mats[m].kind == K_POWDER; }
	inline int kin_of(uint8_t m) const { return mats[m].kin >= 0 ? mats[m].kin : m; }
	inline bool open(int j) const { return !solid(cells[j]); }
	inline bool thin(uint8_t m) const { return mats[m].kind == K_EMPTY || mats[m].kind == K_GAS; }
	inline bool is_fire_cell(int i) const {
		const Mat &M = mats[cells[i]];
		return M.flame || (M.hot && M.kind == K_GAS) || (M.burn_life && aux[i]);
	}
	inline void mark_heat(int x, int y) { heat_dirty[((y >> CSHIFT) * CW) + (x >> CSHIFT)].store(1, std::memory_order_relaxed); }
	// A cell that changed: its chunk gets a temperature pass next time.
	inline void tmark(Ctx *cx, int x, int y) { (cx ? cx->tnext : tnext)[((y >> CSHIFT) * CW) + (x >> CSHIFT)] = 1; }
	inline bool has_family(int i, uint16_t fam) const {
		const int offs[8] = { -W - 1, -W, -W + 1, -1, 1, W - 1, W, W + 1 };
		for (int k = 0; k < 8; k++) {
			if (mats[cells[i + offs[k]]].family & fam) {
				return true;
			}
		}
		return false;
	}
	uint8_t init_aux(uint8_t m, uint32_t r) const;
	int16_t init_temp(uint8_t m, int16_t at) const; // what a cell of m made inside the sim is at, where the cell was `at`
	int16_t placed_temp(uint8_t m, int16_t at) const; // ... and one placed from outside (set_cell, worldgen)
	void put(Ctx *cx, int i, int x, int y, uint8_t m, uint32_t r); // write a cell from inside the sim

	void update_cell(Ctx &cx, int i, int x, int y, uint8_t m);
	bool detonate(Ctx &cx, int i, int x, int y); // a blast material goes off (unless smothered): the cell is spent
	void grow_cell(Ctx &cx, int i, int x, int y, uint8_t m);
	void absorb(Ctx &cx, int i, int x, int y, uint8_t m);
	void burst(Ctx &cx, int i, int x, int y, uint8_t m);
	void run_blasts(); // after the passes: gather, chain and fire the blasts due
	void run_emits(); // forge the bodies the reactions asked for
	void step_temperature();
	void temp_chunk(Ctx &cx, int c);
	bool burn(Ctx &cx, int i, int x, int y, uint8_t m, uint32_t r);
	void heat_neighbour(Ctx &cx, int i, int x, int y, uint32_t r);
	void powder(Ctx &cx, int i, int x, int y, uint8_t m, int d);
	int fall(Ctx &cx, int i, int x, int y); // straight down through open space, gaining speed; cells dropped
	void liquid(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void spread(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void gas(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void swap_cells(Ctx &cx, int i, int j, int x, int y, int x2, int y2);
	void move_liquid(Ctx &cx, int i, int j, int x, int y, int x2, int y2, uint8_t m);
	void loosen_check(Ctx *cx, int i, int x, int y);
	int collapse_row(int y, bool to_air);
	bool due(int i, int xx, int a, int b, int w) const;
	int cling(int i, int step, int cap) const;
	void rebuild_spans();
	void hazards_at(int x, int y, int w, int h, bool inside, int reach, int32_t *out) const;
	void segment_at(int x0, int y0, int x1, int y1, int32_t *out) const;
	void step_particles();
	void spawn(float x, float y, float vx, float vy, uint8_t m, uint8_t a);
	void land(Particle &p, int px, int py);

	// Bodies (bodies.cpp).
	inline bool can_break_off(int i) const {
		const Mat &M = mats[cells[i]];
		return M.kind == K_STATIC && M.span > 0 && !held[i] && settle[i] <= tick && owner[i] == 0;
	}
	int give_way(int y, int s, int e);
	int break_off(int y, int s, int e);
	int crumble_cell(int i, int x, int y);
	int make_body_from(const std::vector<int32_t> &list, float vx, float vy, float spin);
	bool body_shape(Body &b);
	void step_bodies();
	bool body_tick(Body &b);
	bool overlap(const Body &b, float x, float y, float a, const std::vector<int32_t> &skip, Contact &c,
			std::vector<int32_t> *collect) const;
	bool body_hit(Body &b, const Contact &c, float &nx, float &ny);
	void unstamp(Body &b);
	void restamp(Body &b);
	void shatter(Body &b);
	void settle_body(Body &b);
	void clear_bodies();
	void push_bodies(float x, float y, float rad, int power);

protected:
	static void _bind_methods();

public:
	CrucibleSim();
	~CrucibleSim();

	void set_size(int w, int h);
	int get_width() const { return W; }
	int get_height() const { return H; }
	void configure(const Array &materials, const Array &reactions);
	void set_seed(int s);

	int get_cell(int x, int y) const;
	void set_cell(int x, int y, int m);
	int get_aux(int x, int y) const;
	void ignite(int x, int y);
	void settle_around(int x, int y, int radius, int ticks);
	int get_settle(int x, int y) const;
	PackedByteArray get_cells() const;
	void set_cells(const PackedByteArray &data);
	PackedByteArray get_aux_bytes() const;
	void touch_rect(int x0, int y0, int x1, int y1);

	void step();
	void erode(int samples, int y_min, int y_max);
	int weather(int samples);
	int collapse(int rows);
	int wash(int samples);
	int get_washed() const { return washed; }
	int stabilize();
	void hold_circle(int x, int y, int r, int delta);
	int get_held(int x, int y) const;
	void set_shields(const PackedInt32Array &circles);
	Vector2i get_last_cave() const { return Vector2i(last_cave_x, last_cave_y); }
	int tremor(int wanted, int y_min, int y_max);
	int explode(int x, int y, double radius, int power);
	void add_particle(double x, double y, double vx, double vy, int m);
	void refresh_heat(bool all);
	PackedByteArray get_heat() const;
	// Temperature (A1), in degrees from GDScript.
	int get_temp(int x, int y) const;
	void set_temp(int x, int y, int degrees);
	void heat_rect(int x, int y, int w, int h, int degrees);
	void heat_circle(int x, int y, int r, int degrees);
	Vector3i rect_temp(int x, int y, int w, int h) const; // lowest, highest, mean
	void set_ambient(const PackedInt32Array &rows);
	void reset_temps();
	void set_temp_params(const Dictionary &p);
	int paint_circle(int x, int y, int r, int m, bool keep_fixed);
	int get_stat_tchunks() const { return stat_tchunks; }
	PackedInt32Array get_temp_chunks() const; // chunks the next temperature pass looks at
	PackedByteArray light_update(const PackedInt32Array &lights, const PackedInt32Array &sights, int sun, const PackedByteArray &known);
	PackedByteArray get_light() const;
	void set_light_view(int x0, int y0, int x1, int y1);
	void mark_tiles(const Rects &r);
	PackedInt32Array take_dirty_tiles();
	PackedInt32Array take_mem_tiles();
	PackedByteArray get_tile(int which, int tile) const;
	void reset_memory();
	int get_tiles_across() const { return TW; }
	int get_tiles_down() const { return TH; }

	int count(int m) const;
	int count_burning() const;
	int particle_count() const { return (int)parts.size(); }
	int64_t checksum() const;
	Vector4i ring_counts(int x, int y, int w, int h, bool inside) const;
	PackedInt32Array building_hazards(int x, int y, int w, int h, bool inside, int reach) const;
	PackedInt32Array segment_hazards(int x0, int y0, int x1, int y1) const;
	PackedInt32Array hazards_batch(const PackedInt32Array &rects, int reach) const;
	PackedInt32Array segments_batch(const PackedInt32Array &segs) const;
	PackedInt32Array materials_in(const PackedByteArray &mask) const;
	int count_in_rect(int x, int y, int w, int h, const PackedByteArray &mask) const;
	PackedByteArray block_counts(int bx, int by, int bw, int bh, const PackedByteArray &mask) const;
	PackedInt32Array rect_counts(int x, int y, int w, int h) const;
	PackedInt32Array dig_rect(int x, int y, int w, int h, const PackedByteArray &mask, int settle_r, int settle_ticks);
	PackedByteArray block_circles(const PackedInt32Array &circles) const;
	PackedInt32Array place_spots(int x, int y, int w, int h, int radius, const PackedByteArray &open_mask, const PackedByteArray &solid_mask);

	void set_body_params(const Dictionary &p);
	int make_body(int x, int y, int w, int h, double vx, double vy, double spin);
	int body_count() const { return (int)bodies.size(); }
	PackedInt32Array get_bodies() const;
	PackedFloat32Array body_state(int id) const;
	PackedInt32Array take_impacts();
	int get_bodies_made() const { return bodies_made; }
	int get_bodies_shattered() const { return bodies_shattered; }
	int get_bodies_settled() const { return bodies_settled; }
	int get_owner(int x, int y) const;
	bool set_creature(int id, bool on);
	bool remove_body(int id);

	PackedByteArray save_state() const; // save.cpp
	template <class O>
	void write_state(O &o) const; // save.cpp: counts the bytes, or writes them
	bool load_state(const PackedByteArray &data);

	void set_threads(int n);
	void set_fall(double accel, double max_speed);
	int get_threads() const { return threads_wanted; }

	bool get_changed() const { return changed; }
	void set_changed(bool v) { changed = v; }
	bool get_heat_changed() const { return heat_changed; }
	void set_heat_changed(bool v) { heat_changed = v; }
	int get_stat_chunks() const { return stat_chunks; }
	int get_stat_updates() const { return stat_updates; }
	int get_reactions() const { return reactions_total; }
	int get_ignitions() const { return ignitions_total; }
	int get_eroded() const { return eroded; }
	int get_crumbled() const { return crumbled; }
	int get_caved() const { return caved; }
	int get_tick() const { return tick; }
	int get_blasts() const { return blasts_made; }
	int get_forged() const { return bodies_forged; }
};

} // namespace godot

#endif
