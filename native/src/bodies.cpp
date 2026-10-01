// Rigid bodies: pieces of ground that break off a ceiling (or that the game makes)
// and fall, tumble and bounce, then either shatter into what they crumble into or
// come to rest and turn back into ground.
//
// A body keeps its own bitmap (materials and aux) and a pose: where its centre of
// mass is and its angle. Its pixels also sit in the grid as ordinary cells tagged
// with its id in `owner`, so sand piles on it, water flows round it, light stops at
// it and buildings rest on it; the slow passes (collapse, weathering, erosion, wash,
// tremors, loosening) leave tagged cells alone. Each tick, after the cell passes:
//  - pixels knocked off it since last tick (a blast, a drill, burnt coal) are gone
//    from its bitmap, and its mass and centre of mass follow;
//  - gravity, and drag in liquid;
//  - it moves in substeps of at most half a cell. The first pose that puts one of
//    its edge pixels into something solid is a contact: an impulse along the
//    ground's normal (the way the solid cells round the contact lie), with friction
//    and a little bounce, turning it by where the contact is against its centre of
//    mass;
//  - an impact faster than its toughness shatters it; slower ones over crush_min
//    are reported to the game (take_impacts), which hurts the buildings it hits;
//  - once it's barely moved for a while in contact, it settles: its cells stay
//    where they are as ground and the body is gone;
//  - it's stamped into the grid again where it's got to. Liquid and powder in the
//    way go up to the first open cell above; rock in the way hides that pixel.

#include "crucible_sim.h"
#include "rng.h"

#include <algorithm>
#include <cmath>

using namespace godot;
using crucible::frand;
using crucible::lcg;
using crucible::roll;

namespace {

constexpr uint8_t AIR = 0, BEDROCK = 1, BUILDING = 5;
constexpr float RESTITUTION = 0.2f;
constexpr float FRICTION = 0.5f;
constexpr float LIQUID_MAX = 1.6f; // cells a tick: the fastest anything sinks through liquid
constexpr float REST_MOVE = 1.0f; // staying this near (cells, at its rim) a spot in contact counts as still
constexpr int REST_TICKS = 30; // still this long and it settles
constexpr int MAX_AGE = 60 * 30; // it settles after this long, whatever it's doing
constexpr int RUN_MIN = 4; // stretches of ceiling narrower than this crumble cell by cell
constexpr int SKIP_MAX = 64; // wedged into more cells than this and it settles where it is
constexpr int DISPLACE_UP = 96; // how far up liquid or powder in a body's way goes

} // namespace

// --- Setup and queries -----------------------------------------------------------

// Speeds in cells a second (accel in cells a second, per second); sizes in cells.
void CrucibleSim::set_body_params(const Dictionary &p) {
	auto num = [&p](const char *key, double def) { return (double)p.get(key, def); };
	body_g = (float)(num("accel", body_g * 3600.0) / 3600.0);
	body_max = (float)(num("max_speed", body_max * 60.0) / 60.0);
	shatter_base = (float)(num("shatter", shatter_base * 60.0) / 60.0);
	shatter_per = (float)(num("shatter_per_durability", shatter_per * 60.0) / 60.0);
	crush_min = (float)(num("crush_min", crush_min * 60.0) / 60.0);
	creature_tough = (float)(num("creature_shatter", creature_tough * 60.0) / 60.0);
	body_min = std::max(1, (int)num("min_cells", body_min));
	piece_min = std::max(RUN_MIN, (int)num("piece_min", piece_min));
	piece_max = std::max(piece_min, (int)num("piece_max", piece_max));
	thick_min = std::max(1, (int)num("thick_min", thick_min));
	thick_max = std::max(thick_min, (int)num("thick_max", thick_max));
	piece_room = std::max(0, (int)num("piece_room", piece_room));
	pieces = (bool)p.get("pieces", pieces);
}

// Everything static in the rectangle (bar bedrock and buildings) becomes one body
// moving at (vx, vy) cells a second and spinning at `spin` radians a second.
// Returns its id, or -1.
int CrucibleSim::make_body(int x, int y, int w, int h, double vx, double vy, double spin) {
	std::vector<int32_t> list;
	for (int yy = std::max(2, y); yy < std::min(H - 2, y + h); yy++) {
		for (int xx = std::max(2, x); xx < std::min(W - 2, x + w); xx++) {
			int i = yy * W + xx;
			const Mat &M = mats[cells[i]];
			if (M.kind == K_STATIC && cells[i] != BUILDING && cells[i] != BEDROCK && owner[i] == 0) {
				list.push_back(i);
			}
		}
	}
	return make_body_from(list, (float)(vx / 60.0), (float)(vy / 60.0), (float)(spin / 60.0));
}

