#include "crucible_sim.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

using namespace godot;

namespace {

// Material ids the defaults and a few fixed rules refer to (see data/materials.json).
constexpr uint8_t AIR = 0, BEDROCK = 1, STONE = 2, GLIMMER = 3, OBSIDIAN = 4, BUILDING = 5,
				  DIRT = 6, LOOSE_DIRT = 7, RUBBLE = 8, WATER = 9, LAVA = 10, STEAM = 11, STEAM_LAST = 18;

constexpr float GRAVITY = 0.045f; // particles, cells per tick per tick
constexpr float MAX_SPEED = 4.0f;

inline uint32_t hash3(uint32_t a, uint32_t b, uint32_t c) {
	uint32_t h = a * 0x9E3779B1u ^ (b + 0x7F4A7C15u) * 0x85EBCA77u ^ (c + 0x165667B1u) * 0xC2B2AE3Du;
	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;
	h *= 0x846CA68Bu;
	h ^= h >> 16;
	return h | 1u;
}

inline uint32_t lcg(uint32_t &s) {
	s = s * 1103515245u + 12345u;
	return s >> 1; // 31 bits, like the old GDScript stream
}

// A roll against a chance out of 65536.
inline bool roll(uint32_t &s, uint32_t chance) {
	if (chance >= 65536u) {
		return true;
	}
	if (chance == 0) {
		return false;
	}
	return ((lcg(s) >> 7) & 0xFFFFu) < chance;
}

inline float frand(uint32_t &s) {
	return (float)((lcg(s) >> 7) & 0xFFFFu) / 65535.0f;
}

const int N8X[8] = { 0, 0, -1, 1, -1, 1, -1, 1 };
const int N8Y[8] = { -1, 1, 0, 0, -1, -1, 1, 1 };

} // namespace

// --- Rectangles ----------------------------------------------------------------

void CrucibleSim::Rects::init(int width, int height) {
	w = width;
	h = height;
	cw = width / CS;
	n = cw * (height / CS);
	x0.assign(n, NONE);
	y0.assign(n, NONE);
	x1.assign(n, -1);
	y1.assign(n, -1);
}

void CrucibleSim::Rects::reset() {
	for (int c = 0; c < n; c++) {
		x0[c] = NONE;
		y0[c] = NONE;
		x1[c] = -1;
		y1[c] = -1;
	}
}

void CrucibleSim::Rects::touch(int x, int y) {
	int c = ((y >> CSHIFT) * cw) + (x >> CSHIFT);
	if (x < x0[c]) {
		x0[c] = x;
	}
	if (x > x1[c]) {
		x1[c] = x;
	}
	if (y < y0[c]) {
		y0[c] = y;
	}
	if (y > y1[c]) {
		y1[c] = y;
	}
	int lx = x & (CS - 1);
	int ly = y & (CS - 1);
	if (lx != 0 && lx != CS - 1 && ly != 0 && ly != CS - 1) {
		return;
	}
	// On a chunk border the neighbours live in other chunks: wake those too.
	for (int dy = -1; dy <= 1; dy++) {
		int yy = y + dy;
		if (yy < 0 || yy >= h) {
			continue;
		}
		for (int dx = -1; dx <= 1; dx++) {
			int xx = x + dx;
			if (xx < 0 || xx >= w) {
				continue;
			}
			int c2 = ((yy >> CSHIFT) * cw) + (xx >> CSHIFT);
			if (c2 == c) {
				continue;
			}
			if (xx < x0[c2]) {
				x0[c2] = xx;
			}
			if (xx > x1[c2]) {
				x1[c2] = xx;
			}
			if (yy < y0[c2]) {
				y0[c2] = yy;
			}
			if (yy > y1[c2]) {
				y1[c2] = yy;
			}
		}
	}
}

void CrucibleSim::Rects::merge(const Rects &o) {
	for (int c = 0; c < n; c++) {
		if (o.x1[c] < 0) {
			continue;
		}
		x0[c] = std::min(x0[c], o.x0[c]);
		y0[c] = std::min(y0[c], o.y0[c]);
		x1[c] = std::max(x1[c], o.x1[c]);
		y1[c] = std::max(y1[c], o.y1[c]);
	}
}

// --- Setup ------------------------------------------------------------------------

CrucibleSim::CrucibleSim() :
		react_idx(256 * 256, -1) {
	ctxs.resize(1);
	set_size(W, H);
	default_materials();
}

// Sizes the grid (both multiples of 32) and clears it: every buffer, the dirty
// rectangles, particles and the collapse sweep start over. Call it before filling
// the world.
void CrucibleSim::set_size(int w, int h) {
	if (w < CS || h < CS || w % CS != 0 || h % CS != 0) {
		UtilityFunctions::push_error("CrucibleSim.set_size: both sides must be positive multiples of ", CS, ", got ", w, " x ", h);
		return;
	}
	W = w;
	H = h;
	CW = W / CS;
	CH = H / CS;
	NCH = CW * CH;
	const size_t N = (size_t)W * H;
	cells.assign(N, 0);
	aux.assign(N, 0);
	settle.assign(N, 0);
	held.assign(N, 0);
	vel.assign(N, 0);
	mem.assign(N, 0);
	TW = (W + (1 << TSHIFT) - 1) >> TSHIFT;
	TH = (H + (1 << TSHIFT) - 1) >> TSHIFT;
	tile_dirty.assign((size_t)TW * TH, 1);
	mem_dirty.assign((size_t)TW * TH, 1);
	corr_count.assign(NCH, 0);
	corr_valid.assign(NCH, 0);
	stamp.assign(N, 0);
	light_lv.clear(); // sized by light_update, a value per 4x4 block
	light_px.clear();
	heat.assign((size_t)(W / 4) * (H / 4), 0);
	std::vector<std::atomic<uint8_t>> flags(NCH);
	for (auto &f : flags) {
		f.store(0);
	}
	lava_dirty.swap(flags);
	parts.clear();
	cur.init(W, H);
	next.init(W, H);
	for (Ctx &cx : ctxs) {
		cx.next.init(W, H);
	}
	collapse_cursor = H - 4;
	changed = true;
	heat_changed = true;
}

CrucibleSim::~CrucibleSim() {
	stop_pool();
}

// The materials as the game shipped them before data/materials.json existed, so
// the sim behaves even if configure() is never called.
void CrucibleSim::default_materials() {
	for (auto &m : mats) {
		m = Mat();
	}
	mats[AIR].kind = K_EMPTY;
	mats[AIR].density = 0;
	for (uint8_t m : { BEDROCK, STONE, GLIMMER, OBSIDIAN, BUILDING, DIRT }) {
		mats[m].kind = K_STATIC;
	}
	mats[BEDROCK].durability = 255;
	mats[BUILDING].durability = 255;
	mats[DIRT].loosens_to = LOOSE_DIRT;
	mats[DIRT].erodes_to = LOOSE_DIRT;
	mats[STONE].crumbles_to = RUBBLE;
	mats[DIRT].crumbles_into = LOOSE_DIRT;
	mats[STONE].crumbles_into = RUBBLE;
	mats[DIRT].span = 7;
	mats[STONE].span = 15;
	mats[STONE].overhang = 3;
	mats[STONE].cohesive = true;
	mats[DIRT].overhang = 1;
	for (uint8_t m : { LOOSE_DIRT, RUBBLE }) {
		mats[m].kind = K_POWDER;
		mats[m].density = 50;
	}
	Mat &w = mats[WATER];
	w.kind = K_LIQUID;
	w.density = 10;
	w.look = 8;
	w.max_step = 4;
	w.wander_bits = 3;
	Mat &l = mats[LAVA];
	l.kind = K_LIQUID;
	l.density = 30;
	l.look = 4;
	l.max_step = 2;
	l.wander_bits = 4;
	l.slow = 2;
	l.glows = true;
	l.hot = true;
	l.light = 10;
	mats[BUILDING].structure = true;
	for (int s = STEAM; s <= STEAM_LAST; s++) {
		Mat &g = mats[s];
		g.kind = K_GAS;
		g.density = 1;
		g.age_to = s < STEAM_LAST ? s + 1 : WATER;
		g.age_chance = 64;
		g.vents = true;
		g.scalds = true;
	}
	fire_id = -1;
	reacts.clear();
	reacts.push_back({ LAVA, WATER, OBSIDIAN, STEAM, ONE });
	rebuild_reactions();
	rebuild_light();
	rebuild_spans();
}

void CrucibleSim::rebuild_spans() {
	min_span = 255;
	any_cohesive = false;
	for (const Mat &M : mats) {
		if (M.span > 0 && M.kind == K_STATIC) {
			min_span = std::min(min_span, (int)M.span);
			any_cohesive = any_cohesive || M.cohesive;
		}
	}
}

// What light loses crossing each material, in cells of air: its own opacity, or by
// kind (open 1, liquid 2, solid 5). A building's cells are as clear as air.
void CrucibleSim::rebuild_light() {
	for (int m = 0; m < 256; m++) {
		const Mat &M = mats[m];
		int o = M.opacity;
		if (o == 0) {
			o = (M.kind == K_EMPTY || M.kind == K_GAS || M.structure) ? 1 : (M.kind == K_LIQUID ? 2 : 5);
		}
		opq[m] = (uint8_t)o;
	}
}

void CrucibleSim::rebuild_reactions() {
	std::fill(react_idx.begin(), react_idx.end(), (int16_t)-1);
	for (auto &m : mats) {
		m.reactive = false;
	}
	// Each reaction goes in twice, once from each side, so whichever cell updates
	// first can start it.
	std::vector<Reaction> both;
	for (const Reaction &r : reacts) {
		both.push_back(r);
		both.push_back({ r.b, r.a, r.out_b, r.out_a, r.chance });
	}
	reacts = both;
	for (int k = 0; k < (int)reacts.size(); k++) {
		const Reaction &r = reacts[k];
		if (react_idx[r.a * 256 + r.b] < 0) {
			react_idx[r.a * 256 + r.b] = (int16_t)k;
		}
		mats[r.a].reactive = true;
	}
}

static uint32_t chance_of(const Dictionary &d, const char *key) {
	double p = d.get(key, 0.0);
	return (uint32_t)std::clamp(p * 65536.0, 0.0, 65536.0);
}

// materials: Array of Dictionary (see materials.gd for the keys);
// reactions: Array of Dictionary {a, b, out_a, out_b, chance (0..1)}
void CrucibleSim::configure(const Array &materials, const Array &reactions) {
	for (auto &m : mats) {
		m = Mat();
	}
	fire_id = -1;
	for (int k = 0; k < materials.size(); k++) {
		Dictionary d = materials[k];
		int id = d.get("id", -1);
		if (id < 0 || id > 255) {
			continue;
		}
		Mat &m = mats[id];
		m.kind = (uint8_t)(int)d.get("kind", (int)K_STATIC);
		m.density = (int16_t)(int)d.get("density", 100);
		m.look = (uint8_t)(int)d.get("look", 0);
		m.max_step = (uint8_t)(int)d.get("max_step", 0);
		m.wander_bits = (uint8_t)(int)d.get("wander_bits", 0);
		m.slow = (uint8_t)std::max(1, (int)d.get("slow", 1));
		m.age_to = (int16_t)(int)d.get("age_to", -1);
		m.age_chance = (uint16_t)(int)d.get("age_chance", 0);
		m.vents = (bool)d.get("vents", false);
		m.buoyancy = (int8_t)std::clamp((int)d.get("buoyancy", 8), -8, 8);
		m.drift = (uint8_t)std::clamp((int)d.get("drift", 64), 0, 255);
		m.life_min = (uint8_t)std::clamp((int)d.get("life_min", 0), 0, 255);
		m.life_max = (uint8_t)std::clamp((int)d.get("life_max", 0), 0, 255);
		m.life_decay = (uint16_t)std::clamp((int)d.get("life_decay", 256), 1, 256);
		m.expires_to = (int16_t)(int)d.get("expires_to", -1);
		m.expires_alt = (int16_t)(int)d.get("expires_alt", -1);
		m.alt_chance = chance_of(d, "alt_chance");
		m.loosens_to = (int16_t)(int)d.get("loosens_to", -1);
		m.erodes_to = (int16_t)(int)d.get("erodes_to", -1);
		m.crumbles_to = (int16_t)(int)d.get("crumbles_to", -1);
		m.shatters_to = (int16_t)(int)d.get("shatters_to", -1);
		m.crumble = chance_of(d, "crumble");
		m.crumbles_into = (int16_t)(int)d.get("crumbles_into", -1);
		m.durability = (uint8_t)std::clamp((int)d.get("durability", 0), 0, 255);
		m.burn_life = (uint8_t)std::clamp((int)d.get("burn_life", 0), 0, 255);
		m.ignite = chance_of(d, "ignite");
		m.burn_speed = chance_of(d, "burn_speed");
		m.burns_to = (int16_t)(int)d.get("burns_to", -1);
		m.burn_gas = (int16_t)(int)d.get("burn_gas", -1);
		m.gas_chance = chance_of(d, "gas_chance");
		m.flame_chance = chance_of(d, "flame_chance");
		m.quench = (bool)d.get("quench", false);
		m.quench_to = (int16_t)(int)d.get("quench_to", -1);
		m.glows = (bool)d.get("glows", false);
		m.hot = (bool)d.get("hot", false);
		m.flame = (bool)d.get("flame", false);
		m.corrosive = (bool)d.get("corrosive", false);
		m.scalds = (bool)d.get("scalds", false);
		m.light = (uint8_t)std::clamp((int)d.get("light", 0), 0, 250);
		m.opacity = (uint8_t)std::clamp((int)d.get("opacity", 0), 0, 30);
		m.structure = (bool)d.get("structure", false);
		m.span = (uint8_t)std::clamp((int)d.get("span", 0), 0, 250);
		m.overhang = (uint8_t)std::clamp((int)d.get("overhang", 0), 0, 250);
		if (d.has("cave")) {
			m.cave = chance_of(d, "cave");
		}
		m.cohesive = (bool)d.get("cohesive", false);
		m.wash_to = (int16_t)(int)d.get("wash_to", -1);
		m.wash = chance_of(d, "wash");
		if (m.flame && fire_id < 0) {
			fire_id = id;
		}
	}
	reacts.clear();
	for (int k = 0; k < reactions.size(); k++) {
		Dictionary d = reactions[k];
		reacts.push_back({ (uint8_t)(int)d.get("a", 0), (uint8_t)(int)d.get("b", 0),
				(uint8_t)(int)d.get("out_a", 0), (uint8_t)(int)d.get("out_b", 0), chance_of(d, "chance") });
	}
	rebuild_reactions();
	rebuild_light();
	rebuild_spans();
}

