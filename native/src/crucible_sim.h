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
//    and much faster through rock than air, so walls cast shadows.
//
// Material ids are shared with the game (scripts/defs.gd, data/materials.json).

#ifndef CRUCIBLE_SIM_H
#define CRUCIBLE_SIM_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector4i.hpp>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

namespace godot {

class CrucibleSim : public RefCounted {
	GDCLASS(CrucibleSim, RefCounted)

public:
	static constexpr int W = 256;
	static constexpr int H = 1024;
	static constexpr int CSHIFT = 5; // chunks are 32 x 32
	static constexpr int CS = 1 << CSHIFT;
	static constexpr int CW = W / CS;
	static constexpr int CH = H / CS;
	static constexpr int NCH = CW * CH;
	static constexpr int NONE = 1 << 20;
	static constexpr uint32_t ONE = 65536; // chances are out of this
	static constexpr int LSTEP = 8; // light lost per straight step through air
	static constexpr int LDIAG = 11; // ... and per diagonal step
	static constexpr int LFULL = 48; // light at which a cell is at full brightness (6 cells)
	static constexpr int LMIN = 4; // light at which a cell counts as lit
	static constexpr int NHAZ = 8; // values hazards_at writes per building

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
		// water: a cell touching a liquid that isn't hot turns into wash_to (air: washed
		// away), with chance `wash` each time the wash pass checks it
		int16_t wash_to = -1;
		uint32_t wash = 0;
	};

	struct Reaction {
		uint8_t a, b, out_a, out_b;
		uint32_t chance; // out of ONE
	};

	struct Particle {
		float x, y, vx, vy;
		uint8_t mat, aux;
	};

	// Dirty rectangles, one per chunk.
	struct Rects {
		int32_t x0[NCH], y0[NCH], x1[NCH], y1[NCH];
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
		bool changed = false;
		Rects next;
	};

private:
	std::vector<uint8_t> cells;
	std::vector<uint8_t> aux;
	std::vector<int32_t> settle; // tick until which a freshly exposed solid cell holds still
	std::vector<uint8_t> held; // how many Struts hold each cell still (weathering, loosening, collapse)
	std::vector<int32_t> shields; // circles (x, y, r) that tremors leave alone
	std::vector<uint8_t> stamp;
	std::vector<std::atomic<uint8_t>> lava_dirty;
	std::vector<uint8_t> heat;
	std::vector<uint16_t> light_lv; // light left at each cell, LSTEP per cell of air
	std::vector<uint8_t> light_px; // brightness 0..255 per cell, for the renderer
	std::vector<std::vector<int32_t>> light_buckets;
	uint8_t opq[256]; // light cost multiplier per material
	std::vector<Particle> parts;
	Rects cur;
	Rects next;
	Mat mats[256];
	std::vector<int16_t> react_idx; // 256 x 256: index into reacts, or -1
	std::vector<Reaction> reacts;
	std::vector<Ctx> ctxs;
	int fire_id = -1;

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
	inline bool open(int j) const { return !solid(cells[j]); }
	inline bool thin(uint8_t m) const { return mats[m].kind == K_EMPTY || mats[m].kind == K_GAS; }
	inline bool is_fire_cell(int i) const {
		const Mat &M = mats[cells[i]];
		return M.flame || (M.hot && M.kind == K_GAS) || (M.burn_life && aux[i]);
	}
	inline void mark_lava(int x, int y) { lava_dirty[((y >> CSHIFT) * CW) + (x >> CSHIFT)].store(1, std::memory_order_relaxed); }
	uint8_t init_aux(uint8_t m, uint32_t r) const;
	void put(Ctx *cx, int i, int x, int y, uint8_t m, uint32_t r); // write a cell from inside the sim

	void update_cell(Ctx &cx, int i, int x, int y, uint8_t m);
	bool burn(Ctx &cx, int i, int x, int y, uint8_t m, uint32_t r);
	void heat_neighbour(Ctx &cx, int i, int x, int y, uint32_t r);
	void powder(Ctx &cx, int i, int x, int y, uint8_t m, int d);
	void liquid(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void spread(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void gas(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r);
	void swap_cells(Ctx &cx, int i, int j, int x, int y, int x2, int y2);
	void move_liquid(Ctx &cx, int i, int j, int x, int y, int x2, int y2, uint8_t m);
	void loosen_check(Ctx *cx, int i, int x, int y);
	int collapse_row(int y, bool to_air);
	int cling(int i, int step, int cap) const;
	void rebuild_spans();
	void hazards_at(int x, int y, int w, int h, bool inside, int reach, int32_t *out) const;
	void segment_at(int x0, int y0, int x1, int y1, int32_t *out) const;
	void step_particles();
	void spawn(float x, float y, float vx, float vy, uint8_t m, uint8_t a);
	void land(Particle &p, int px, int py);

protected:
	static void _bind_methods();

public:
	CrucibleSim();
	~CrucibleSim();

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
	PackedByteArray light_update(const PackedInt32Array &lights, const PackedInt32Array &sights, int sun, const PackedByteArray &known);
	PackedByteArray get_light() const;

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

	void set_threads(int n);
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
};

} // namespace godot

#endif