// Per body: id, x0, y0, x1, y1 (the box round it), speed (cells a second), cells.
PackedInt32Array CrucibleSim::get_bodies() const {
	PackedInt32Array out;
	out.resize((int64_t)bodies.size() * 7);
	int32_t *o = out.ptrw();
	for (const Body &b : bodies) {
		float cs = std::cos(b.a), sn = std::sin(b.a);
		float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
		const float xs[4] = { -b.cx, b.w - b.cx, -b.cx, b.w - b.cx };
		const float ys[4] = { -b.cy, -b.cy, b.h - b.cy, b.h - b.cy };
		for (int k = 0; k < 4; k++) {
			float wx = b.x + cs * xs[k] - sn * ys[k];
			float wy = b.y + sn * xs[k] + cs * ys[k];
			x0 = std::min(x0, wx);
			x1 = std::max(x1, wx);
			y0 = std::min(y0, wy);
			y1 = std::max(y1, wy);
		}
		*o++ = b.id;
		*o++ = (int)std::floor(x0);
		*o++ = (int)std::floor(y0);
		*o++ = (int)std::floor(x1);
		*o++ = (int)std::floor(y1);
		*o++ = (int)(std::sqrt(b.vx * b.vx + b.vy * b.vy) * 60.0f);
		*o++ = b.count;
	}
	return out;
}

// Body `id` as [x, y, angle, vx, vy, spin, cells, age, ticks still, ticks since a
// contact] (a second's worth for the speeds), or empty if there's no such body.
PackedFloat32Array CrucibleSim::body_state(int id) const {
	PackedFloat32Array out;
	for (const Body &b : bodies) {
		if (b.id != id) {
			continue;
		}
		out.resize(10);
		float *o = out.ptrw();
		o[0] = b.x;
		o[1] = b.y;
		o[2] = b.a;
		o[3] = b.vx * 60.0f;
		o[4] = b.vy * 60.0f;
		o[5] = b.spin * 60.0f;
		o[6] = (float)b.count;
		o[7] = (float)b.age;
		o[8] = (float)b.rest;
		o[9] = (float)(b.age - b.last_hit);
		break;
	}
	return out;
}

// Impacts since last asked: x, y, speed (cells a second), the body's cells, 1 if
// what it hit there was a building (x, y are then in the building), and the id of
// the body it hit (0 if none).
PackedInt32Array CrucibleSim::take_impacts() {
	PackedInt32Array out;
	out.resize((int64_t)impacts.size());
	if (!impacts.empty()) {
		memcpy(out.ptrw(), impacts.data(), impacts.size() * sizeof(int32_t));
	}
	impacts.clear();
	return out;
}

int CrucibleSim::get_owner(int x, int y) const {
	if (x < 0 || y < 0 || x >= W || y >= H) {
		return 0;
	}
	return owner[y * W + x];
}

// Body `id` is a creature (a mite): it never turns back into ground, and at rest it
// just lies still (body_state says how long) for the game to take back. False if
// there's no such body.
bool CrucibleSim::set_creature(int id, bool on) {
	for (Body &b : bodies) {
		if (b.id == id) {
			b.creature = on;
			if (on) {
				b.toughness = creature_tough;
			}
			return true;
		}
	}
	return false;
}

// Lift body `id` out of the grid (its cells go back to air) and forget it. False if
// there's no such body.
bool CrucibleSim::remove_body(int id) {
	for (size_t k = 0; k < bodies.size(); k++) {
		if (bodies[k].id == id) {
			unstamp(bodies[k]);
			bodies.erase(bodies.begin() + (long)k);
			return true;
		}
	}
	return false;
}

void CrucibleSim::clear_bodies() {
	bodies.clear();
	impacts.clear();
	std::fill(owner.begin(), owner.end(), (uint16_t)0);
}

// --- Collapse into pieces --------------------------------------------------------

// The old way down, one cell: it becomes what it crumbles into, which falls.
int CrucibleSim::crumble_cell(int i, int x, int y) {
	const Mat &M = mats[cells[i]];
	uint8_t m = cells[i];
	int into = M.crumbles_into >= 0 ? M.crumbles_into : (M.loosens_to >= 0 ? M.loosens_to : m);
	// A burning piece keeps burning on the way down.
	uint8_t a = (M.burn_life && aux[i] && mats[into].burn_life) ? aux[i] : init_aux((uint8_t)into, lcg(grng));
	if (M.glows) {
		mark_lava(x, y);
	}
	if (mats[into].kind == K_POWDER) {
		cells[i] = (uint8_t)into;
		aux[i] = a;
	} else {
		cells[i] = AIR;
		aux[i] = 0;
		spawn(x + 0.5f, y + 0.6f, 0.0f, 0.2f, (uint8_t)into, a);
	}
	settle[i] = 0;
	next.touch(x, y);
	changed = true;
	last_cave_x = x;
	last_cave_y = y;
	return 1;
}