void CrucibleSim::set_seed(int s) {
	seed = (uint32_t)s * 2654435761u + 1u;
	grng = seed;
}

// A fresh cell's aux: a short-lived gas starts with its life; anything else, 0.
uint8_t CrucibleSim::init_aux(uint8_t m, uint32_t r) const {
	const Mat &M = mats[m];
	if (M.life_max == 0) {
		return 0;
	}
	int span = std::max(1, M.life_max - M.life_min + 1);
	return (uint8_t)std::max(1, M.life_min + (int)(r % (uint32_t)span));
}

// Write a cell from inside a tick (or from game-side effects when cx is null).
void CrucibleSim::put(Ctx *cx, int i, int x, int y, uint8_t m, uint32_t r) {
	uint8_t old = cells[i];
	cells[i] = m;
	aux[i] = init_aux(m, r);
	settle[i] = 0;
	vel[i] = 0;
	stamp[i] = (uint8_t)mark;
	if (cx) {
		cx->next.touch(x, y);
		cx->changed = true;
	} else {
		next.touch(x, y);
		changed = true;
	}
	if (mats[old].glows || mats[m].glows) {
		mark_lava(x, y);
	}
}

// --- Threads ----------------------------------------------------------------------

void CrucibleSim::set_threads(int n) {
	n = std::clamp(n, 1, 16);
	if (n == threads_wanted && (int)workers.size() == n - 1) {
		return;
	}
	stop_pool();
	threads_wanted = n;
	ctxs.resize(n);
	for (Ctx &cx : ctxs) {
		if (cx.next.n != NCH) {
			cx.next.init(W, H);
		}
	}
	if (n > 1) {
		start_pool(n - 1);
	}
}

// Free fall for powders and liquids with open space under them: `accel` in cells a
// second per second, up to `max_speed` cells a second (at most 15 cells a tick). 0
// for either keeps the old one-cell-a-tick fall.
void CrucibleSim::set_fall(double accel, double max_speed) {
	fall_g = std::clamp((int)std::lround(accel * 16.0 / 3600.0), 0, 255);
	fall_max = std::clamp((int)std::lround(max_speed * 16.0 / 60.0), 16, FALL_CAP);
	if (fall_g == 0) {
		fall_max = 16;
	}
}

void CrucibleSim::start_pool(int n) {
	pool_quit = false;
	for (int k = 0; k < n; k++) {
		workers.emplace_back(&CrucibleSim::worker_loop, this, k + 1);
	}
}

void CrucibleSim::stop_pool() {
	{
		std::lock_guard<std::mutex> lock(pool_mutex);
		pool_quit = true;
	}
	pool_cv.notify_all();
	for (auto &t : workers) {
		if (t.joinable()) {
			t.join();
		}
	}
	workers.clear();
	pool_quit = false;
}

void CrucibleSim::worker_loop(int index) {
	int seen = 0;
	while (true) {
		const std::vector<int> *jobs = nullptr;
		{
			std::unique_lock<std::mutex> lock(pool_mutex);
			pool_cv.wait(lock, [&] { return pool_quit || pool_generation != seen; });
			if (pool_quit) {
				return;
			}
			seen = pool_generation;
			jobs = pool_jobs;
		}
		Ctx &cx = ctxs[index];
		while (true) {
			int k = pool_next.fetch_add(1);
			if (k >= (int)jobs->size()) {
				break;
			}
			process_chunk(cx, (*jobs)[k]);
		}
		{
			std::lock_guard<std::mutex> lock(pool_mutex);
			pool_busy--;
		}
		pool_done_cv.notify_one();
	}
}

// One checkerboard pass. Small passes run on this thread: waking workers costs
// more than a dozen chunks of ordinary activity.
void CrucibleSim::run_pass(const std::vector<int> &list) {
	if (list.empty()) {
		return;
	}
	if (workers.empty() || list.size() < 12) {
		for (int c : list) {
			process_chunk(ctxs[0], c);
		}
		return;
	}
	{
		std::lock_guard<std::mutex> lock(pool_mutex);
		pool_jobs = &list;
		pool_next.store(0);
		pool_busy = (int)workers.size();
		pool_generation++;
	}
	pool_cv.notify_all();
	while (true) {
		int k = pool_next.fetch_add(1);
		if (k >= (int)list.size()) {
			break;
		}
		process_chunk(ctxs[0], list[k]);
	}
	std::unique_lock<std::mutex> lock(pool_mutex);
	pool_done_cv.wait(lock, [&] { return pool_busy == 0; });
}

// --- The tick ---------------------------------------------------------------------

void CrucibleSim::step() {
	tick++;
	mark++;
	if (mark > 250) {
		mark = 1;
	}
	mark_tiles(next);
	cur = next;
	next.reset();
	for (Ctx &cx : ctxs) {
		cx.updates = 0;
		cx.reactions = 0;
		cx.ignitions = 0;
		cx.changed = false;
		cx.next.reset();
	}
	// Four passes over a checkerboard of chunks, the column order swapping every
	// tick so nothing drifts one way.
	std::vector<int> pass;
	int chunks = 0;
	int flip = tick & 1;
	for (int p = 0; p < 4; p++) {
		int py = 1 - (p >> 1);
		int px = (p & 1) ^ flip;
		pass.clear();
		for (int cy = CH - 1 - ((CH - 1 - py) & 1); cy >= 0; cy -= 2) {
			for (int cxi = px; cxi < CW; cxi += 2) {
				int c = cy * CW + cxi;
				if (cur.x1[c] >= 0) {
					pass.push_back(c);
				}
			}
		}
		chunks += (int)pass.size();
		run_pass(pass);
	}
	int updates = 0;
	for (Ctx &cx : ctxs) {
		next.merge(cx.next);
		updates += cx.updates;
		reactions_total += cx.reactions;
		ignitions_total += cx.ignitions;
		if (cx.changed) {
			changed = true;
		}
	}
	stat_chunks = chunks;
	stat_updates = updates;
	step_particles();
}

void CrucibleSim::process_chunk(Ctx &cx, int c) {
	cx.rng = hash3(seed, (uint32_t)tick, (uint32_t)c);
	int cyi = c / CW;
	int cxi = c % CW;
	int gx = cxi << CSHIFT;
	int gy = cyi << CSHIFT;
	int x0 = std::max(std::max(cur.x0[c] - 1, gx), 2);
	int x1 = std::min(std::min(cur.x1[c] + 1, gx + CS - 1), W - 3);
	int y0 = std::max(std::max(cur.y0[c] - 1, gy), 2);
	int y1 = std::min(std::min(cur.y1[c] + 1, gy + CS - 1), H - 3);
	const uint8_t mk = (uint8_t)mark;
	for (int y = y1; y >= y0; y--) {
		int row = y * W;
		bool fwd = ((y + tick) & 1) == 0;
		for (int k = 0; k <= x1 - x0; k++) {
			int x = fwd ? x0 + k : x1 - k;
			int i = row + x;
			uint8_t m = cells[i];
			if (stamp[i] == mk) {
				continue;
			}
			uint8_t kind = mats[m].kind;
			// Still things sleep, unless they're burning.
			if (kind == K_EMPTY || (kind == K_STATIC && aux[i] == 0)) {
				continue;
			}
			update_cell(cx, i, x, y, m);
			cx.updates++;
		}
	}
}

void CrucibleSim::update_cell(Ctx &cx, int i, int x, int y, uint8_t m) {
	uint32_t r = lcg(cx.rng);
	int d = (r & 0x10000) ? 1 : -1;
	const Mat &M = mats[m];
	// Burning: spreads, throws flames and smoke, burns down, or gets put out.
	if (M.burn_life && aux[i]) {
		if (burn(cx, i, x, y, m, r)) {
			return;
		}
	}
	// Hot things (lava, fire) try to light one neighbour each update.
	if (M.hot) {
		heat_neighbour(cx, i, x, y, r);
	}
	// Reactions with the four neighbours (up, down, left, right).
	if (M.reactive) {
		const int offs[4] = { -W, W, -1, 1 };
		const int ox[4] = { 0, 0, -1, 1 };
		const int oy[4] = { -1, 1, 0, 0 };
		for (int k = 0; k < 4; k++) {
			int j = i + offs[k];
			uint8_t n = cells[j];
			int ri = react_idx[m * 256 + n];
			if (ri < 0) {
				continue;
			}
			const Reaction &R = reacts[ri];
			if (!roll(cx.rng, R.chance)) {
				continue;
			}
			int jx = x + ox[k];
			int jy = y + oy[k];
			put(&cx, i, x, y, R.out_a, lcg(cx.rng));
			put(&cx, j, jx, jy, R.out_b, lcg(cx.rng));
			if (mats[m].glows || mats[n].glows) {
				mark_lava(x, y);
				mark_lava(jx, jy);
			}
			cx.reactions++;
			return;
		}
	}
	switch (M.kind) {
		case K_POWDER:
			if (settle[i] > tick) {
				cx.next.touch(x, y); // stay awake to fall when the hold runs out
				return;
			}
			powder(cx, i, x, y, m, d);
			return;
		case K_LIQUID:
			liquid(cx, i, x, y, m, d, r);
			return;
		case K_GAS:
			gas(cx, i, x, y, m, d, r);
			return;
		default:
			return;
	}
}

// Light one random neighbour (of eight) if it can burn.
void CrucibleSim::heat_neighbour(Ctx &cx, int i, int x, int y, uint32_t r) {
	int k = (int)((r >> 9) & 7);
	int nx = x + N8X[k];
	int ny = y + N8Y[k];
	int j = ny * W + nx;
	const Mat &N = mats[cells[j]];
	if (N.burn_life && aux[j] == 0 && roll(cx.rng, N.ignite)) {
		aux[j] = N.burn_life;
		cx.next.touch(nx, ny);
		cx.changed = true;
		cx.ignitions++;
	}
}

// A burning cell. Returns true when it has changed into something else (burnt out,
// or put out and so done for this tick).
bool CrucibleSim::burn(Ctx &cx, int i, int x, int y, uint8_t m, uint32_t r) {
	const Mat &M = mats[m];
	cx.next.touch(x, y); // stays awake while it burns
	cx.changed = true;
	// Water beside it puts it out, and turns to steam doing it.
	const int offs[4] = { -W, W, -1, 1 };
	const int ox[4] = { 0, 0, -1, 1 };
	const int oy[4] = { -1, 1, 0, 0 };
	for (int k = 0; k < 4; k++) {
		int j = i + offs[k];
		const Mat &N = mats[cells[j]];
		if (N.quench) {
			aux[i] = 0;
			if (N.quench_to >= 0) {
				put(&cx, j, x + ox[k], y + oy[k], (uint8_t)N.quench_to, lcg(cx.rng));
			}
			return true;
		}
	}
	// Fire needs air: with no open side it goes out now and then (so buried or
	// flooded coal stops burning), and meanwhile neither spreads nor burns down.
	if (!thin(cells[i - W]) && !thin(cells[i + W]) && !thin(cells[i - 1]) && !thin(cells[i + 1])) {
		if ((lcg(cx.rng) & 31u) == 0) {
			aux[i] = 0;
		}
		return false;
	}
	// Spread: try one neighbour of eight.
	heat_neighbour(cx, i, x, y, lcg(cx.rng));
	// Flames and fumes go into an open neighbour, above if it can.
	auto emit = [&](uint8_t what) {
		const int order[4] = { 0, 2, 3, 1 }; // up, left, right, down
		int start = (int)(lcg(cx.rng) & 1); // up first most of the time
		for (int n = start; n < 4 + start; n++) {
			int k = order[n % 4];
			int nx = x + N8X[k];
			int ny = y + N8Y[k];
			int j = ny * W + nx;
			if (mats[cells[j]].kind == K_EMPTY) {
				put(&cx, j, nx, ny, what, lcg(cx.rng));
				return;
			}
		}
	};
	if (fire_id >= 0 && roll(cx.rng, M.flame_chance)) {
		emit((uint8_t)fire_id);
	}
	if (M.burn_gas >= 0 && roll(cx.rng, M.gas_chance)) {
		emit((uint8_t)M.burn_gas);
	}
	// Burn down.
	if (roll(cx.rng, M.burn_speed)) {
		aux[i]--;
		if (aux[i] == 0) {
			uint8_t to = M.burns_to >= 0 ? (uint8_t)M.burns_to : AIR;
			put(&cx, i, x, y, to, lcg(cx.rng));
			if (to == AIR && mats[cells[i - W]].loosens_to >= 0) {
				loosen_check(&cx, i - W, x, y - 1);
			}
			return true;
		}
	}
	return false;
}

