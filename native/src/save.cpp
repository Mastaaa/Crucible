// Saving and loading the whole simulation (phase 10's Continue).
//
// save_state() writes everything that carries from one tick to the next: the
// cells and their aux, fall speeds, settle and Strut holds, the remembered map,
// the per-cell move stamps, which chunks are awake, free particles, rigid bodies,
// the random streams and the counters. Materials, reactions and the body and fall
// settings are configuration: a loading sim gets those from the game first, the
// same way a new one does. Caches (heat, light, corrosion counts, render tiles)
// are rebuilt, so a loaded sim steps exactly as the saved one would have.
//
// The format is raw little-endian values with a magic, a version and the grid's
// size up front; the game compresses it.

#include "crucible_sim.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdint>
#include <cstring>

using namespace godot;

namespace {

const uint32_t MAGIC = 0x56535243u; // "CRSV"
const uint32_t VERSION = 1;

struct Out {
	std::vector<uint8_t> b;
	template <class T>
	void put(const T &v) {
		const uint8_t *p = reinterpret_cast<const uint8_t *>(&v);
		b.insert(b.end(), p, p + sizeof(T));
	}
	template <class T>
	void vec(const std::vector<T> &v) {
		put<uint32_t>((uint32_t)v.size());
		if (!v.empty()) {
			const uint8_t *p = reinterpret_cast<const uint8_t *>(v.data());
			b.insert(b.end(), p, p + v.size() * sizeof(T));
		}
	}
};

struct In {
	const uint8_t *p = nullptr;
	size_t n = 0, i = 0;
	bool ok = true;
	template <class T>
	T get() {
		T v{};
		if (!ok || i + sizeof(T) > n) {
			ok = false;
			return v;
		}
		std::memcpy(&v, p + i, sizeof(T));
		i += sizeof(T);
		return v;
	}
	template <class T>
	void vec(std::vector<T> &v, size_t expect = SIZE_MAX) {
		uint32_t k = get<uint32_t>();
		if (!ok || (expect != SIZE_MAX && k != expect) || i + (size_t)k * sizeof(T) > n) {
			ok = false;
			return;
		}
		v.resize(k);
		if (k) {
			std::memcpy(v.data(), p + i, (size_t)k * sizeof(T));
		}
		i += (size_t)k * sizeof(T);
	}
};

} // namespace

PackedByteArray CrucibleSim::save_state() const {
	Out o;
	o.put(MAGIC);
	o.put(VERSION);
	o.put<int32_t>(W);
	o.put<int32_t>(H);
	o.put(seed);
	o.put(grng);
	o.put<int32_t>(tick);
	o.put<int32_t>(mark);
	o.put<int32_t>(collapse_cursor);
	o.put<int32_t>(next_body_id);
	for (int v : { reactions_total, ignitions_total, eroded, crumbled, caved, washed, last_cave_x, last_cave_y,
				 bodies_made, bodies_shattered, bodies_settled }) {
		o.put<int32_t>(v);
	}
	o.vec(cells);
	o.vec(aux);
	o.vec(settle);
	o.vec(held);
	o.vec(vel);
	o.vec(mem);
	o.vec(stamp);
	o.vec(owner);
	o.vec(shields);
	o.vec(next.x0);
	o.vec(next.y0);
	o.vec(next.x1);
	o.vec(next.y1);
	o.vec(impacts);
	o.put<uint32_t>((uint32_t)parts.size());
	for (const Particle &q : parts) {
		o.put(q.x);
		o.put(q.y);
		o.put(q.vx);
		o.put(q.vy);
		o.put(q.mat);
		o.put(q.aux);
	}
	o.put<uint32_t>((uint32_t)bodies.size());
	for (const Body &b : bodies) {
		o.put<int32_t>(b.id);
		o.put<int32_t>(b.w);
		o.put<int32_t>(b.h);
		o.vec(b.mat);
		o.vec(b.aux);
		o.vec(b.edge);
		for (float v : { b.cx, b.cy, b.x, b.y, b.a, b.vx, b.vy, b.spin, b.mass, b.inertia, b.radius, b.toughness,
					 b.sx, b.sy, b.sa, b.ax, b.ay, b.aa }) {
			o.put(v);
		}
		o.put<int32_t>(b.count);
		o.vec(b.at);
		o.vec(b.from);
		o.put<uint8_t>(b.creature ? 1 : 0);
		o.put<int32_t>(b.age);
		o.put<int32_t>(b.rest);
		o.put<int32_t>(b.last_hit);
	}
	PackedByteArray out;
	out.resize((int64_t)o.b.size());
	if (!o.b.empty()) {
		std::memcpy(out.ptrw(), o.b.data(), o.b.size());
	}
	return out;
}