// Ceiling cells s..e of row y are due to come down. A short stretch, or one over a
// gap too low for a slab to drop into (a crawlspace sags and crumbles), crumbles
// cell by cell as before; otherwise, with its material's cave chance a sweep, a
// piece breaks off (the rest goes on later sweeps).
int CrucibleSim::give_way(int y, int s, int e) {
	bool low = false;
	if (pieces && e - s + 1 >= RUN_MIN) {
		const int xs[3] = { s + (e - s) / 4, (s + e) >> 1, e - (e - s) / 4 };
		for (int k = 0; k < 3 && !low; k++) {
			for (int d = 1; d <= piece_room; d++) {
				if (y + d >= H - 2 || solid(cells[(y + d) * W + xs[k]])) {
					low = true;
					break;
				}
			}
		}
	}
	if (!pieces || e - s + 1 < RUN_MIN || low) {
		int n = 0;
		for (int x = s; x <= e; x++) {
			int i = y * W + x;
			if (roll(grng, mats[cells[i]].cave)) {
				n += crumble_cell(i, x, y);
			}
		}
		return n;
	}
	if (!roll(grng, mats[cells[y * W + ((s + e) >> 1)]].cave)) {
		return 0;
	}
	return break_off(y, s, e);
}

// One piece of the stretch s..e (row y is its bottom) breaks off as a body: some
// piece_min..piece_max wide somewhere along it, thick_min..thick_max deep with a
// ragged top, narrowing upward at the stretch's ends as the arch will (by the
// ground's overhang a row), with cracks either side that lean in going up so it
// can drop out. It takes the ground in that outline joined to its bottom row that
// could give way (not held, settling or already moving). Returns cells that went.
int CrucibleSim::break_off(int y, int s, int e) {
	const int L = e - s + 1;
	int pw = piece_min + (int)(lcg(grng) % (uint32_t)(piece_max - piece_min + 1));
	int p0 = s, p1 = e;
	if (L > pw) {
		int mid = s + (int)(lcg(grng) % (uint32_t)L);
		p0 = std::clamp(mid - pw / 2, s, e - pw + 1);
		p1 = p0 + pw - 1;
		// A sliver left at either end goes with it.
		if (p0 - s < piece_min / 2) {
			p0 = s;
		}
		if (e - p1 < piece_min / 2) {
			p1 = e;
		}
	}
	const int oh = std::max(1, (int)mats[cells[y * W + ((p0 + p1) >> 1)]].overhang);
	int T = thick_min + (int)(lcg(grng) % (uint32_t)(thick_max - thick_min + 1));
	T = std::max(2, std::min(T, (p1 - p0 + 1) / 2));
	const int tmax = T + T / 2;
	const int ry0 = std::max(2, y - tmax + 1);
	const int RW = p1 - p0 + 1, RH = y - ry0 + 1;
	std::vector<int> depth(RW);
	int t = T;
	for (int x = p0; x <= p1; x++) {
		t += (int)(lcg(grng) % 3u) - 1;
		t = std::clamp(t, std::max(2, T / 2), tmax);
		int k = std::min(x - s, e - x);
		depth[x - p0] = std::min(t, k / oh + 1);
	}
	std::vector<uint8_t> in((size_t)RW * RH, 0);
	int xl = p0, xr = p1;
	for (int row = 0; row < RH && xl <= xr; row++) {
		for (int x = xl; x <= xr; x++) {
			if (row < depth[x - p0]) {
				in[(size_t)(RH - 1 - row) * RW + (x - p0)] = 1;
			}
		}
		uint32_t q = lcg(grng);
		xl += (q & 3) == 0 ? 1 : 0;
		xr -= ((q >> 2) & 3) == 0 ? 1 : 0;
	}
	std::vector<int32_t> list, stack;
	for (int x = p0; x <= p1; x++) {
		int i = y * W + x;
		size_t r = (size_t)(RH - 1) * RW + (x - p0);
		if (in[r] == 1 && can_break_off(i)) {
			in[r] = 2;
			stack.push_back(i);
		}
	}
	while (!stack.empty()) {
		int i = stack.back();
		stack.pop_back();
		list.push_back(i);
		int x = i % W, yy = i / W;
		const int nx[4] = { x - 1, x + 1, x, x };
		const int ny[4] = { yy, yy, yy - 1, yy + 1 };
		for (int k = 0; k < 4; k++) {
			if (nx[k] < p0 || nx[k] > p1 || ny[k] < ry0 || ny[k] > y) {
				continue;
			}
			size_t r = (size_t)(ny[k] - ry0) * RW + (nx[k] - p0);
			int j = ny[k] * W + nx[k];
			if (in[r] != 1 || !can_break_off(j)) {
				continue;
			}
			in[r] = 2;
			stack.push_back(j);
		}
	}
	last_cave_x = (p0 + p1) >> 1;
	last_cave_y = y;
	if ((int)list.size() < body_min || (int)bodies.size() >= MAX_BODIES) {
		int n = 0;
		for (int x = p0; x <= p1; x++) {
			int i = y * W + x;
			if (can_break_off(i)) {
				n += crumble_cell(i, x, y);
			}
		}
		return n;
	}
	make_body_from(list, 0.0f, 0.0f, (frand(grng) - 0.5f) * 0.02f);
	return (int)list.size();
}