// Powders fall, then slip diagonally, sinking through anything thinner than they are.
void CrucibleSim::powder(Ctx &cx, int i, int x, int y, uint8_t m, int d) {
	const int16_t dens = mats[m].density;
	auto sinks = [&](uint8_t t) {
		const Mat &T = mats[t];
		return T.kind == K_EMPTY || ((T.kind == K_LIQUID || T.kind == K_GAS) && T.density < dens);
	};
	int b = i + W;
	if (thin(cells[b])) {
		fall(cx, i, x, y);
		return;
	}
	vel[i] = 0;
	if (sinks(cells[b])) {
		swap_cells(cx, i, b, x, y, x, y + 1);
		return;
	}
	if (sinks(cells[b + d]) && open(i + d)) {
		swap_cells(cx, i, b + d, x, y, x + d, y + 1);
		return;
	}
	if (sinks(cells[b - d]) && open(i - d)) {
		swap_cells(cx, i, b - d, x, y, x - d, y + 1);
	}
}

// A powder or liquid with open space (air or gas) under it: it gains fall_g of
// speed and drops as many cells as that carries it (at least one), stopping above
// anything that isn't open. It keeps its speed for the next tick; it loses it when
// it lands (powder, liquid) or meets a liquid (it sinks one cell a tick).
int CrucibleSim::fall(Ctx &cx, int i, int x, int y) {
	int v = std::min((int)vel[i] + fall_g, fall_max);
	int n = std::max(1, v >> 4);
	int k = 1;
	while (k < n && y + k + 1 < H - 2 && thin(cells[i + (k + 1) * W])) {
		k++;
	}
	int j = i + k * W;
	swap_cells(cx, i, j, x, y, x, y + k);
	vel[j] = (uint8_t)v;
	return k;
}

// Liquids fall, slip diagonally, then spread sideways. They pass through gases and
// sink through lighter liquids.
void CrucibleSim::liquid(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r) {
	const Mat &M = mats[m];
	if (M.slow > 1 && (tick % M.slow) != 0) {
		cx.next.touch(x, y); // sluggish: waits for its tick, but stays awake
		return;
	}
	auto enters = [&](uint8_t t) {
		const Mat &T = mats[t];
		return T.kind == K_EMPTY || T.kind == K_GAS || (T.kind == K_LIQUID && T.density < M.density);
	};
	int b = i + W;
	if (thin(cells[b])) {
		int k = fall(cx, i, x, y);
		if (M.glows) {
			mark_lava(x, y);
			mark_lava(x, y + k);
		}
		return;
	}
	vel[i] = 0;
	if (enters(cells[b])) {
		move_liquid(cx, i, b, x, y, x, y + 1, m);
		return;
	}
	if (enters(cells[b + d]) && open(i + d)) {
		move_liquid(cx, i, b + d, x, y, x + d, y + 1, m);
		return;
	}
	if (enters(cells[b - d]) && open(i - d)) {
		move_liquid(cx, i, b - d, x, y, x - d, y + 1, m);
		return;
	}
	spread(cx, i, x, y, m, d, r);
}

// Sideways movement for a liquid that can't fall: head for a drop within `look`
// cells (moving at most `max_step`); with more of the same liquid on top, spread as
// far as `max_step`; a surface cell with room beside it wanders now and then, which
// levels shallow slopes. A cell with no free neighbour lets its chunk sleep.
void CrucibleSim::spread(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r) {
	const Mat &M = mats[m];
	const int look = M.look;
	const int max_step = std::max(1, (int)M.max_step);
	int dd = d;
	bool free_side = false;
	for (int p = 0; p < 2; p++) {
		int j = i;
		for (int s = 1; s <= look; s++) {
			j += dd;
			if (!thin(cells[j])) {
				break;
			}
			if (s == 1) {
				free_side = true;
			}
			if (thin(cells[j + W])) {
				int k = std::min(s, max_step);
				move_liquid(cx, i, i + dd * k, x, y, x + dd * k, y, m);
				return;
			}
		}
		dd = -dd;
	}
	if (!free_side) {
		return;
	}
	if (cells[i - W] == m) {
		dd = d;
		for (int p = 0; p < 2; p++) {
			int best = -1;
			int best_s = 0;
			int j = i;
			for (int s = 1; s <= max_step; s++) {
				j += dd;
				if (!thin(cells[j])) {
					break;
				}
				best = j;
				best_s = s;
			}
			if (best >= 0) {
				move_liquid(cx, i, best, x, y, x + dd * best_s, y, m);
				return;
			}
			dd = -dd;
		}
		return;
	}
	if (((r >> 20) & ((1u << M.wander_bits) - 1u)) == 0) {
		if (thin(cells[i + d])) {
			move_liquid(cx, i, i + d, x, y, x + d, y, m);
			return;
		}
		if (thin(cells[i - d])) {
			move_liquid(cx, i, i - d, x, y, x - d, y, m);
			return;
		}
	}
	cx.next.touch(x, y);
}

void CrucibleSim::move_liquid(Ctx &cx, int i, int j, int x, int y, int x2, int y2, uint8_t m) {
	if (mats[m].glows) {
		mark_lava(x, y);
		mark_lava(x2, y2);
	}
	swap_cells(cx, i, j, x, y, x2, y2);
}

// Gases: short-lived ones count their life down and expire; steam ages through
// its stages; then they rise (bubbling up through liquids) or sink, slip
// diagonally into open air, and drift sideways now and then.
void CrucibleSim::gas(Ctx &cx, int i, int x, int y, uint8_t m, int d, uint32_t r) {
	const Mat &M = mats[m];
	if (M.life_max > 0) {
		if (aux[i] == 0) {
			aux[i] = init_aux(m, r);
		}
		if (M.life_decay >= 256 || ((r >> 3) & 255u) < M.life_decay) {
			aux[i]--;
			if (aux[i] == 0) {
				int to = M.expires_to;
				if (M.expires_alt >= 0 && roll(cx.rng, M.alt_chance)) {
					to = M.expires_alt;
				}
				put(&cx, i, x, y, to >= 0 ? (uint8_t)to : AIR, lcg(cx.rng));
				return;
			}
		}
	}
	if (M.age_to >= 0 && M.age_chance > 0 && ((r >> 17) % M.age_chance) == 0) {
		uint8_t to = (uint8_t)M.age_to;
		cells[i] = to;
		cx.changed = true;
		if (mats[to].kind != K_GAS) {
			aux[i] = init_aux(to, r);
			stamp[i] = (uint8_t)mark;
			cx.next.touch(x, y);
			return;
		}
		m = to;
	}
	if (M.vents && y <= 3) {
		put(&cx, i, x, y, AIR, 0);
		return;
	}
	const Mat &G = mats[m];
	int b = G.buoyancy;
	bool moves = b != 0 && (std::abs(b) >= 8 || (int)((r >> 25) & 7u) < std::abs(b));
	if (moves) {
		int dir = b > 0 ? -1 : 1;
		int u = i + dir * W;
		uint8_t t = cells[u];
		const Mat &T = mats[t];
		// Into open air; a rising gas also bubbles up through liquids, and gases
		// sort themselves by density (fumes sink under smoke, smoke rises over them).
		bool through = T.kind == K_EMPTY || (b > 0 && T.kind == K_LIQUID && T.density > G.density) ||
				(T.kind == K_GAS && t != m && (b > 0 ? T.density > G.density : T.density < G.density));
		if (through) {
			swap_cells(cx, i, u, x, y, x, y + dir);
			return;
		}
		if (mats[cells[u + d]].kind == K_EMPTY && open(i + d)) {
			swap_cells(cx, i, u + d, x, y, x + d, y + dir);
			return;
		}
		if (mats[cells[u - d]].kind == K_EMPTY && open(i - d)) {
			swap_cells(cx, i, u - d, x, y, x - d, y + dir);
			return;
		}
	}
	if (mats[cells[i + d]].kind == K_EMPTY && ((r >> 11) & 255u) < G.drift) {
		swap_cells(cx, i, i + d, x, y, x + d, y);
		return;
	}
	cx.next.touch(x, y);
}

void CrucibleSim::swap_cells(Ctx &cx, int i, int j, int x, int y, int x2, int y2) {
	uint8_t a = cells[i];
	uint8_t b = cells[j];
	cells[i] = b;
	cells[j] = a;
	std::swap(aux[i], aux[j]);
	std::swap(settle[i], settle[j]);
	std::swap(vel[i], vel[j]);
	stamp[i] = (uint8_t)mark;
	stamp[j] = (uint8_t)mark;
	cx.next.touch(x, y);
	cx.next.touch(x2, y2);
	cx.changed = true;
	if (mats[b].kind == K_EMPTY && mats[cells[i - W]].loosens_to >= 0) {
		loosen_check(&cx, i - W, x, y - 1);
	}
}

// A static cell that comes loose (settled dirt) does so with nothing under it and
// nothing either side.
void CrucibleSim::loosen_check(Ctx *cx, int i, int x, int y) {
	int to = mats[cells[i]].loosens_to;
	if (to < 0 || settle[i] > tick || held[i]) {
		return;
	}
	if (solid(cells[i + W]) || solid(cells[i - 1]) || solid(cells[i + 1])) {
		return;
	}
	cells[i] = (uint8_t)to; // aux (burning) carries over
	if (cx) {
		cx->next.touch(x, y);
		cx->changed = true;
	} else {
		next.touch(x, y);
		changed = true;
	}
}

// --- Particles ----------------------------------------------------------------------

void CrucibleSim::spawn(float x, float y, float vx, float vy, uint8_t m, uint8_t a) {
	if (parts.size() >= 20000) {
		return;
	}
	parts.push_back({ x, y, vx, vy, m, a });
}

void CrucibleSim::add_particle(double x, double y, double vx, double vy, int m) {
	if (m < 0 || m > 255) {
		return;
	}
	spawn((float)x, (float)y, (float)vx, (float)vy, (uint8_t)m, init_aux((uint8_t)m, lcg(grng)));
}

// A particle comes to rest in the last open cell it passed through (or the first
// open one above, if that's filled), and becomes part of the grid again.
void CrucibleSim::land(Particle &p, int px, int py) {
	for (int up = 0; up < 6; up++) {
		int yy = py - up;
		if (px < 2 || px >= W - 2 || yy < 2 || yy >= H - 2) {
			return;
		}
		int i = yy * W + px;
		if (thin(cells[i])) {
			uint8_t old = cells[i];
			cells[i] = p.mat;
			aux[i] = p.aux;
			settle[i] = 0;
			next.touch(px, yy);
			changed = true;
			if (mats[old].glows || mats[p.mat].glows) {
				mark_lava(px, yy);
			}
			return;
		}
	}
}

void CrucibleSim::step_particles() {
	if (parts.empty()) {
		return;
	}
	size_t keep = 0;
	for (size_t k = 0; k < parts.size(); k++) {
		Particle p = parts[k];
		p.vy = std::min(p.vy + GRAVITY, MAX_SPEED);
		p.vx = std::clamp(p.vx * 0.995f, -MAX_SPEED, MAX_SPEED);
		int steps = (int)std::ceil(std::max(std::fabs(p.vx), std::fabs(p.vy)));
		steps = std::max(steps, 1);
		float sx = p.vx / steps;
		float sy = p.vy / steps;
		bool alive = true;
		for (int s = 0; s < steps; s++) {
			float nx = p.x + sx;
			float ny = p.y + sy;
			int cx = (int)std::floor(nx);
			int cy = (int)std::floor(ny);
			if (cx < 2 || cx >= W - 2 || cy < 2 || cy >= H - 2) {
				alive = false;
				break;
			}
			if (!thin(cells[cy * W + cx])) {
				land(p, (int)std::floor(p.x), (int)std::floor(p.y));
				alive = false;
				break;
			}
			p.x = nx;
			p.y = ny;
		}
		if (alive) {
			parts[keep++] = p;
		}
	}
	parts.resize(keep);
	changed = true;
}