bool CrucibleSim::load_state(const PackedByteArray &data) {
	In in;
	in.p = data.ptr();
	in.n = (size_t)data.size();
	if (in.get<uint32_t>() != MAGIC || in.get<uint32_t>() != VERSION) {
		UtilityFunctions::push_error("CrucibleSim.load_state: not a save this engine can read");
		return false;
	}
	int w = in.get<int32_t>();
	int h = in.get<int32_t>();
	if (!in.ok || w != W || h != H) {
		UtilityFunctions::push_error("CrucibleSim.load_state: the save is ", w, " x ", h, ", the sim ", W, " x ", H);
		return false;
	}
	// Read into a scratch copy first, so a damaged save leaves this sim as it was.
	std::vector<uint8_t> c, a, hd, ve, me, st;
	std::vector<int32_t> se, sh, nx0, ny0, nx1, ny1, imp;
	std::vector<uint16_t> ow;
	uint32_t sd = in.get<uint32_t>();
	uint32_t gr = in.get<uint32_t>();
	int tk = in.get<int32_t>();
	int mk = in.get<int32_t>();
	int cc = in.get<int32_t>();
	int nb = in.get<int32_t>();
	int32_t counters[11];
	for (int32_t &v : counters) {
		v = in.get<int32_t>();
	}
	const size_t N = (size_t)W * H;
	in.vec(c, N);
	in.vec(a, N);
	in.vec(se, N);
	in.vec(hd, N);
	in.vec(ve, N);
	in.vec(me, N);
	in.vec(st, N);
	in.vec(ow, N);
	in.vec(sh);
	in.vec(nx0, (size_t)NCH);
	in.vec(ny0, (size_t)NCH);
	in.vec(nx1, (size_t)NCH);
	in.vec(ny1, (size_t)NCH);
	in.vec(imp);
	std::vector<Particle> ps(in.get<uint32_t>());
	for (Particle &q : ps) {
		q.x = in.get<float>();
		q.y = in.get<float>();
		q.vx = in.get<float>();
		q.vy = in.get<float>();
		q.mat = in.get<uint8_t>();
		q.aux = in.get<uint8_t>();
	}
	uint32_t nbod = in.get<uint32_t>();
	std::vector<Body> bs(in.ok ? nbod : 0);
	for (Body &b : bs) {
		b.id = in.get<int32_t>();
		b.w = in.get<int32_t>();
		b.h = in.get<int32_t>();
		in.vec(b.mat);
		in.vec(b.aux);
		in.vec(b.edge);
		for (float *v : { &b.cx, &b.cy, &b.x, &b.y, &b.a, &b.vx, &b.vy, &b.spin, &b.mass, &b.inertia, &b.radius,
					 &b.toughness, &b.sx, &b.sy, &b.sa, &b.ax, &b.ay, &b.aa }) {
			*v = in.get<float>();
		}
		b.count = in.get<int32_t>();
		in.vec(b.at);
		in.vec(b.from);
		b.creature = in.get<uint8_t>() != 0;
		b.age = in.get<int32_t>();
		b.rest = in.get<int32_t>();
		b.last_hit = in.get<int32_t>();
		if (!in.ok) {
			break;
		}
	}
	if (!in.ok || in.i != in.n) {
		UtilityFunctions::push_error("CrucibleSim.load_state: the save is damaged");
		return false;
	}
	seed = sd;
	grng = gr;
	tick = tk;
	mark = mk;
	collapse_cursor = cc;
	next_body_id = nb;
	reactions_total = counters[0];
	ignitions_total = counters[1];
	eroded = counters[2];
	crumbled = counters[3];
	caved = counters[4];
	washed = counters[5];
	last_cave_x = counters[6];
	last_cave_y = counters[7];
	bodies_made = counters[8];
	bodies_shattered = counters[9];
	bodies_settled = counters[10];
	cells.swap(c);
	aux.swap(a);
	settle.swap(se);
	held.swap(hd);
	vel.swap(ve);
	mem.swap(me);
	stamp.swap(st);
	owner.swap(ow);
	shields.swap(sh);
	next.x0.swap(nx0);
	next.y0.swap(ny0);
	next.x1.swap(nx1);
	next.y1.swap(ny1);
	impacts.swap(imp);
	parts.swap(ps);
	bodies.swap(bs);
	// Caches: worked out again from what was loaded.
	std::fill(tile_dirty.begin(), tile_dirty.end(), (uint8_t)1);
	std::fill(mem_dirty.begin(), mem_dirty.end(), (uint8_t)1);
	std::fill(corr_valid.begin(), corr_valid.end(), (uint8_t)0);
	for (auto &f : lava_dirty) {
		f.store(1);
	}
	light_lv.clear();
	light_px.clear();
	light_stamp.clear();
	light_cost.clear();
	changed = true;
	heat_changed = true;
	return true;
}