// --- Bodies ---------------------------------------------------------------------

// The cells in `list` (all static, none a body's) become a body where they are.
int CrucibleSim::make_body_from(const std::vector<int32_t> &list, float vx, float vy, float spin) {
	if (list.empty() || (int)bodies.size() >= MAX_BODIES) {
		return -1;
	}
	int x0 = W, y0 = H, x1 = -1, y1 = -1;
	for (int gi : list) {
		int x = gi % W, y = gi / W;
		x0 = std::min(x0, x);
		x1 = std::max(x1, x);
		y0 = std::min(y0, y);
		y1 = std::max(y1, y);
	}
	// An id no live body has (ids wrap at 65535; there are never more than MAX_BODIES).
	int id = 0;
	for (int tries = 0; tries < 70000 && id == 0; tries++) {
		int c = next_body_id;
		next_body_id = next_body_id >= 65535 ? 1 : next_body_id + 1;
		bool used = false;
		for (const Body &o : bodies) {
			if (o.id == c) {
				used = true;
				break;
			}
		}
		if (!used) {
			id = c;
		}
	}
	Body b;
	b.id = id;
	b.w = x1 - x0 + 1;
	b.h = y1 - y0 + 1;
	b.mat.assign((size_t)b.w * b.h, 0);
	b.aux.assign((size_t)b.w * b.h, 0);
	for (int gi : list) {
		int li = (gi / W - y0) * b.w + (gi % W - x0);
		b.mat[li] = cells[gi];
		b.aux[li] = aux[gi];
		b.at.push_back(gi);
		b.from.push_back(li);
		owner[gi] = (uint16_t)id;
		settle[gi] = 0;
		vel[gi] = 0;
	}
	body_shape(b);
	b.x = x0 + b.cx;
	b.y = y0 + b.cy;
	b.sx = b.x;
	b.sy = b.y;
	b.vx = vx;
	b.vy = vy;
	b.spin = spin;
	bodies.push_back(std::move(b));
	bodies_made++;
	return id;
}

// Mass, centre of mass, moment of inertia, reach and edge pixels from the bitmap.
// A body that had pixels already keeps its place in the world as its centre of
// mass shifts. False when there's nothing left of it.
bool CrucibleSim::body_shape(Body &b) {
	int n = 0;
	double sx = 0.0, sy = 0.0, tough = 0.0;
	for (int ly = 0; ly < b.h; ly++) {
		for (int lx = 0; lx < b.w; lx++) {
			uint8_t m = b.mat[ly * b.w + lx];
			if (!m) {
				continue;
			}
			n++;
			sx += lx + 0.5;
			sy += ly + 0.5;
			tough += mats[m].durability >= 255 ? 10 : mats[m].durability;
		}
	}
	if (n == 0) {
		b.count = 0;
		return false;
	}
	float ncx = (float)(sx / n), ncy = (float)(sy / n);
	if (b.count > 0) {
		float dx = ncx - b.cx, dy = ncy - b.cy;
		float cs = std::cos(b.a), sn = std::sin(b.a);
		float wx = cs * dx - sn * dy, wy = sn * dx + cs * dy;
		b.x += wx;
		b.y += wy;
		b.sx += wx;
		b.sy += wy;
	}
	b.cx = ncx;
	b.cy = ncy;
	b.count = n;
	b.mass = (float)n;
	double inertia = n / 6.0;
	float r2 = 0.0f;
	b.edge.clear();
	for (int ly = 0; ly < b.h; ly++) {
		for (int lx = 0; lx < b.w; lx++) {
			int li = ly * b.w + lx;
			if (!b.mat[li]) {
				continue;
			}
			float dx = lx + 0.5f - b.cx, dy = ly + 0.5f - b.cy;
			inertia += dx * dx + dy * dy;
			r2 = std::max(r2, dx * dx + dy * dy);
			bool edge = lx == 0 || ly == 0 || lx == b.w - 1 || ly == b.h - 1 || !b.mat[li - 1] || !b.mat[li + 1] ||
					!b.mat[li - b.w] || !b.mat[li + b.w];
			if (edge) {
				b.edge.push_back(li);
			}
		}
	}
	b.inertia = (float)inertia;
	b.radius = std::sqrt(r2) + 0.71f;
	b.toughness = shatter_base + shatter_per * (float)(tough / n);
	return true;
}