// --- Game-side access ---------------------------------------------------------------

int CrucibleSim::get_cell(int x, int y) const {
	if (x < 0 || y < 0 || x >= W || y >= H) {
		return BEDROCK;
	}
	return cells[y * W + x];
}

int CrucibleSim::get_aux(int x, int y) const {
	if (x < 0 || y < 0 || x >= W || y >= H) {
		return 0;
	}
	return aux[y * W + x];
}

// Write a cell from game code (drills, hoppers, buildings, the brush). Wakes the
// area and lets anything that was leaning on this cell come loose.
void CrucibleSim::set_cell(int x, int y, int m) {
	if (x < 0 || y < 0 || x >= W || y >= H || m < 0 || m > 255) {
		return;
	}
	int i = y * W + x;
	uint8_t old = cells[i];
	if (old == m) {
		return;
	}
	cells[i] = (uint8_t)m;
	aux[i] = init_aux((uint8_t)m, lcg(grng));
	settle[i] = 0;
	vel[i] = 0;
	next.touch(x, y);
	changed = true;
	if (mats[old].glows || mats[m].glows) {
		mark_lava(x, y);
	}
	if (!solid((uint8_t)m)) {
		if (y > 2) {
			loosen_check(nullptr, i - W, x, y - 1);
		}
		if (x > 2) {
			loosen_check(nullptr, i - 1, x - 1, y);
		}
		if (x < W - 3) {
			loosen_check(nullptr, i + 1, x + 1, y);
		}
	}
}

// Set a cell burning, if it can burn.
void CrucibleSim::ignite(int x, int y) {
	if (x < 2 || y < 2 || x >= W - 2 || y >= H - 2) {
		return;
	}
	int i = y * W + x;
	const Mat &M = mats[cells[i]];
	if (M.burn_life && aux[i] == 0) {
		aux[i] = M.burn_life;
		next.touch(x, y);
		changed = true;
		ignitions_total++;
	}
}

// The grid as the renderer sees it: cells, with flying particles drawn over open ones.
PackedByteArray CrucibleSim::get_cells() const {
	PackedByteArray out;
	out.resize(W * H);
	uint8_t *o = out.ptrw();
	memcpy(o, cells.data(), W * H);
	for (const Particle &p : parts) {
		int x = (int)p.x;
		int y = (int)p.y;
		if (x >= 0 && x < W && y >= 0 && y < H && thin(o[y * W + x])) {
			o[y * W + x] = p.mat;
		}
	}
	return out;
}

PackedByteArray CrucibleSim::get_aux_bytes() const {
	PackedByteArray out;
	out.resize(W * H);
	uint8_t *o = out.ptrw();
	memcpy(o, aux.data(), W * H);
	for (const Particle &p : parts) {
		int x = (int)p.x;
		int y = (int)p.y;
		if (x >= 0 && x < W && y >= 0 && y < H && thin(cells[y * W + x])) {
			o[y * W + x] = p.aux;
		}
	}
	return out;
}

void CrucibleSim::set_cells(const PackedByteArray &data) {
	if (data.size() != W * H) {
		UtilityFunctions::push_error("CrucibleSim.set_cells: expected ", W * H, " bytes, got ", data.size());
		return;
	}
	memcpy(cells.data(), data.ptr(), W * H);
	std::fill(aux.begin(), aux.end(), (uint8_t)0);
	std::fill(settle.begin(), settle.end(), 0);
	std::fill(vel.begin(), vel.end(), (uint8_t)0);
	std::fill(tile_dirty.begin(), tile_dirty.end(), (uint8_t)1);
	std::fill(corr_valid.begin(), corr_valid.end(), (uint8_t)0);
	parts.clear();
	for (auto &f : lava_dirty) {
		f.store(1);
	}
	changed = true;
}

void CrucibleSim::touch_rect(int x0, int y0, int x1, int y1) {
	x0 = std::max(x0, 0);
	y0 = std::max(y0, 0);
	x1 = std::min(x1, W - 1);
	y1 = std::min(y1, H - 1);
	for (int cy = y0 >> CSHIFT; cy <= (y1 >> CSHIFT); cy++) {
		for (int cxi = x0 >> CSHIFT; cxi <= (x1 >> CSHIFT); cxi++) {
			int c = cy * CW + cxi;
			next.x0[c] = std::min(next.x0[c], std::max(x0, cxi << CSHIFT));
			next.x1[c] = std::max(next.x1[c], std::min(x1, (cxi << CSHIFT) + CS - 1));
			next.y0[c] = std::min(next.y0[c], std::max(y0, cy << CSHIFT));
			next.y1[c] = std::max(next.y1[c], std::min(y1, (cy << CSHIFT) + CS - 1));
		}
	}
	changed = true;
}

// --- Slow hazards -------------------------------------------------------------------

// The old dirt erosion (kept for tests): exposed cells that erode trickle loose in place.
void CrucibleSim::erode(int samples, int y_min, int y_max) {
	int span = std::max(1, y_max - y_min);
	for (int s = 0; s < samples; s++) {
		int x = 2 + (int)((lcg(grng) >> 6) % (uint32_t)(W - 4));
		int y = y_min + (int)((lcg(grng) >> 6) % (uint32_t)span);
		if (y < 2 || y >= H - 2) {
			continue;
		}
		int i = y * W + x;
		int to = mats[cells[i]].erodes_to;
		if (to < 0 || settle[i] > tick || held[i]) {
			continue;
		}
		if (cells[i + W] == AIR || (cells[i - 1] == AIR && cells[i + W - 1] == AIR) || (cells[i + 1] == AIR && cells[i + W + 1] == AIR)) {
			cells[i] = (uint8_t)to;
			next.touch(x, y);
			changed = true;
			eroded++;
		}
	}
}

// Freshly dug: the solid cells within `radius` of (x, y) hold still for `ticks`.
// Weathering, erosion and loosening pass them over and held powders don't fall,
// so there's time to shore a new hole up. Liquids aren't held.
void CrucibleSim::settle_around(int x, int y, int radius, int ticks) {
	int until = tick + std::max(0, ticks);
	for (int yy = std::max(2, y - radius); yy <= std::min(H - 3, y + radius); yy++) {
		for (int xx = std::max(2, x - radius); xx <= std::min(W - 3, x + radius); xx++) {
			int i = yy * W + xx;
			uint8_t k = mats[cells[i]].kind;
			if ((k == K_STATIC || k == K_POWDER) && settle[i] < until) {
				settle[i] = until;
			}
		}
	}
}

// Ticks left on a cell's hold (0 when it isn't held).
int CrucibleSim::get_settle(int x, int y) const {
	if (x < 0 || y < 0 || x >= W || y >= H) {
		return 0;
	}
	int left = settle[y * W + x] - tick;
	return left > 0 ? left : 0;
}

// Weathering: random cells across the map; one that hangs over open air (a
// ceiling) and crumbles comes away and falls, twice as readily in the middle of an
// open span as at its edge.
int CrucibleSim::weather(int samples) {
	int n = 0;
	for (int s = 0; s < samples; s++) {
		uint32_t r = lcg(grng);
		int x = 2 + (int)((r >> 4) % (uint32_t)(W - 4));
		int y = 3 + (int)((lcg(grng) >> 4) % (uint32_t)(H - 6));
		int i = y * W + x;
		const Mat &M = mats[cells[i]];
		if (M.crumble == 0 || M.kind != K_STATIC || settle[i] > tick || held[i]) {
			continue;
		}
		if (!thin(cells[i + W])) {
			continue;
		}
		uint32_t chance = M.crumble;
		if (thin(cells[i + W - 1]) && thin(cells[i + W + 1])) {
			chance *= 2;
		}
		if (!roll(grng, chance)) {
			continue;
		}
		uint8_t m = cells[i];
		uint8_t into = M.crumbles_into >= 0 ? (uint8_t)M.crumbles_into : m;
		// A burning piece keeps burning on the way down.
		uint8_t a = (M.burn_life && aux[i] && mats[into].burn_life) ? aux[i] : init_aux(into, lcg(grng));
		cells[i] = AIR;
		aux[i] = 0;
		next.touch(x, y);
		changed = true;
		spawn(x + 0.5f, y + 1.05f, (frand(grng) - 0.5f) * 0.1f, 0.1f, into, a);
		if (mats[cells[i - W]].loosens_to >= 0) {
			loosen_check(nullptr, i - W, x, y - 1);
		}
		n++;
	}
	crumbled += n;
	return n;
}

// --- Collapse ------------------------------------------------------------------------

// Ceilings: a static cell with a span, over open space (air, gas or liquid). It
// stands while the open run under it is no wider than its material's span, or
// while it's within its overhang of either end of that run (so a wide ceiling
// goes from the middle and leaves an arch). Solid ground, powder and buildings
// under it hold it up. Held cells (Struts) and freshly dug ground stay put.
// One row: in play a cell that should go does so with COLLAPSE_CHANCE a sweep and
// becomes what it crumbles into, which falls; with to_air (worldgen) it's just
// cleared, so the row above sees the hole straight away. Returns cells that went.
int CrucibleSim::collapse_row(int y, bool to_air) {
	if (y < 2 || y >= H - 3) {
		return 0;
	}
	int n = 0;
	const int below = (y + 1) * W;
	int x = 2;
	while (x < W - 2) {
		if (solid(cells[below + x])) {
			x++;
			continue;
		}
		int a = x;
		while (x < W - 2 && !solid(cells[below + x])) {
			x++;
		}
		int b = x - 1;
		int w = b - a + 1;
		if (w <= min_span && !any_cohesive) {
			continue;
		}
		for (int xx = a; xx <= b; xx++) {
			int i = y * W + xx;
			const Mat &M = mats[cells[i]];
			if (M.span == 0 || M.kind != K_STATIC) {
				continue;
			}
			if (M.cohesive) {
				// Held up only through its own kind: the nearest cell of it along the
				// row that has something under it, walking through nothing else.
				int cap = M.span + 1;
				int dl = cling(i, -1, cap), dr = cling(i, 1, cap);
				int d = std::min(dl, dr);
				if (d <= M.overhang || (dl <= cap && dr <= cap && dl + dr - 1 <= M.span)) {
					continue;
				}
			} else {
				if (w <= M.span) {
					continue;
				}
				int d = std::min(xx - a + 1, b - xx + 1);
				if (d <= M.overhang) {
					continue;
				}
			}
			if (held[i] || settle[i] > tick) {
				continue;
			}
			if (to_air) {
				cells[i] = AIR;
				aux[i] = 0;
				n++;
				continue;
			}
			if (!roll(grng, M.cave)) {
				continue;
			}
			uint8_t m = cells[i];
			int into = M.crumbles_into >= 0 ? M.crumbles_into : (M.loosens_to >= 0 ? M.loosens_to : m);
			// A burning piece keeps burning on the way down.
			uint8_t a2 = (M.burn_life && aux[i] && mats[into].burn_life) ? aux[i] : init_aux((uint8_t)into, lcg(grng));
			if (M.glows) {
				mark_lava(xx, y);
			}
			if (mats[into].kind == K_POWDER) {
				cells[i] = (uint8_t)into;
				aux[i] = a2;
			} else {
				cells[i] = AIR;
				aux[i] = 0;
				spawn(xx + 0.5f, y + 0.6f, 0.0f, 0.2f, (uint8_t)into, a2);
			}
			settle[i] = 0;
			next.touch(xx, y);
			changed = true;
			last_cave_x = xx;
			last_cave_y = y;
			n++;
		}
	}
	return n;
}

// How far along the row (step -1 or 1) the nearest cell holding cohesive cell i up
// is: one of its own kind with something solid under it, or rock that never gives
// way (no span: bedrock, obsidian, glimmer, buildings). Walks only through its own
// kind, and past gaps with its own kind right above them; cap + 1 when there's
// none within cap.
int CrucibleSim::cling(int i, int step, int cap) const {
	const uint8_t m = cells[i];
	int x = i % W;
	for (int k = 1; k <= cap; k++) {
		int xx = x + step * k;
		if (xx < 2 || xx >= W - 2) {
			return k; // the map's edge holds
		}
		int j = i + step * k;
		uint8_t c = cells[j];
		if (c != m) {
			const Mat &C = mats[c];
			if (C.kind == K_STATIC && C.span == 0) {
				return k;
			}
			// A gap its own kind bridges from just above (a cell weathered out of a
			// thick roof) doesn't cut the row.
			if (cells[j - W] == m) {
				continue;
			}
			return cap + 1;
		}
		if (solid(cells[j + W])) {
			return k;
		}
	}
	return cap + 1;
}