void CrucibleSim::step_bodies() {
	if (bodies.empty()) {
		return;
	}
	size_t keep = 0;
	for (size_t k = 0; k < bodies.size(); k++) {
		if (body_tick(bodies[k])) {
			if (keep != k) {
				bodies[keep] = std::move(bodies[k]);
			}
			keep++;
		}
	}
	bodies.resize(keep);
	changed = true;
}

// One tick of body b; false when it's gone (shattered or settled).
bool CrucibleSim::body_tick(Body &b) {
	b.age++;
	// What's been knocked off it since last tick.
	size_t keep = 0;
	int lost = 0;
	for (size_t k = 0; k < b.at.size(); k++) {
		int gi = b.at[k], li = b.from[k];
		if (owner[gi] == b.id && cells[gi] == b.mat[li]) {
			b.aux[li] = aux[gi];
			b.at[keep] = gi;
			b.from[keep] = li;
			keep++;
		} else {
			if (owner[gi] == b.id) {
				owner[gi] = 0;
			}
			b.mat[li] = 0;
			lost++;
		}
	}
	b.at.resize(keep);
	b.from.resize(keep);
	if (lost > 0 && (!body_shape(b) || b.count < body_min)) {
		shatter(b);
		return false;
	}
	// Gravity, and liquid round a third of its edge slows it.
	b.vy += body_g;
	b.spin *= 0.995f;
	{
		float cs = std::cos(b.a), sn = std::sin(b.a);
		int wet = 0, looked = 0;
		size_t every = std::max<size_t>(1, b.edge.size() / 16);
		for (size_t k = 0; k < b.edge.size(); k += every) {
			int li = b.edge[k];
			float dx = li % b.w + 0.5f - b.cx, dy = li / b.w + 0.5f - b.cy;
			int gx = (int)std::floor(b.x + cs * dx - sn * dy);
			int gy = (int)std::floor(b.y + sn * dx + cs * dy);
			if (gx < 3 || gx >= W - 3 || gy < 3 || gy >= H - 3) {
				continue;
			}
			looked++;
			int gi = gy * W + gx;
			if (mats[cells[gi + W]].kind == K_LIQUID || mats[cells[gi - 1]].kind == K_LIQUID || mats[cells[gi + 1]].kind == K_LIQUID ||
					mats[cells[gi - W]].kind == K_LIQUID) {
				wet++;
			}
		}
		if (looked > 0 && wet * 3 >= looked) {
			b.vx *= 0.92f;
			b.spin *= 0.9f;
			b.vy = std::clamp(b.vy * 0.92f, -LIQUID_MAX, LIQUID_MAX);
		}
	}
	float sp = std::sqrt(b.vx * b.vx + b.vy * b.vy);
	if (sp > body_max) {
		b.vx *= body_max / sp;
		b.vy *= body_max / sp;
	}
	float spin_max = body_max / std::max(1.0f, b.radius);
	b.spin = std::clamp(b.spin, -spin_max, spin_max);
	// Cells it's already in (its stamp and its true pose differ a little when it's
	// turned) don't count against it.
	std::vector<int32_t> skip;
	{
		Contact c;
		overlap(b, b.x, b.y, b.a, skip, c, &skip);
		if ((int)skip.size() > SKIP_MAX) {
			if (b.creature) {
				shatter(b); // a mite wedged into rock is crushed
			} else {
				settle_body(b);
			}
			return false;
		}
	}
	// Move, in substeps of half a cell. A substep into something takes the impulse
	// and is then pushed back out along the ground's normal (a tenth of a cell at a
	// time, up to one), so it slides along ground and turns over edges; if that
	// doesn't free it, it stops there and tries again with what speed it has left
	// (up to three times a tick).
	float left = 1.0f;
	for (int iter = 0; iter < 3 && left > 0.02f; iter++) {
		float disp = (std::fabs(b.vx) + std::fabs(b.vy) + std::fabs(b.spin) * b.radius) * left;
		int n = std::clamp((int)std::ceil(disp / 0.5f), 1, 64);
		float f = left / n;
		bool blocked = false;
		for (int s = 0; s < n; s++) {
			float tx = b.x + b.vx * f, ty = b.y + b.vy * f, ta = b.a + b.spin * f;
			Contact c;
			if (!overlap(b, tx, ty, ta, skip, c, nullptr)) {
				b.x = tx;
				b.y = ty;
				b.a = ta;
				left -= f;
				continue;
			}
			float nx = 0.0f, ny = 0.0f;
			if (!body_hit(b, c, nx, ny)) {
				return false; // shattered
			}
			bool freed = false;
			for (float k = 0.1f; k <= 1.05f && !freed; k += 0.1f) {
				Contact c2;
				if (!overlap(b, tx + nx * k, ty + ny * k, ta, skip, c2, nullptr)) {
					b.x = tx + nx * k;
					b.y = ty + ny * k;
					b.a = ta;
					freed = true;
				}
			}
			if (freed) {
				left -= f;
				continue;
			}
			blocked = true;
			break;
		}
		if (!blocked) {
			break;
		}
	}
	// Still: in contact, and within REST_MOVE of where it was when it last started
	// being still (jostling in place doesn't count as moving).
	float moved = std::fabs(b.x - b.ax) + std::fabs(b.y - b.ay) + std::fabs(b.a - b.aa) * b.radius;
	if (b.age - b.last_hit <= 4 && moved < REST_MOVE) {
		b.rest++;
	} else {
		b.rest = 0;
		b.ax = b.x;
		b.ay = b.y;
		b.aa = b.a;
	}
	if (!b.creature && !b.module && (b.rest >= REST_TICKS || b.age >= MAX_AGE)) {
		settle_body(b);
		return false;
	}
	if (std::fabs(b.x - b.sx) + std::fabs(b.y - b.sy) + std::fabs(b.a - b.sa) * b.radius > 0.35f) {
		restamp(b);
	}
	return true;
}