// Water wearing rock away: random cells across the map; one that washes and has a
// liquid that isn't hot beside it (or above or below) turns into what it washes to,
// with its material's chance. Held and freshly dug cells are passed over.
int CrucibleSim::wash(int samples) {
	int n = 0;
	for (int s = 0; s < samples; s++) {
		int x = 2 + (int)((lcg(grng) >> 4) % (uint32_t)(W - 4));
		int y = 3 + (int)((lcg(grng) >> 4) % (uint32_t)(H - 6));
		int i = y * W + x;
		const Mat &M = mats[cells[i]];
		if (M.wash == 0 || M.wash_to < 0 || held[i] || settle[i] > tick) {
			continue;
		}
		const int offs[4] = { -W, W, -1, 1 };
		bool wet = false;
		for (int k = 0; k < 4; k++) {
			const Mat &N = mats[cells[i + offs[k]]];
			if (N.kind == K_LIQUID && !N.hot) {
				wet = true;
				break;
			}
		}
		if (!wet || !roll(grng, M.wash)) {
			continue;
		}
		cells[i] = (uint8_t)M.wash_to;
		aux[i] = 0;
		next.touch(x, y);
		changed = true;
		if (mats[cells[i - W]].loosens_to >= 0) {
			loosen_check(nullptr, i - W, x, y - 1);
		}
		n++;
	}
	washed += n;
	return n;
}

// The collapse sweep: `rows` more rows, bottom up, wrapping round the map.
int CrucibleSim::collapse(int rows) {
	int n = 0;
	for (int k = 0; k < std::clamp(rows, 1, H); k++) {
		n += collapse_row(collapse_cursor, false);
		collapse_cursor--;
		if (collapse_cursor < 2) {
			collapse_cursor = H - 4;
		}
	}
	caved += n;
	return n;
}

// Worldgen: one pass from the bottom up that clears everything the collapse rule
// would bring down, so caves start out as arches that stand. Returns cells cleared.
int CrucibleSim::stabilize() {
	int n = 0;
	for (int y = H - 4; y >= 2; y--) {
		n += collapse_row(y, true);
	}
	if (n > 0) {
		touch_rect(0, 0, W - 1, H - 1);
	}
	return n;
}

// A Strut's anchor: the cells within r of (x, y) are held (delta 1) or let go (-1).
void CrucibleSim::hold_circle(int x, int y, int r, int delta) {
	for (int yy = std::max(0, y - r); yy <= std::min(H - 1, y + r); yy++) {
		for (int xx = std::max(0, x - r); xx <= std::min(W - 1, x + r); xx++) {
			int dx = xx - x, dy = yy - y;
			if (dx * dx + dy * dy > r * r) {
				continue;
			}
			int i = yy * W + xx;
			held[i] = (uint8_t)std::clamp((int)held[i] + delta, 0, 255);
		}
	}
}

int CrucibleSim::get_held(int x, int y) const {
	if (x < 0 || y < 0 || x >= W || y >= H) {
		return 0;
	}
	return held[y * W + x];
}

// Circles (x, y, r) where tremors crumble nothing (Tremor Dampers).
void CrucibleSim::set_shields(const PackedInt32Array &circles) {
	shields.assign(circles.ptr(), circles.ptr() + circles.size());
}

// Crumble up to `wanted` cells that crumble (stone) beside open air.
int CrucibleSim::tremor(int wanted, int y_min, int y_max) {
	int done = 0;
	int tries = 0;
	int span = std::max(1, y_max - y_min);
	while (done < wanted && tries < 60000) {
		tries++;
		int x = 3 + (int)((lcg(grng) >> 6) % (uint32_t)(W - 6));
		int y = y_min + (int)((lcg(grng) >> 6) % (uint32_t)span);
		if (y < 2 || y >= H - 2) {
			continue;
		}
		int i = y * W + x;
		int to = mats[cells[i]].crumbles_to;
		if (to < 0) {
			continue;
		}
		bool shielded = false;
		for (size_t k = 0; k + 2 < shields.size(); k += 3) {
			int dx = x - shields[k], dy = y - shields[k + 1];
			if (dx * dx + dy * dy <= shields[k + 2] * shields[k + 2]) {
				shielded = true;
				break;
			}
		}
		if (shielded) {
			continue;
		}
		if (cells[i - W] == AIR || cells[i + W] == AIR || cells[i - 1] == AIR || cells[i + 1] == AIR) {
			cells[i] = (uint8_t)to;
			next.touch(x, y);
			changed = true;
			done++;
		}
	}
	return done;
}

// A blast at (x, y): rays go out in every direction, each with power x radius of
// energy. A ray passes open cells for free, breaks anything whose durability the
// blast's power beats (paying durability + 1), and stops at anything tougher, so
// hard rock shields what's behind it. Broken cells fly out as debris (statics as
// what they shatter to), the middle flashes into fire, and what can burn nearby
// catches. Returns how many cells broke.
int CrucibleSim::explode(int x, int y, double radius, int power) {
	float rad = (float)std::clamp(radius, 1.0, 64.0);
	int bx0 = std::max(2, x - (int)rad - 1), bx1 = std::min(W - 3, x + (int)rad + 1);
	int by0 = std::max(2, y - (int)rad - 1), by1 = std::min(H - 3, y + (int)rad + 1);
	int bw = bx1 - bx0 + 1;
	int bh = by1 - by0 + 1;
	if (bw <= 0 || bh <= 0) {
		return 0;
	}
	std::vector<uint8_t> hit(bw * bh, 0);
	int rays = std::max(24, (int)(rad * 8.0f));
	int broken = 0;
	for (int k = 0; k < rays; k++) {
		float ang = (6.2831853f * k) / rays;
		float dx = std::cos(ang);
		float dy = std::sin(ang);
		float energy = (float)power * rad;
		int lastx = -1, lasty = -1;
		for (float t = 0.0f; t <= rad; t += 0.5f) {
			int cx = (int)std::floor(x + 0.5f + dx * t);
			int cy = (int)std::floor(y + 0.5f + dy * t);
			if (cx == lastx && cy == lasty) {
				continue;
			}
			lastx = cx;
			lasty = cy;
			if (cx < bx0 || cx > bx1 || cy < by0 || cy > by1) {
				break;
			}
			int i = cy * W + cx;
			const Mat &M = mats[cells[i]];
			if (M.kind == K_EMPTY || M.kind == K_GAS) {
				continue;
			}
			if (M.durability >= 255 || (int)M.durability > power) {
				break;
			}
			int hk = (cy - by0) * bw + (cx - bx0);
			if (hit[hk]) {
				continue;
			}
			float cost = (float)M.durability + 1.0f;
			if (energy < cost) {
				break;
			}
			energy -= cost;
			hit[hk] = 1;
			uint8_t m = cells[i];
			int debris = M.kind == K_STATIC ? M.shatters_to : m;
			if (debris >= 0) {
				float speed = (0.8f + power * 0.35f) * (1.0f - t / (rad + 1.0f)) + frand(grng) * 0.6f;
				uint8_t a = 0;
				const Mat &Dm = mats[debris];
				if (Dm.burn_life && ((M.burn_life && aux[i]) || frand(grng) < 0.35f)) {
					a = Dm.burn_life; // embers
				} else {
					a = init_aux((uint8_t)debris, lcg(grng));
				}
				spawn(cx + 0.5f, cy + 0.5f, dx * speed, dy * speed - 0.6f, (uint8_t)debris, a);
			}
			if (M.glows) {
				mark_lava(cx, cy);
			}
			cells[i] = AIR;
			aux[i] = 0;
			broken++;
		}
	}
	// The flash: fire in the open middle, and anything that burns nearby catches.
	float flash = rad * 0.45f;
	for (int yy = by0; yy <= by1; yy++) {
		for (int xx = bx0; xx <= bx1; xx++) {
			float ddx = xx - x, ddy = yy - y;
			float dist = std::sqrt(ddx * ddx + ddy * ddy);
			if (dist > rad) {
				continue;
			}
			int i = yy * W + xx;
			const Mat &M = mats[cells[i]];
			if (fire_id >= 0 && dist <= flash && M.kind == K_EMPTY && frand(grng) < 0.45f) {
				cells[i] = (uint8_t)fire_id;
				aux[i] = init_aux((uint8_t)fire_id, lcg(grng));
			} else if (M.burn_life && aux[i] == 0 && frand(grng) < 0.5f * (1.0f - dist / (rad + 1.0f))) {
				aux[i] = M.burn_life;
				ignitions_total++;
			}
		}
	}
	touch_rect(bx0 - 1, by0 - 1, bx1 + 1, by1 + 1);
	// Whatever leant on what's gone comes loose.
	for (int yy = by0; yy <= by1; yy++) {
		for (int xx = bx0; xx <= bx1; xx++) {
			int i = yy * W + xx;
			if (mats[cells[i]].loosens_to >= 0) {
				loosen_check(nullptr, i, xx, yy);
			}
		}
	}
	return broken;
}

// --- Heat map ------------------------------------------------------------------------

// One byte per 4x4 block: 255 where something that glows (lava) is.
void CrucibleSim::refresh_heat(bool all) {
	const int BW = W / 4;
	for (int c = 0; c < NCH; c++) {
		if (!all && lava_dirty[c].load(std::memory_order_relaxed) == 0) {
			continue;
		}
		lava_dirty[c].store(0, std::memory_order_relaxed);
		int gx = (c % CW) << CSHIFT;
		int gy = (c / CW) << CSHIFT;
		for (int by = 0; by < CS / 4; by++) {
			for (int bx = 0; bx < CS / 4; bx++) {
				uint8_t v = 0;
				int x0 = gx + bx * 4;
				int y0 = gy + by * 4;
				for (int yy = y0; yy < y0 + 4 && !v; yy++) {
					const uint8_t *row = &cells[yy * W];
					for (int xx = x0; xx < x0 + 4; xx++) {
						if (mats[row[xx]].glows) {
							v = 255;
							break;
						}
					}
				}
				heat[((gy >> 2) + by) * BW + (gx >> 2) + bx] = v;
			}
		}
		heat_changed = true;
	}
}

PackedByteArray CrucibleSim::get_heat() const {
	PackedByteArray out;
	out.resize((int64_t)heat.size());
	memcpy(out.ptrw(), heat.data(), heat.size());
	return out;
}

// --- Light ----------------------------------------------------------------------------