// Whether body b at pose (x, y, a) has an edge pixel in anything solid that isn't
// its own (or in `skip`). Sums up the contact in c; with `collect`, lists the
// cells instead.
bool CrucibleSim::overlap(const Body &b, float x, float y, float a, const std::vector<int32_t> &skip, Contact &c,
		std::vector<int32_t> *collect) const {
	c = Contact();
	const float cs = std::cos(a), sn = std::sin(a);
	for (int li : b.edge) {
		float dx = li % b.w + 0.5f - b.cx, dy = li / b.w + 0.5f - b.cy;
		float px = x + cs * dx - sn * dy, py = y + sn * dx + cs * dy;
		int gx = (int)std::floor(px), gy = (int)std::floor(py);
		int gi = -1;
		if (gx >= 2 && gx < W - 2 && gy >= 2 && gy < H - 2) {
			gi = gy * W + gx;
			if (owner[gi] == b.id || !solid(cells[gi])) {
				continue;
			}
		}
		if (collect) {
			if (gi >= 0) {
				collect->push_back(gi);
			}
			continue;
		}
		if (gi >= 0 && !skip.empty() && std::find(skip.begin(), skip.end(), gi) != skip.end()) {
			continue;
		}
		c.n++;
		c.px += px;
		c.py += py;
		// Which way the ground round it lies.
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				int xx = gx + ox, yy = gy + oy;
				bool s = xx < 2 || xx >= W - 2 || yy < 2 || yy >= H - 2;
				if (!s) {
					int j = yy * W + xx;
					s = owner[j] != b.id && solid(cells[j]);
				}
				if (s) {
					c.gx += ox;
					c.gy += oy;
				}
			}
		}
		if (gi >= 0 && c.other == 0 && owner[gi]) {
			c.other = owner[gi];
		}
		if (gi >= 0 && cells[gi] == BUILDING) {
			c.nb++;
			c.bx += px;
			c.by += py;
		}
	}
	return c.n > 0;
}

// Body b ran into something (contact c) from where it is now. Impulse, friction,
// the impact reported, and the ground's normal in (nx, ny); false if it shattered.
bool CrucibleSim::body_hit(Body &b, const Contact &c, float &nx, float &ny) {
	float px = c.px / c.n, py = c.py / c.n;
	float rx = px - b.x, ry = py - b.y;
	float vcx = b.vx - b.spin * ry, vcy = b.vy + b.spin * rx;
	nx = -c.gx;
	ny = -c.gy;
	float len = std::sqrt(nx * nx + ny * ny);
	if (len < 0.5f) {
		// Wedged all round: straight back the way it came.
		float vl = std::sqrt(vcx * vcx + vcy * vcy);
		nx = vl > 1e-4f ? -vcx / vl : 0.0f;
		ny = vl > 1e-4f ? -vcy / vl : -1.0f;
	} else {
		nx /= len;
		ny /= len;
	}
	b.last_hit = b.age;
	if (b.creature) {
		// A mite scrabbles for a hold: it doesn't roll, and it drags.
		b.spin *= 0.3f;
		b.vx *= 0.8f;
	}
	float vn = vcx * nx + vcy * ny;
	if (vn >= 0.0f) {
		return true; // already parting there: a pixel off to one side turned into it
	}
	float speed = -vn;
	if (speed >= crush_min && impacts.size() < 6 * 256) {
		bool bld = c.nb > 0;
		impacts.push_back((int)std::floor(bld ? c.bx / c.nb : px));
		impacts.push_back((int)std::floor(bld ? c.by / c.nb : py));
		impacts.push_back((int)(speed * 60.0f));
		impacts.push_back(b.count);
		impacts.push_back(bld ? 1 : 0);
		impacts.push_back(c.other);
	}
	if (speed > b.toughness) {
		restamp(b); // where it hit, not where it was last drawn
		shatter(b);
		return false;
	}
	float rn = rx * ny - ry * nx;
	float k = 1.0f / b.mass + rn * rn / b.inertia;
	float j = -(speed >= 1.0f ? 1.0f + RESTITUTION : 1.0f) * vn / k;
	b.vx += j * nx / b.mass;
	b.vy += j * ny / b.mass;
	b.spin += rn * j / b.inertia;
	// Friction along the ground.
	float tx = -ny, ty = nx;
	vcx = b.vx - b.spin * ry;
	vcy = b.vy + b.spin * rx;
	float vt = vcx * tx + vcy * ty;
	float rt = rx * ty - ry * tx;
	float kt = 1.0f / b.mass + rt * rt / b.inertia;
	float jt = std::clamp(-vt / kt, -FRICTION * j, FRICTION * j);
	b.vx += jt * tx / b.mass;
	b.vy += jt * ty / b.mass;
	b.spin += rt * jt / b.inertia;
	return true;
}

// Lift b out of the grid (the cells it's stamped into go back to air).
void CrucibleSim::unstamp(Body &b) {
	for (size_t k = 0; k < b.at.size(); k++) {
		int gi = b.at[k], li = b.from[k];
		if (owner[gi] != b.id) {
			continue;
		}
		owner[gi] = 0;
		if (cells[gi] == b.mat[li]) {
			b.aux[li] = aux[gi];
			cells[gi] = AIR;
			aux[gi] = 0;
		}
		next.touch(gi % W, gi / W);
	}
	b.at.clear();
	b.from.clear();
	changed = true;
}

// Stamp b into the grid at its pose: every cell whose middle falls inside one of
// its pixels. Liquid and powder there go up to the first open cell above (through
// it and what else is in the way); rock or another body there hides that pixel.
void CrucibleSim::restamp(Body &b) {
	unstamp(b);
	const float cs = std::cos(b.a), sn = std::sin(b.a);
	float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
	const float xs[4] = { -b.cx, b.w - b.cx, -b.cx, b.w - b.cx };
	const float ys[4] = { -b.cy, -b.cy, b.h - b.cy, b.h - b.cy };
	for (int k = 0; k < 4; k++) {
		float wx = b.x + cs * xs[k] - sn * ys[k];
		float wy = b.y + sn * xs[k] + cs * ys[k];
		x0 = std::min(x0, wx);
		x1 = std::max(x1, wx);
		y0 = std::min(y0, wy);
		y1 = std::max(y1, wy);
	}
	int gx0 = std::max(2, (int)std::floor(x0)), gx1 = std::min(W - 3, (int)std::floor(x1));
	int gy0 = std::max(2, (int)std::floor(y0)), gy1 = std::min(H - 3, (int)std::floor(y1));
	for (int gy = gy0; gy <= gy1; gy++) {
		for (int gx = gx0; gx <= gx1; gx++) {
			float qx = gx + 0.5f - b.x, qy = gy + 0.5f - b.y;
			int ix = (int)std::floor(cs * qx + sn * qy + b.cx);
			int iy = (int)std::floor(-sn * qx + cs * qy + b.cy);
			if (ix < 0 || iy < 0 || ix >= b.w || iy >= b.h) {
				continue;
			}
			int li = iy * b.w + ix;
			uint8_t m = b.mat[li];
			if (!m) {
				continue;
			}
			int gi = gy * W + gx;
			if (owner[gi]) {
				continue;
			}
			uint8_t c = cells[gi];
			const Mat &C = mats[c];
			if (C.kind == K_STATIC) {
				continue;
			}
			if (C.kind == K_POWDER || C.kind == K_LIQUID) {
				bool placed = false;
				for (int up = 1; up <= DISPLACE_UP && gy - up >= 2; up++) {
					int j = gi - up * W;
					const Mat &U = mats[cells[j]];
					if (owner[j] == b.id || U.kind == K_POWDER || U.kind == K_LIQUID) {
						continue;
					}
					if (owner[j] || U.kind == K_STATIC) {
						break;
					}
					cells[j] = c;
					aux[j] = aux[gi];
					vel[j] = 0;
					next.touch(gx, gy - up);
					placed = true;
					break;
				}
				if (!placed) {
					spawn(gx + 0.5f, gy + 0.5f, b.vx * 0.5f + (frand(grng) - 0.5f) * 0.6f, -0.4f - frand(grng) * 0.6f, c, aux[gi]);
				}
			}
			cells[gi] = m;
			aux[gi] = b.aux[li];
			owner[gi] = (uint16_t)b.id;
			vel[gi] = 0;
			settle[gi] = 0;
			b.at.push_back(gi);
			b.from.push_back(li);
			next.touch(gx, gy);
		}
	}
	b.sx = b.x;
	b.sy = b.y;
	b.sa = b.a;
	changed = true;
}