// Spreads light over 4x4 blocks of cells (the fog maps' blocks, W/4 x H/4), then
// works out the fog maps (a byte per block, 255 or 0). A block is seen when it's lit
// and within sight of one of `sights`; seeing it explores it for good. It shows live
// whenever it's lit and explored. Returns three maps back to back: live, explored
// (`known` plus what was just seen), and seen.
//  - `lights`: (x, y, radius) per light the game places (the Hub, Lamps, pilot lights);
//  - materials with a "light" radius glow by themselves, and so do burning cells;
//  - with `sun` > 0, open cells straight down from the top of the map (through
//    buildings, stopping at anything else) are sunlit with that radius;
//  - `sights`: (x, y, radius) per building watching.
// Radii are in cells. Light fades LSTEP per cell of air (LDIAG diagonally), times
// the average opacity of the block it leaves, so it lights a wall's face and dies a
// few blocks into the rock. Brightness per block is kept for get_light().
PackedByteArray CrucibleSim::light_update(const PackedInt32Array &lights, const PackedInt32Array &sights, int sun, const PackedByteArray &known) {
	const int BW = W / 4, BH = H / 4, N = BW * BH;
	const int CB = CS / 4; // blocks across a chunk
	if ((int)light_lv.size() != N) {
		light_lv.assign(N, 0);
		light_px.assign(N, 0);
		light_cost.assign(N, 0);
		light_stamp.assign(N, 0);
	}
	std::fill(light_lv.begin(), light_lv.end(), (uint16_t)0);
	light_gen++;
	uint8_t mlight[256];
	int reach = std::max(sun, 0);
	for (int m = 0; m < 256; m++) {
		mlight[m] = mats[m].light;
		reach = std::max(reach, (int)mats[m].light);
	}
	const int32_t *lp = lights.ptr();
	for (int k = 0; k + 2 < (int)lights.size(); k += 3) {
		reach = std::max(reach, (int)lp[k + 2]);
	}
	reach = std::min(reach, LIGHT_MAX_R);
	const int ring = (reach + CS - 1) / CS; // chunks light can cross
	// Only chunks near something watched, or explored and in the view
	// (set_light_view), are worth lighting: those, and any source close enough to
	// reach them.
	std::vector<uint8_t> hit(NCH, 0), near(NCH, 0);
	if (known.size() >= N) {
		const uint8_t *kn = known.ptr();
		int kx0 = std::clamp(view_x0 >> 2, 0, BW), kx1 = std::clamp((view_x1 + 3) >> 2, 0, BW);
		int ky0 = std::clamp(view_y0 >> 2, 0, BH), ky1 = std::clamp((view_y1 + 3) >> 2, 0, BH);
		for (int ky = ky0; ky < ky1; ky++) {
			for (int kx = kx0; kx < kx1; kx++) {
				if (kn[ky * BW + kx]) {
					hit[(ky / CB) * CW + (kx / CB)] = 1;
				}
			}
		}
	}
	// What buildings watch, and where the game's own lights sit.
	for (const PackedInt32Array *arr : { &sights, &lights }) {
		const int32_t *sp = arr->ptr();
		for (int k = 0; k + 2 < (int)arr->size(); k += 3) {
			int r = arr == &lights ? 0 : sp[k + 2];
			int x0 = std::clamp((sp[k] - r) >> CSHIFT, 0, CW - 1), x1 = std::clamp((sp[k] + r) >> CSHIFT, 0, CW - 1);
			int y0 = std::clamp((sp[k + 1] - r) >> CSHIFT, 0, CH - 1), y1 = std::clamp((sp[k + 1] + r) >> CSHIFT, 0, CH - 1);
			for (int cy = y0; cy <= y1; cy++) {
				for (int cx = x0; cx <= x1; cx++) {
					hit[cy * CW + cx] = 1;
				}
			}
		}
	}
	for (int c = 0; c < NCH; c++) {
		if (!hit[c]) {
			continue;
		}
		int cx = c % CW, cy = c / CW;
		for (int yy = std::max(cy - ring, 0); yy <= std::min(cy + ring, CH - 1); yy++) {
			for (int xx = std::max(cx - ring, 0); xx <= std::min(cx + ring, CW - 1); xx++) {
				near[yy * CW + xx] = 1;
			}
		}
	}
	auto near_block = [&](int bx, int by) { return near[(by / CB) * CW + (bx / CB)] != 0; };
	int fire_light = fire_id >= 0 ? mats[fire_id].light : 0;
	auto glow_of = [&](int i) {
		int r = mlight[cells[i]];
		if (fire_light && aux[i] && mats[cells[i]].burn_life) {
			r = std::max(r, fire_light);
		}
		return r;
	};
	// What crossing a block costs: the sum of its 16 cells' opacities (16 for open
	// air), or 16 when anything in it glows (light leaves a glowing cell as if
	// through air). Worked out the first time the spread reaches the block.
	auto cost = [&](int b) -> int {
		if (light_stamp[b] == light_gen) {
			return light_cost[b];
		}
		int bx = b % BW, by = b / BW;
		int sum = 0;
		bool glow = false;
		for (int yy = by * 4; yy < by * 4 + 4; yy++) {
			for (int xx = bx * 4; xx < bx * 4 + 4; xx++) {
				int i = yy * W + xx;
				sum += opq[cells[i]];
				glow = glow || glow_of(i) > 0;
			}
		}
		light_stamp[b] = light_gen;
		light_cost[b] = (uint16_t)(glow ? 16 : sum);
		return light_cost[b];
	};
	int top = 0;
	auto seed = [&](int b, int lv) {
		if (lv <= light_lv[b]) {
			return;
		}
		light_lv[b] = (uint16_t)lv;
		if (lv >= (int)light_buckets.size()) {
			light_buckets.resize(lv + 1);
		}
		light_buckets[lv].push_back(b);
		top = std::max(top, lv);
	};
	for (auto &bk : light_buckets) {
		bk.clear();
	}
	// Glowing materials and burning cells.
	for (int c = 0; c < NCH; c++) {
		if (!near[c]) {
			continue;
		}
		int gx = (c % CW) << CSHIFT, gy = (c / CW) << CSHIFT;
		for (int yy = gy; yy < gy + CS; yy++) {
			for (int xx = gx; xx < gx + CS; xx++) {
				int r = glow_of(yy * W + xx);
				if (r) {
					seed((yy >> 2) * BW + (xx >> 2), std::min(r, LIGHT_MAX_R) * LSTEP);
				}
			}
		}
	}
	for (const Particle &p : parts) {
		int px = (int)p.x, py = (int)p.y;
		if (px >= 0 && py >= 0 && px < W && py < H && mlight[p.mat] && near_block(px >> 2, py >> 2)) {
			seed((py >> 2) * BW + (px >> 2), std::min((int)mlight[p.mat], LIGHT_MAX_R) * LSTEP);
		}
	}
	// The sky, straight down open columns.
	if (sun > 0) {
		int lv = std::min(sun, LIGHT_MAX_R) * LSTEP;
		for (int x = 0; x < W; x++) {
			int last = -1;
			for (int y = 0; y < H; y++) {
				const Mat &M = mats[cells[y * W + x]];
				if (!(M.kind == K_EMPTY || M.kind == K_GAS || M.structure)) {
					break;
				}
				int by = y >> 2;
				if (by != last) {
					last = by;
					if (near_block(x >> 2, by)) {
						seed(by * BW + (x >> 2), lv);
					}
				}
			}
		}
	}
	for (int k = 0; k + 2 < (int)lights.size(); k += 3) {
		int x = lp[k], y = lp[k + 1], r = lp[k + 2];
		if (x >= 0 && y >= 0 && x < W && y < H && r > 0) {
			seed((y >> 2) * BW + (x >> 2), std::min(r, LIGHT_MAX_R) * LSTEP);
		}
	}
	// Brightest first; a block whose level rose after it was queued is skipped.
	static const int DX[8] = { 1, -1, 0, 0, 1, 1, -1, -1 };
	static const int DY[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };
	for (int lv = top; lv > 0; lv--) {
		std::vector<int32_t> &bucket = light_buckets[lv];
		for (size_t q = 0; q < bucket.size(); q++) {
			int b = bucket[q];
			if (light_lv[b] != lv) {
				continue;
			}
			int bx = b % BW, by = b / BW;
			int o = cost(b);
			for (int d = 0; d < 8; d++) {
				int x2 = bx + DX[d], y2 = by + DY[d];
				if (x2 < 0 || y2 < 0 || x2 >= BW || y2 >= BH) {
					continue;
				}
				// Four cells across a block: LSTEP per cell times the average opacity.
				int nl = lv - (((d < 4 ? LSTEP : LDIAG) * o) >> 2);
				if (nl <= 0) {
					continue;
				}
				int j = y2 * BW + x2;
				if (nl > light_lv[j]) {
					light_lv[j] = (uint16_t)nl;
					light_buckets[nl].push_back(j);
				}
			}
		}
		bucket.clear();
	}
	// Brightness per block, and the block masks.
	std::vector<uint8_t> bits(N, 0); // 1 lit, 2 in sight
	uint8_t *o = bits.data();
	for (int b = 0; b < N; b++) {
		int lv = light_lv[b];
		light_px[b] = (uint8_t)(std::min(lv, (int)LFULL) * 255 / LFULL);
		if (lv >= LMIN) {
			o[b] = 1;
		}
	}
	const int32_t *sp = sights.ptr();
	for (int k = 0; k + 2 < (int)sights.size(); k += 3) {
		float px = (float)sp[k], py = (float)sp[k + 1], r = (float)sp[k + 2];
		int kx0 = std::max((int)((px - r) / 4.0f), 0), kx1 = std::min((int)((px + r) / 4.0f), BW - 1);
		int ky0 = std::max((int)((py - r) / 4.0f), 0), ky1 = std::min((int)((py + r) / 4.0f), BH - 1);
		float r2 = (r + 2.0f) * (r + 2.0f);
		for (int ky = ky0; ky <= ky1; ky++) {
			for (int kx = kx0; kx <= kx1; kx++) {
				float dx = kx * 4 + 2.0f - px, dy = ky * 4 + 2.0f - py;
				if (dx * dx + dy * dy <= r2) {
					o[ky * BW + kx] |= 2;
				}
			}
		}
	}
	PackedByteArray out;
	out.resize(3 * N);
	uint8_t *live = out.ptrw();
	uint8_t *expl = live + N;
	uint8_t *seen = live + 2 * N;
	const uint8_t *kn = known.size() >= N ? known.ptr() : nullptr;
	for (int b = 0; b < N; b++) {
		bool s = bits[b] == 3;
		bool k = s || (kn && kn[b]);
		live[b] = (k && (bits[b] & 1)) ? 255 : 0;
		expl[b] = k ? 255 : 0;
		seen[b] = s ? 255 : 0;
		// What shows live now is what will be remembered once it doesn't.
		if (live[b]) {
			int bx = b % BW, by = b / BW;
			bool diff = false;
			for (int yy = by * 4; yy < by * 4 + 4; yy++) {
				int i = yy * W + bx * 4;
				if (memcmp(&mem[i], &cells[i], 4) != 0) {
					memcpy(&mem[i], &cells[i], 4);
					diff = true;
				}
			}
			if (diff) {
				mem_dirty[(size_t)((by * 4) >> TSHIFT) * TW + ((bx * 4) >> TSHIFT)] = 1;
			}
		}
	}
	return out;
}

// --- Render tiles -----------------------------------------------------------------
// The game draws the map from textures cut into 256 x 256 tiles and re-uploads only
// the tiles that changed: the engine flags a tile when a chunk in it was touched
// (anything that moves or changes a cell touches its chunk).

void CrucibleSim::mark_tiles(const Rects &r) {
	const int per = 1 << (TSHIFT - CSHIFT); // chunks across a tile
	for (int c = 0; c < NCH; c++) {
		if (r.x1[c] >= 0) {
			tile_dirty[(size_t)((c / CW) / per) * TW + ((c % CW) / per)] = 1;
			corr_valid[c] = 0;
		}
	}
}

// Tiles (index ty * tiles_across + tx) whose cells or aux changed since the last
// call; their flags are cleared.
PackedInt32Array CrucibleSim::take_dirty_tiles() {
	mark_tiles(next);
	PackedInt32Array out;
	for (int t = 0; t < (int)tile_dirty.size(); t++) {
		if (tile_dirty[t]) {
			out.push_back(t);
			tile_dirty[t] = 0;
		}
	}
	return out;
}

// Tiles whose remembered cells changed since the last call.
PackedInt32Array CrucibleSim::take_mem_tiles() {
	PackedInt32Array out;
	for (int t = 0; t < (int)mem_dirty.size(); t++) {
		if (mem_dirty[t]) {
			out.push_back(t);
			mem_dirty[t] = 0;
		}
	}
	return out;
}

// One tile's bytes, 256 x 256 row by row (zeros past the map's edge): `which` 0
// cells, 1 aux, 2 the remembered map.
PackedByteArray CrucibleSim::get_tile(int which, int tile) const {
	const int TS = 1 << TSHIFT;
	PackedByteArray out;
	out.resize(TS * TS);
	uint8_t *o = out.ptrw();
	memset(o, 0, TS * TS);
	if (tile < 0 || tile >= TW * TH) {
		return out;
	}
	const std::vector<uint8_t> &src = which == 1 ? aux : (which == 2 ? mem : cells);
	int x0 = (tile % TW) << TSHIFT, y0 = (tile / TW) << TSHIFT;
	int w = std::min(TS, W - x0);
	for (int yy = 0; yy < TS && y0 + yy < H; yy++) {
		memcpy(o + yy * TS, &src[(size_t)(y0 + yy) * W + x0], w);
	}
	return out;
}

// Forget what was seen: the remembered map becomes the map as it is now.
void CrucibleSim::reset_memory() {
	mem = cells;
	std::fill(mem_dirty.begin(), mem_dirty.end(), (uint8_t)1);
}

// Explored ground outside this rectangle (cells, end exclusive) no longer pulls its
// chunks into light_update; what buildings watch still does. The game passes the
// camera's view, so the pass costs what's on screen, not everything explored.
void CrucibleSim::set_light_view(int x0, int y0, int x1, int y1) {
	view_x0 = x0;
	view_y0 = y0;
	view_x1 = x1;
	view_y1 = y1;
}

// Brightness per 4x4 block (W/4 x H/4) from the last light_update.
PackedByteArray CrucibleSim::get_light() const {
	PackedByteArray out;
	out.resize((int64_t)light_px.size());
	memcpy(out.ptrw(), light_px.data(), light_px.size());
	return out;
}

// --- Queries --------------------------------------------------------------------------

int CrucibleSim::count(int m) const {
	return (int)std::count(cells.begin(), cells.end(), (uint8_t)m);
}

int CrucibleSim::count_burning() const {
	int n = 0;
	for (int i = 0; i < W * H; i++) {
		if (aux[i] && mats[cells[i]].burn_life) {
			n++;
		}
	}
	return n;
}

int64_t CrucibleSim::checksum() const {
	uint64_t h = 1469598103934665603ull;
	for (int i = 0; i < W * H; i++) {
		h ^= cells[i];
		h *= 1099511628211ull;
		h ^= aux[i];
		h *= 1099511628211ull;
	}
	for (const Particle &p : parts) {
		h ^= (uint64_t)(int)(p.x * 16.0f) * 31u + (uint64_t)(int)(p.y * 16.0f);
		h *= 1099511628211ull;
	}
	return (int64_t)(h & 0x7FFFFFFFFFFFFFFFull);
}

// What touches a building's outline (and, with `inside`, fills it):
// (hot, scald, liquid, open) cell counts. Gas counts as open; hot liquid as liquid.
Vector4i CrucibleSim::ring_counts(int x, int y, int w, int h, bool inside) const {
	int32_t a[NHAZ];
	hazards_at(x, y, w, h, inside, 0, a);
	return Vector4i(a[0], a[2], a[3], a[4]);
}

// Hazards around a building: [hot liquid, fire, scald, liquid, open, corrosive,
// ground, structure]. The first five count its outline (and its inside, with
// `inside`); fire counts flames, hot gas and burning cells; scald counts steam.
// Corrosive counts within `reach` cells of it. The last two are what could hold it
// up: solid cells (static or powder) and other buildings' cells on its outline,
// corners included (powder counts only under it).
void CrucibleSim::hazards_at(int x, int y, int w, int h, bool inside, int reach, int32_t *out) const {
	int hot = 0, fire = 0, scald = 0, liq = 0, opn = 0, cor = 0, ground = 0, strut = 0;
	// Rock holds it from any side; powder only from underneath, and only when it
	// rests on something itself (a sprinkle of loose dirt on its roof, or grains
	// falling past, hold nothing up).
	auto hold_at = [&](int xx, int yy) {
		if (xx < 0 || yy < 0 || xx >= W || yy >= H) {
			return;
		}
		const Mat &M = mats[cells[yy * W + xx]];
		if (M.structure) {
			strut++;
		} else if (M.kind == K_STATIC || (M.kind == K_POWDER && yy == y + h && yy + 1 < H && solid(cells[(yy + 1) * W + xx]))) {
			ground++;
		}
	};
	auto look_at = [&](int xx, int yy) {
		if (xx < 0 || yy < 0 || xx >= W || yy >= H) {
			return;
		}
		int i = yy * W + xx;
		const Mat &M = mats[cells[i]];
		if (is_fire_cell(i)) {
			fire++;
		}
		switch (M.kind) {
			case K_EMPTY:
				opn++;
				break;
			case K_GAS:
				if (M.scalds) {
					scald++;
				}
				opn++;
				break;
			case K_LIQUID:
				liq++;
				if (M.hot) {
					hot++;
				}
				break;
			default:
				break;
		}
	};
	for (int xx = x; xx < x + w; xx++) {
		look_at(xx, y - 1);
		look_at(xx, y + h);
		hold_at(xx, y - 1);
		hold_at(xx, y + h);
	}
	for (int yy = y; yy < y + h; yy++) {
		look_at(x - 1, yy);
		look_at(x + w, yy);
		hold_at(x - 1, yy);
		hold_at(x + w, yy);
	}
	hold_at(x - 1, y - 1);
	hold_at(x + w, y - 1);
	hold_at(x - 1, y + h);
	hold_at(x + w, y + h);
	if (inside) {
		for (int yy = y; yy < y + h; yy++) {
			for (int xx = x; xx < x + w; xx++) {
				look_at(xx, yy);
			}
		}
	}
	if (reach > 0) {
		int x0 = std::max(0, x - reach), x1 = std::min(W, x + w + reach);
		int y0 = std::max(0, y - reach), y1 = std::min(H, y + h + reach);
		// Only look cell by cell when a chunk in reach holds anything corrosive.
		bool any = false;
		for (int cy = y0 >> CSHIFT; cy <= (y1 - 1) >> CSHIFT && !any; cy++) {
			for (int cx = x0 >> CSHIFT; cx <= (x1 - 1) >> CSHIFT; cx++) {
				int c = cy * CW + cx;
				if (!corr_valid[c] || next.x1[c] >= 0) {
					int n = 0;
					for (int yy = cy << CSHIFT; yy < (cy + 1) << CSHIFT; yy++) {
						for (int xx = cx << CSHIFT; xx < (cx + 1) << CSHIFT; xx++) {
							n += mats[cells[yy * W + xx]].corrosive ? 1 : 0;
						}
					}
					corr_count[c] = n;
					corr_valid[c] = next.x1[c] >= 0 ? 0 : 1;
				}
				if (corr_count[c] > 0) {
					any = true;
					break;
				}
			}
		}
		if (any) {
			for (int yy = y0; yy < y1; yy++) {
				for (int xx = x0; xx < x1; xx++) {
					if (mats[cells[yy * W + xx]].corrosive) {
						cor++;
					}
				}
			}
		}
	}
	out[0] = hot;
	out[1] = fire;
	out[2] = scald;
	out[3] = liq;
	out[4] = opn;
	out[5] = cor;
	out[6] = ground;
	out[7] = strut;
}

PackedInt32Array CrucibleSim::building_hazards(int x, int y, int w, int h, bool inside, int reach) const {
	PackedInt32Array out;
	out.resize(NHAZ);
	hazards_at(x, y, w, h, inside, reach, out.ptrw());
	return out;
}

// Many buildings at once: `rects` holds (x, y, w, h, inside) per building; the
// result holds the NHAZ counts above per building.
PackedInt32Array CrucibleSim::hazards_batch(const PackedInt32Array &rects, int reach) const {
	int n = (int)rects.size() / 5;
	PackedInt32Array out;
	out.resize(n * NHAZ);
	const int32_t *r = rects.ptr();
	int32_t *o = out.ptrw();
	for (int k = 0; k < n; k++) {
		hazards_at(r[k * 5], r[k * 5 + 1], r[k * 5 + 2], r[k * 5 + 3], r[k * 5 + 4] != 0, reach, o + k * NHAZ);
	}
	return out;
}

// Hazards along a link from (x0, y0) to (x1, y1): [fire, corrosive, hot liquid].
// Fire and lava count on the line; corrosion counts on it or right beside it.
void CrucibleSim::segment_at(int x0, int y0, int x1, int y1, int32_t *out) const {
	int fire = 0, cor = 0, hot = 0;
	int dx = std::abs(x1 - x0), dy = std::abs(y1 - y0);
	int n = std::max(dx, dy);
	for (int s = 0; s <= n; s++) {
		int x = n ? x0 + (x1 - x0) * s / n : x0;
		int y = n ? y0 + (y1 - y0) * s / n : y0;
		if (x < 1 || y < 1 || x >= W - 1 || y >= H - 1) {
			continue;
		}
		int i = y * W + x;
		const Mat &M = mats[cells[i]];
		if (is_fire_cell(i)) {
			fire++;
		}
		if (M.hot && M.kind == K_LIQUID) {
			hot++;
		}
		if (M.corrosive || mats[cells[i - 1]].corrosive || mats[cells[i + 1]].corrosive || mats[cells[i - W]].corrosive || mats[cells[i + W]].corrosive) {
			cor++;
		}
	}
	out[0] = fire;
	out[1] = cor;
	out[2] = hot;
}

PackedInt32Array CrucibleSim::segment_hazards(int x0, int y0, int x1, int y1) const {
	PackedInt32Array out;
	out.resize(3);
	segment_at(x0, y0, x1, y1, out.ptrw());
	return out;
}

// Many links at once: `segs` holds (x0, y0, x1, y1) per link; the result holds
// the three counts above per link.
PackedInt32Array CrucibleSim::segments_batch(const PackedInt32Array &segs) const {
	int n = (int)segs.size() / 4;
	PackedInt32Array out;
	out.resize(n * 3);
	const int32_t *s = segs.ptr();
	int32_t *o = out.ptrw();
	for (int k = 0; k < n; k++) {
		segment_at(s[k * 4], s[k * 4 + 1], s[k * 4 + 2], s[k * 4 + 3], o + k * 3);
	}
	return out;
}

// Cells in the rectangle (clipped to the map) whose material `mask` flags (a byte
// per material id).
int CrucibleSim::count_in_rect(int x, int y, int w, int h, const PackedByteArray &mask) const {
	if (mask.size() < 256) {
		return 0;
	}
	const uint8_t *mk = mask.ptr();
	int n = 0;
	for (int yy = std::max(y, 0); yy < std::min(y + h, H); yy++) {
		for (int xx = std::max(x, 0); xx < std::min(x + w, W); xx++) {
			n += mk[cells[yy * W + xx]] ? 1 : 0;
		}
	}
	return n;
}

// For each 4x4 block in the bw x bh blocks from block (bx, by), how many of its
// cells `mask` flags (0..16), row by row. Blocks off the map count 0.
PackedByteArray CrucibleSim::block_counts(int bx, int by, int bw, int bh, const PackedByteArray &mask) const {
	PackedByteArray out;
	if (bw <= 0 || bh <= 0 || mask.size() < 256) {
		return out;
	}
	out.resize((int64_t)bw * bh);
	uint8_t *o = out.ptrw();
	memset(o, 0, (size_t)bw * bh);
	const uint8_t *mk = mask.ptr();
	for (int j = 0; j < bh; j++) {
		int y0 = (by + j) * 4;
		if (y0 < 0 || y0 + 4 > H) {
			continue;
		}
		for (int i = 0; i < bw; i++) {
			int x0 = (bx + i) * 4;
			if (x0 < 0 || x0 + 4 > W) {
				continue;
			}
			int n = 0;
			for (int yy = y0; yy < y0 + 4; yy++) {
				const uint8_t *row = &cells[(size_t)yy * W + x0];
				n += (mk[row[0]] ? 1 : 0) + (mk[row[1]] ? 1 : 0) + (mk[row[2]] ? 1 : 0) + (mk[row[3]] ? 1 : 0);
			}
			o[j * bw + i] = (uint8_t)n;
		}
	}
	return out;
}

// How many cells of each material (256 entries) lie in the rectangle.
PackedInt32Array CrucibleSim::rect_counts(int x, int y, int w, int h) const {
	PackedInt32Array out;
	out.resize(256);
	int32_t *o = out.ptrw();
	memset(o, 0, sizeof(int32_t) * 256);
	for (int yy = std::max(y, 0); yy < std::min(y + h, H); yy++) {
		for (int xx = std::max(x, 0); xx < std::min(x + w, W); xx++) {
			o[cells[yy * W + xx]]++;
		}
	}
	return out;
}

// Digs out every cell `mask` flags in the rectangle at once (as set_cell to air
// would), then holds the ground round it still for `settle_ticks` (settle_around
// over the rectangle grown by `settle_r`). Returns how many of each material went
// (256 entries). For machines that clear a row at a time.
PackedInt32Array CrucibleSim::dig_rect(int x, int y, int w, int h, const PackedByteArray &mask, int settle_r, int settle_ticks) {
	PackedInt32Array out;
	out.resize(256);
	int32_t *o = out.ptrw();
	memset(o, 0, sizeof(int32_t) * 256);
	if (mask.size() < 256) {
		return out;
	}
	const uint8_t *mk = mask.ptr();
	int n = 0;
	for (int yy = std::max(y, 0); yy < std::min(y + h, H); yy++) {
		for (int xx = std::max(x, 0); xx < std::min(x + w, W); xx++) {
			uint8_t m = cells[yy * W + xx];
			if (mk[m]) {
				o[m]++;
				set_cell(xx, yy, AIR);
				n++;
			}
		}
	}
	if (n > 0 && settle_ticks > 0) {
		int until = tick + settle_ticks;
		for (int yy = std::max(2, y - settle_r); yy <= std::min(H - 3, y + h - 1 + settle_r); yy++) {
			for (int xx = std::max(2, x - settle_r); xx <= std::min(W - 3, x + w - 1 + settle_r); xx++) {
				int i = yy * W + xx;
				uint8_t k = mats[cells[i]].kind;
				if ((k == K_STATIC || k == K_POWDER) && settle[i] < until) {
					settle[i] = until;
				}
			}
		}
	}
	return out;
}

// A block map (W/4 x H/4, 255 or 0) of the blocks whose middle lies within r + 2
// of some (x, y, r) in `circles`: the same reach light_update gives sight.
PackedByteArray CrucibleSim::block_circles(const PackedInt32Array &circles) const {
	const int BW = W / 4, BH = H / 4;
	PackedByteArray out;
	out.resize((int64_t)BW * BH);
	uint8_t *o = out.ptrw();
	memset(o, 0, (size_t)BW * BH);
	const int32_t *c = circles.ptr();
	for (int k = 0; k + 2 < (int)circles.size(); k += 3) {
		float px = (float)c[k], py = (float)c[k + 1], r = (float)c[k + 2];
		int kx0 = std::max((int)((px - r) / 4.0f), 0), kx1 = std::min((int)((px + r) / 4.0f), BW - 1);
		int ky0 = std::max((int)((py - r) / 4.0f), 0), ky1 = std::min((int)((py + r) / 4.0f), BH - 1);
		float r2 = (r + 2.0f) * (r + 2.0f);
		for (int ky = ky0; ky <= ky1; ky++) {
			for (int kx = kx0; kx <= kx1; kx++) {
				float dx = kx * 4 + 2.0f - px, dy = ky * 4 + 2.0f - py;
				if (dx * dx + dy * dy <= r2) {
					o[ky * BW + kx] = 255;
				}
			}
		}
	}
	return out;
}