// b breaks up where it's stamped: each pixel turns into what its ground crumbles
// into (dirt to loose dirt, stone to rubble), most of it falling where it is at the
// body's speed, one in eight thrown out as debris.
void CrucibleSim::shatter(Body &b) {
	bodies_shattered++;
	const float sp = std::sqrt(b.vx * b.vx + b.vy * b.vy);
	const uint8_t fall_v = (uint8_t)std::clamp((int)(std::max(b.vy, 0.0f) * 16.0f), 0, fall_max);
	for (size_t k = 0; k < b.at.size(); k++) {
		int gi = b.at[k], li = b.from[k];
		if (owner[gi] != b.id) {
			continue;
		}
		owner[gi] = 0;
		if (cells[gi] != b.mat[li]) {
			continue;
		}
		const Mat &M = mats[cells[gi]];
		int into = M.crumbles_into >= 0 ? M.crumbles_into : (M.shatters_to >= 0 ? M.shatters_to : cells[gi]);
		uint8_t a = (M.burn_life && aux[gi] && mats[into].burn_life) ? aux[gi] : init_aux((uint8_t)into, lcg(grng));
		int x = gi % W, y = gi / W;
		if (M.glows) {
			mark_lava(x, y);
		}
		if (mats[into].kind == K_POWDER && (lcg(grng) & 7) != 0) {
			cells[gi] = (uint8_t)into;
			aux[gi] = a;
			vel[gi] = fall_v;
		} else {
			cells[gi] = AIR;
			aux[gi] = 0;
			spawn(x + 0.5f, y + 0.5f, b.vx * 0.4f + (frand(grng) - 0.5f) * (0.6f + sp * 0.2f),
					-(0.3f + frand(grng) * (0.4f + sp * 0.25f)), (uint8_t)into, a);
		}
		next.touch(x, y);
	}
	b.at.clear();
	b.from.clear();
	b.count = 0;
	changed = true;
}

// b comes to rest: drawn where it's got to, its cells are ground again.
void CrucibleSim::settle_body(Body &b) {
	bodies_settled++;
	if (std::fabs(b.x - b.sx) + std::fabs(b.y - b.sy) + std::fabs(b.a - b.sa) > 0.0f) {
		restamp(b);
	}
	for (int gi : b.at) {
		if (owner[gi] == b.id) {
			owner[gi] = 0;
			next.touch(gi % W, gi / W);
		}
	}
	b.at.clear();
	b.from.clear();
	changed = true;
}

// A blast at (x, y) shoves the bodies it reaches away from it, lighter ones more.
void CrucibleSim::push_bodies(float x, float y, float rad, int power) {
	for (Body &b : bodies) {
		float dx = b.x - x, dy = b.y - y;
		float d = std::sqrt(dx * dx + dy * dy);
		float reach = rad + b.radius;
		if (d >= reach) {
			continue;
		}
		if (d < 1e-3f) {
			dx = 0.0f;
			dy = -1.0f;
			d = 1.0f;
		}
		float f = 1.0f - d / reach;
		float dv = power * 1.5f * f / std::sqrt(std::max(1.0f, b.mass / 100.0f));
		b.vx += dx / d * dv;
		b.vy += dy / d * dv - 0.2f * f;
		b.spin += (frand(grng) - 0.5f) * 0.1f * f;
		b.rest = 0;
	}
}