// Where a w x h footprint at (x, y) could go within `radius` cells: every offset
// (nearest first) where the footprint lies inside the map's 2-cell margin, every
// cell of it is one `open_mask` flags, and a cell `solid_mask` flags touches one
// of its sides (above, below, left or right; not the corners). Returns triples
// (dx, dy, rests), rests being 1 when something solid lies right under it. The game
// then checks what the engine can't (fog, network reach).
PackedInt32Array CrucibleSim::place_spots(int x, int y, int w, int h, int radius, const PackedByteArray &open_mask, const PackedByteArray &solid_mask) {
	PackedInt32Array out;
	if (open_mask.size() < 256 || solid_mask.size() < 256 || w <= 0 || h <= 0 || radius < 0) {
		return out;
	}
	if (radius != spot_radius) {
		spot_radius = radius;
		std::vector<std::pair<int, int>> offs;
		for (int dy = -radius; dy <= radius; dy++) {
			for (int dx = -radius; dx <= radius; dx++) {
				if (dx * dx + dy * dy <= radius * radius) {
					offs.push_back({ dx, dy });
				}
			}
		}
		std::stable_sort(offs.begin(), offs.end(), [](const std::pair<int, int> &a, const std::pair<int, int> &b) {
			return a.first * a.first + a.second * a.second < b.first * b.first + b.second * b.second;
		});
		spot_offsets.clear();
		for (auto &o : offs) {
			spot_offsets.push_back(o.first);
			spot_offsets.push_back(o.second);
		}
	}
	// Prefix sums over the window every candidate (and its one-cell border) lies in.
	const uint8_t *om = open_mask.ptr();
	const uint8_t *sm = solid_mask.ptr();
	const int wx0 = x - radius - 1, wy0 = y - radius - 1;
	const int ww = w + 2 * radius + 2, wh = h + 2 * radius + 2;
	std::vector<int32_t> bad((size_t)(ww + 1) * (wh + 1), 0), sol((size_t)(ww + 1) * (wh + 1), 0);
	for (int j = 0; j < wh; j++) {
		int gy = wy0 + j;
		int rb = 0, rs = 0;
		for (int i = 0; i < ww; i++) {
			int gx = wx0 + i;
			bool inside = gx >= 0 && gy >= 0 && gx < W && gy < H;
			uint8_t m = inside ? cells[gy * W + gx] : 1;
			rb += (inside && om[m]) ? 0 : 1;
			rs += (inside && sm[m]) ? 1 : 0;
			size_t k = (size_t)(j + 1) * (ww + 1) + (i + 1);
			bad[k] = bad[k - (ww + 1)] + rb;
			sol[k] = sol[k - (ww + 1)] + rs;
		}
	}
	// Sum over window cells [i0, i1) x [j0, j1).
	auto sum = [&](const std::vector<int32_t> &p, int i0, int j0, int i1, int j1) {
		return p[(size_t)j1 * (ww + 1) + i1] - p[(size_t)j0 * (ww + 1) + i1] - p[(size_t)j1 * (ww + 1) + i0] + p[(size_t)j0 * (ww + 1) + i0];
	};
	for (size_t k = 0; k + 1 < spot_offsets.size(); k += 2) {
		int dx = spot_offsets[k], dy = spot_offsets[k + 1];
		int rx = x + dx, ry = y + dy;
		if (rx < 2 || ry < 2 || rx + w > W - 2 || ry + h > H - 2) {
			continue;
		}
		int i0 = rx - wx0, j0 = ry - wy0;
		if (sum(bad, i0, j0, i0 + w, j0 + h) != 0) {
			continue;
		}
		int below = sum(sol, i0, j0 + h, i0 + w, j0 + h + 1);
		int touch = below + sum(sol, i0, j0 - 1, i0 + w, j0) + sum(sol, i0 - 1, j0, i0, j0 + h) + sum(sol, i0 + w, j0, i0 + w + 1, j0 + h);
		if (touch == 0) {
			continue;
		}
		out.push_back(dx);
		out.push_back(dy);
		out.push_back(below > 0 ? 1 : 0);
	}
	return out;
}

// Which materials occur in the 4x4 blocks a mask (W/4 x H/4, like the fog maps)
// marks: 256 entries, each the index (y * W + x) of one cell of that material
// found there, or -1. Burning cells show up as the fire material, if there is one.
PackedInt32Array CrucibleSim::materials_in(const PackedByteArray &mask) const {
	PackedInt32Array out;
	out.resize(256);
	int32_t *o = out.ptrw();
	for (int k = 0; k < 256; k++) {
		o[k] = -1;
	}
	const int BW = W / 4;
	const int BH = H / 4;
	if (mask.size() < BW * BH) {
		return out;
	}
	const uint8_t *mk = mask.ptr();
	for (int by = 0; by < BH; by++) {
		for (int bx = 0; bx < BW; bx++) {
			if (!mk[by * BW + bx]) {
				continue;
			}
			for (int yy = by * 4; yy < by * 4 + 4; yy++) {
				for (int xx = bx * 4; xx < bx * 4 + 4; xx++) {
					int i = yy * W + xx;
					uint8_t m = cells[i];
					if (o[m] < 0) {
						o[m] = i;
					}
					if (fire_id >= 0 && o[fire_id] < 0 && aux[i] && mats[m].burn_life) {
						o[fire_id] = i;
					}
				}
			}
		}
	}
	return out;
}

// --- Bindings ---------------------------------------------------------------------------

void CrucibleSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_size", "width", "height"), &CrucibleSim::set_size);
	ClassDB::bind_method(D_METHOD("get_width"), &CrucibleSim::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &CrucibleSim::get_height);
	ClassDB::bind_method(D_METHOD("configure", "materials", "reactions"), &CrucibleSim::configure);
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &CrucibleSim::set_seed);
	ClassDB::bind_method(D_METHOD("get_cell", "x", "y"), &CrucibleSim::get_cell);
	ClassDB::bind_method(D_METHOD("set_cell", "x", "y", "material"), &CrucibleSim::set_cell);
	ClassDB::bind_method(D_METHOD("get_aux", "x", "y"), &CrucibleSim::get_aux);
	ClassDB::bind_method(D_METHOD("ignite", "x", "y"), &CrucibleSim::ignite);
	ClassDB::bind_method(D_METHOD("settle_around", "x", "y", "radius", "ticks"), &CrucibleSim::settle_around);
	ClassDB::bind_method(D_METHOD("get_settle", "x", "y"), &CrucibleSim::get_settle);
	ClassDB::bind_method(D_METHOD("get_cells"), &CrucibleSim::get_cells);
	ClassDB::bind_method(D_METHOD("set_cells", "data"), &CrucibleSim::set_cells);
	ClassDB::bind_method(D_METHOD("get_aux_bytes"), &CrucibleSim::get_aux_bytes);
	ClassDB::bind_method(D_METHOD("touch_rect", "x0", "y0", "x1", "y1"), &CrucibleSim::touch_rect);
	ClassDB::bind_method(D_METHOD("step"), &CrucibleSim::step);
	ClassDB::bind_method(D_METHOD("erode", "samples", "y_min", "y_max"), &CrucibleSim::erode);
	ClassDB::bind_method(D_METHOD("weather", "samples"), &CrucibleSim::weather);
	ClassDB::bind_method(D_METHOD("collapse", "rows"), &CrucibleSim::collapse);
	ClassDB::bind_method(D_METHOD("stabilize"), &CrucibleSim::stabilize);
	ClassDB::bind_method(D_METHOD("wash", "samples"), &CrucibleSim::wash);
	ClassDB::bind_method(D_METHOD("get_washed"), &CrucibleSim::get_washed);
	ClassDB::bind_method(D_METHOD("hold_circle", "x", "y", "r", "delta"), &CrucibleSim::hold_circle);
	ClassDB::bind_method(D_METHOD("get_held", "x", "y"), &CrucibleSim::get_held);
	ClassDB::bind_method(D_METHOD("set_shields", "circles"), &CrucibleSim::set_shields);
	ClassDB::bind_method(D_METHOD("get_last_cave"), &CrucibleSim::get_last_cave);
	ClassDB::bind_method(D_METHOD("get_caved"), &CrucibleSim::get_caved);
	ClassDB::bind_method(D_METHOD("tremor", "wanted", "y_min", "y_max"), &CrucibleSim::tremor);
	ClassDB::bind_method(D_METHOD("explode", "x", "y", "radius", "power"), &CrucibleSim::explode);
	ClassDB::bind_method(D_METHOD("add_particle", "x", "y", "vx", "vy", "material"), &CrucibleSim::add_particle);
	ClassDB::bind_method(D_METHOD("refresh_heat", "all"), &CrucibleSim::refresh_heat);
	ClassDB::bind_method(D_METHOD("get_heat"), &CrucibleSim::get_heat);
	ClassDB::bind_method(D_METHOD("light_update", "lights", "sights", "sun", "known"), &CrucibleSim::light_update);
	ClassDB::bind_method(D_METHOD("get_light"), &CrucibleSim::get_light);
	ClassDB::bind_method(D_METHOD("set_light_view", "x0", "y0", "x1", "y1"), &CrucibleSim::set_light_view);
	ClassDB::bind_method(D_METHOD("take_dirty_tiles"), &CrucibleSim::take_dirty_tiles);
	ClassDB::bind_method(D_METHOD("take_mem_tiles"), &CrucibleSim::take_mem_tiles);
	ClassDB::bind_method(D_METHOD("get_tile", "which", "tile"), &CrucibleSim::get_tile);
	ClassDB::bind_method(D_METHOD("reset_memory"), &CrucibleSim::reset_memory);
	ClassDB::bind_method(D_METHOD("get_tiles_across"), &CrucibleSim::get_tiles_across);
	ClassDB::bind_method(D_METHOD("get_tiles_down"), &CrucibleSim::get_tiles_down);
	ClassDB::bind_method(D_METHOD("count", "material"), &CrucibleSim::count);
	ClassDB::bind_method(D_METHOD("count_burning"), &CrucibleSim::count_burning);
	ClassDB::bind_method(D_METHOD("particle_count"), &CrucibleSim::particle_count);
	ClassDB::bind_method(D_METHOD("checksum"), &CrucibleSim::checksum);
	ClassDB::bind_method(D_METHOD("ring_counts", "x", "y", "w", "h", "inside"), &CrucibleSim::ring_counts);
	ClassDB::bind_method(D_METHOD("building_hazards", "x", "y", "w", "h", "inside", "reach"), &CrucibleSim::building_hazards);
	ClassDB::bind_method(D_METHOD("segment_hazards", "x0", "y0", "x1", "y1"), &CrucibleSim::segment_hazards);
	ClassDB::bind_method(D_METHOD("hazards_batch", "rects", "reach"), &CrucibleSim::hazards_batch);
	ClassDB::bind_method(D_METHOD("segments_batch", "segments"), &CrucibleSim::segments_batch);
	ClassDB::bind_method(D_METHOD("materials_in", "mask"), &CrucibleSim::materials_in);
	ClassDB::bind_method(D_METHOD("count_in_rect", "x", "y", "w", "h", "mask"), &CrucibleSim::count_in_rect);
	ClassDB::bind_method(D_METHOD("block_counts", "bx", "by", "bw", "bh", "mask"), &CrucibleSim::block_counts);
	ClassDB::bind_method(D_METHOD("rect_counts", "x", "y", "w", "h"), &CrucibleSim::rect_counts);
	ClassDB::bind_method(D_METHOD("dig_rect", "x", "y", "w", "h", "mask", "settle_r", "settle_ticks"), &CrucibleSim::dig_rect);
	ClassDB::bind_method(D_METHOD("block_circles", "circles"), &CrucibleSim::block_circles);
	ClassDB::bind_method(D_METHOD("place_spots", "x", "y", "w", "h", "radius", "open_mask", "solid_mask"), &CrucibleSim::place_spots);
	ClassDB::bind_method(D_METHOD("set_threads", "n"), &CrucibleSim::set_threads);
	ClassDB::bind_method(D_METHOD("set_fall", "accel", "max_speed"), &CrucibleSim::set_fall);
	ClassDB::bind_method(D_METHOD("get_threads"), &CrucibleSim::get_threads);
	ClassDB::bind_method(D_METHOD("get_changed"), &CrucibleSim::get_changed);
	ClassDB::bind_method(D_METHOD("set_changed", "value"), &CrucibleSim::set_changed);
	ClassDB::bind_method(D_METHOD("get_heat_changed"), &CrucibleSim::get_heat_changed);
	ClassDB::bind_method(D_METHOD("set_heat_changed", "value"), &CrucibleSim::set_heat_changed);
	ClassDB::bind_method(D_METHOD("get_stat_chunks"), &CrucibleSim::get_stat_chunks);
	ClassDB::bind_method(D_METHOD("get_stat_updates"), &CrucibleSim::get_stat_updates);
	ClassDB::bind_method(D_METHOD("get_reactions"), &CrucibleSim::get_reactions);
	ClassDB::bind_method(D_METHOD("get_ignitions"), &CrucibleSim::get_ignitions);
	ClassDB::bind_method(D_METHOD("get_eroded"), &CrucibleSim::get_eroded);
	ClassDB::bind_method(D_METHOD("get_crumbled"), &CrucibleSim::get_crumbled);
	ClassDB::bind_method(D_METHOD("get_tick"), &CrucibleSim::get_tick);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "changed"), "set_changed", "get_changed");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "heat_changed"), "set_heat_changed", "get_heat_changed");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_BYTE_ARRAY, "cells"), "set_cells", "get_cells");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "stat_chunks"), "", "get_stat_chunks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "stat_updates"), "", "get_stat_updates");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "reactions"), "", "get_reactions");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ignitions"), "", "get_ignitions");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "eroded"), "", "get_eroded");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "crumbled"), "", "get_crumbled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick"), "", "get_tick");
}
