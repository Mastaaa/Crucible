// Joints (A8): a joint holds two rigid bodies, or a body and a point of the world, to each other.
// It is solved by position, the way the bodies already move: each tick, after every body has
// moved and pushed itself out of the ground, a few passes pull each joint's anchors back
// together, weighted by mass (a body the game is driving counts as immovable, so a joint drags
// the other body and never the driven one). A body a joint pulled into rock keeps its pixels
// hidden there until the pull lets go: collision wins, the joint stretches, and past its limit
// it snaps.
//
// Types:
//  PIN    the anchors meet; the bodies turn freely about them (a Hinge)
//  ROPE   the anchors are never more than `len` apart; slack is allowed
//  WELD   a pin that also holds the angle (a Bolt, a Strut's ends)
//  MOTOR  a pin whose angle is asked to turn at `rate`; a blocked motor stops where it is, and its
//         target never runs more than `lag` radians ahead of the pose
//  SLIDE  the anchors stay on one line (the axis, in a's frame) at a fixed angle, free between
//         `lo` and `hi`, or with `drive` following `goal` at `rate` cells a tick (Piston, Gantry)
// Each joint measures `strain` (the first pull of the tick, in cells) and `load` (the impulse all
// the passes put in, averaged over a few ticks); past `limit` or `max_load` it snaps. A rooted world joint also lets go when
// the cell under its anchor is no longer ground. Bodies in one assembly (joined by anything but
// a rope) pass through each other.

#include "crucible_sim.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

struct P {
	float x, y;
};

constexpr int ITER = 10;
constexpr float LOAD_MIX = 0.2f; // how much of a tick's load joins the running load
constexpr double TWO_PI = 6.283185307179586;
constexpr uint8_t BUILDING = 5;

P world_pt(const CrucibleSim::Body &b, float lx, float ly) {
	float cs = std::cos(b.a), sn = std::sin(b.a);
	float dx = lx - b.cx, dy = ly - b.cy;
	return { b.x + cs * dx - sn * dy, b.y + sn * dx + cs * dy };
}

P local_pt(const CrucibleSim::Body &b, float wx, float wy) {
	float cs = std::cos(b.a), sn = std::sin(b.a);
	float qx = wx - b.x, qy = wy - b.y;
	return { cs * qx + sn * qy + b.cx, -sn * qx + cs * qy + b.cy };
}

} // namespace

// --- The game's side --------------------------------------------------------------

// Keys (all optional but type and a): type (0 pin, 1 rope, 2 weld, 3 motor, 4 slide), a and b
// (body ids; b 0 or missing is the world), ax and ay (the anchor on a, in world cells), bx and
// by (the anchor on b, default the same place), len (rope, default the gap now), limit and
// max_load (snap past), rooted, rate (motor radians a second, slide cells a second), lag,
// drive (slide), goal, lo and hi (slide, cells from where it is now), dx and dy (the slide's
// way in the world, default from a's anchor to b's). Returns the joint's id, or -1.
int CrucibleSim::add_joint(const Dictionary &p) {
	int a = (int)p.get("a", 0), b = (int)p.get("b", 0);
	int type = (int)p.get("type", 0);
	Body *A = body_by_id(a);
	Body *B = b != 0 ? body_by_id(b) : nullptr;
	if (!A || a == b || (b != 0 && !B) || type < 0 || type > Joint::SLIDE) {
		return -1;
	}
	Joint j;
	j.id = next_joint++;
	j.a = a;
	j.b = b;
	j.type = (uint8_t)type;
	float wax = (float)(double)p.get("ax", A->x), way = (float)(double)p.get("ay", A->y);
	float wbx = (float)(double)p.get("bx", wax), wby = (float)(double)p.get("by", way);
	P la = local_pt(*A, wax, way);
	j.lax = la.x;
	j.lay = la.y;
	if (B) {
		P lb = local_pt(*B, wbx, wby);
		j.lbx = lb.x;
		j.lby = lb.y;
	} else {
		j.lbx = wbx;
		j.lby = wby;
	}
	float dist = std::sqrt((wax - wbx) * (wax - wbx) + (way - wby) * (way - wby));
	j.len = (float)(double)p.get("len", dist);
	j.limit = (float)(double)p.get("limit", 1e9);
	j.max_load = (float)(double)p.get("max_load", 1e9);
	j.rooted = (bool)p.get("rooted", false) && !B;
	j.lag = (float)(double)p.get("lag", j.lag);
	j.drive = type == Joint::MOTOR || (bool)p.get("drive", false);
	const double rel = (double)A->a - (B ? (double)B->a : 0.0);
	j.rest = rel;
	if (type == Joint::MOTOR) {
		j.tgt = rel;
		j.rate = (float)((double)p.get("rate", 0.0) / 60.0);
	}
	if (type == Joint::SLIDE) {
		float dx = (float)(double)p.get("dx", wbx - wax), dy = (float)(double)p.get("dy", wby - way);
		float dl = std::sqrt(dx * dx + dy * dy);
		if (dl < 1e-6f) {
			dx = 1.0f;
			dy = 0.0f;
			dl = 1.0f;
		}
		dx /= dl;
		dy /= dl;
		float cs = std::cos(A->a), sn = std::sin(A->a);
		j.sx = cs * dx + sn * dy;
		j.sy = -sn * dx + cs * dy;
		j.ext0 = (wbx - wax) * dx + (wby - way) * dy;
		j.lo = (float)(double)p.get("lo", -1e9);
		j.hi = (float)(double)p.get("hi", 1e9);
		j.goal = (float)(double)p.get("goal", 0.0);
		j.rate = (float)((double)p.get("rate", 0.0) / 60.0);
		j.tgt = 0.0;
	}
	joints.push_back(j);
	rebuild_groups();
	return j.id;
}

bool CrucibleSim::set_joint(int id, const Dictionary &p) {
	for (Joint &j : joints) {
		if (j.id != id) {
			continue;
		}
		const double per_tick = 1.0 / 60.0;
		if (p.has("rate")) {
			j.rate = (float)((double)p["rate"] * per_tick);
		}
		if (p.has("goal")) {
			j.goal = (float)(double)p["goal"];
		}
		if (p.has("lo")) {
			j.lo = (float)(double)p["lo"];
		}
		if (p.has("hi")) {
			j.hi = (float)(double)p["hi"];
		}
		if (p.has("lag")) {
			j.lag = (float)(double)p["lag"];
		}
		if (p.has("len")) {
			j.len = (float)(double)p["len"];
		}
		if (p.has("limit")) {
			j.limit = (float)(double)p["limit"];
		}
		if (p.has("max_load")) {
			j.max_load = (float)(double)p["max_load"];
		}
		if (p.has("drive") && j.type == Joint::SLIDE) {
			j.drive = (bool)p["drive"];
		}
		if (p.has("rooted") && j.b == 0) {
			j.rooted = (bool)p["rooted"];
		}
		if (p.has("hold") && (bool)p["hold"]) {
			// Stop where it is: the target becomes the pose.
			const Body *A = body_by_id(j.a);
			const Body *B = j.b != 0 ? body_by_id(j.b) : nullptr;
			if (A && j.type == Joint::MOTOR) {
				j.tgt = (double)A->a - (B ? (double)B->a : 0.0);
				j.rate = 0.0f;
			}
			if (A && j.type == Joint::SLIDE) {
				float cs = std::cos(A->a), sn = std::sin(A->a);
				float ux = cs * j.sx - sn * j.sy, uy = sn * j.sx + cs * j.sy;
				P pa = world_pt(*A, j.lax, j.lay);
				P pb = B ? world_pt(*B, j.lbx, j.lby) : P{ j.lbx, j.lby };
				j.tgt = (pb.x - pa.x) * ux + (pb.y - pa.y) * uy - j.ext0;
				j.goal = (float)j.tgt;
			}
		}
		return true;
	}
	return false;
}

bool CrucibleSim::remove_joint(int id) {
	for (size_t k = 0; k < joints.size(); k++) {
		if (joints[k].id == id) {
			joints.erase(joints.begin() + (long)k);
			rebuild_groups();
			return true;
		}
	}
	return false;
}

// [strain, load, angle of a against b, how far apart (a slide: from where it was made), target
// (a motor's angle, a slide's position)]; empty if there is no such joint.
PackedFloat32Array CrucibleSim::joint_state(int id) const {
	PackedFloat32Array out;
	for (const Joint &j : joints) {
		if (j.id != id) {
			continue;
		}
		const Body *A = body_by_id(j.a);
		const Body *B = j.b != 0 ? body_by_id(j.b) : nullptr;
		if (!A) {
			break;
		}
		P pa = world_pt(*A, j.lax, j.lay);
		P pb = B ? world_pt(*B, j.lbx, j.lby) : P{ j.lbx, j.lby };
		float ext = std::sqrt((pb.x - pa.x) * (pb.x - pa.x) + (pb.y - pa.y) * (pb.y - pa.y));
		if (j.type == Joint::SLIDE) {
			float cs = std::cos(A->a), sn = std::sin(A->a);
			ext = (pb.x - pa.x) * (cs * j.sx - sn * j.sy) + (pb.y - pa.y) * (sn * j.sx + cs * j.sy) - j.ext0;
		}
		out.resize(5);
		float *o = out.ptrw();
		o[0] = j.strain;
		o[1] = j.load;
		o[2] = (float)((double)A->a - (B ? (double)B->a : 0.0));
		o[3] = ext;
		o[4] = (float)j.tgt;
		break;
	}
	return out;
}

PackedInt32Array CrucibleSim::joint_ids() const {
	PackedInt32Array out;
	for (const Joint &j : joints) {
		out.push_back(j.id);
	}
	return out;
}

// Joints that went since last asked: id, why (1 snapped, 2 lost a body, 3 its anchor let go).
PackedInt32Array CrucibleSim::take_joint_events() {
	PackedInt32Array out;
	out.resize((int64_t)joint_events.size());
	if (!joint_events.empty()) {
		memcpy(out.ptrw(), joint_events.data(), joint_events.size() * sizeof(int32_t));
	}
	joint_events.clear();
	return out;
}

// --- Bookkeeping ------------------------------------------------------------------

// A body is out of the list: its joints go with it.
void CrucibleSim::drop_joints_of(int body) {
	for (size_t k = 0; k < joints.size();) {
		if (joints[k].a == body || joints[k].b == body) {
			joint_events.push_back(joints[k].id);
			joint_events.push_back(2);
			joints.erase(joints.begin() + (long)k);
		} else {
			k++;
		}
	}
}

// Which bodies are held by a joint (they never turn back into ground), and which assemblies
// they form (everything joined by anything but a rope passes through itself).
void CrucibleSim::rebuild_groups() {
	if (bidx.size() < 65536) {
		reindex();
	}
	std::vector<int> root(bodies.size());
	for (size_t k = 0; k < bodies.size(); k++) {
		root[k] = (int)k;
		bodies[k].jointed = false;
		bodies[k].group = 0;
		bgrp[bodies[k].id] = 0;
	}
	auto find = [&](int x) {
		while (root[x] != x) {
			root[x] = root[root[x]];
			x = root[x];
		}
		return x;
	};
	for (const Joint &j : joints) {
		int ia = bidx[j.a], ib = j.b != 0 ? bidx[j.b] : -1;
		if (ia < 0) {
			continue;
		}
		bodies[ia].jointed = true;
		if (ib >= 0) {
			bodies[ib].jointed = true;
			if (j.type != Joint::ROPE) {
				int ra = find(ia), rb = find(ib);
				if (ra != rb) {
					// The lowest id names the assembly, so it doesn't change when a body joins.
					if (bodies[ra].id < bodies[rb].id) {
						root[rb] = ra;
					} else {
						root[ra] = rb;
					}
				}
			}
		}
	}
	std::vector<int> size(bodies.size(), 0);
	for (size_t k = 0; k < bodies.size(); k++) {
		size[find((int)k)]++;
	}
	for (size_t k = 0; k < bodies.size(); k++) {
		int r = find((int)k);
		if (size[r] > 1) {
			bodies[k].group = (uint16_t)bodies[r].id;
			bgrp[bodies[k].id] = (uint16_t)bodies[r].id;
		}
	}
}

// --- The solver -------------------------------------------------------------------

void CrucibleSim::solve_joints() {
	if (joints.empty()) {
		return;
	}
	// What snapped, lost a body or lost its footing last tick goes.
	bool dropped = false;
	for (size_t k = 0; k < joints.size();) {
		Joint &j = joints[k];
		int why = 0;
		if (!body_by_id(j.a) || (j.b != 0 && !body_by_id(j.b))) {
			why = 2;
		} else if (j.strain > j.limit || j.load > j.max_load) {
			why = 1;
		} else if (j.rooted) {
			int gx = (int)std::floor(j.lbx), gy = (int)std::floor(j.lby);
			bool held = gx >= 2 && gy >= 2 && gx < W - 2 && gy < H - 2;
			if (held) {
				int gi = gy * W + gx;
				held = mats[cells[gi]].kind == K_STATIC && owner[gi] == 0;
			}
			if (!held) {
				why = 3;
			}
		}
		if (why != 0) {
			joint_events.push_back(j.id);
			joint_events.push_back(why);
			joints.erase(joints.begin() + (long)k);
			dropped = true;
		} else {
			k++;
		}
	}
	if (dropped) {
		rebuild_groups();
	}
	if (joints.empty()) {
		return;
	}
	joint_moved.assign(bodies.size(), 0);

	// A motor's or piston's target moves on, but never far ahead of where the pose is.
	for (Joint &j : joints) {
		const Body &A = *body_by_id(j.a);
		const Body *B = j.b != 0 ? body_by_id(j.b) : nullptr;
		if (j.type == Joint::MOTOR) {
			double rel = (double)A.a - (B ? (double)B->a : 0.0);
			j.tgt = std::clamp(j.tgt + (double)j.rate, rel - (double)j.lag, rel + (double)j.lag);
		} else if (j.type == Joint::SLIDE && j.drive) {
			float cs = std::cos(A.a), sn = std::sin(A.a);
			P pa = world_pt(A, j.lax, j.lay);
			P pb = B ? world_pt(*B, j.lbx, j.lby) : P{ j.lbx, j.lby };
			double s = (pb.x - pa.x) * (cs * j.sx - sn * j.sy) + (pb.y - pa.y) * (sn * j.sx + cs * j.sy) - j.ext0;
			double goal = std::clamp((double)j.goal, (double)j.lo, (double)j.hi);
			double step = std::clamp(goal - j.tgt, -(double)j.rate, (double)j.rate);
			j.tgt = std::clamp(j.tgt + step, s - (double)j.lag, s + (double)j.lag);
		}
		j.lx = j.ly = j.lt = 0.0f;
	}

	// Where each body is before the passes pull it (collision wins over the joints, below).
	pre.assign(bodies.size() * 3, 0.0f);
	for (size_t k = 0; k < bodies.size(); k++) {
		pre[k * 3] = bodies[k].x;
		pre[k * 3 + 1] = bodies[k].y;
		pre[k * 3 + 2] = bodies[k].a;
	}

	// The ground a body already overlapped at the start of the passes does not count against it.
	std::vector<std::vector<int32_t>> skips(bodies.size());
	std::vector<char> skipped(bodies.size(), 0);
	auto skip_of = [&](size_t k) -> const std::vector<int32_t> & {
		if (!skipped[k]) {
			skipped[k] = 1;
			Contact c0;
			overlap(bodies[k], pre[k * 3], pre[k * 3 + 1], pre[k * 3 + 2], skips[k], c0, &skips[k]);
		}
		return skips[k];
	};
	// Slides body k out of ground the passes pulled it into, along the ground's normal; true if it is clear.
	auto depen = [&](size_t k) -> bool {
		Body &b = bodies[k];
		if (std::fabs(b.x - pre[k * 3]) + std::fabs(b.y - pre[k * 3 + 1]) + std::fabs(b.a - pre[k * 3 + 2]) * b.radius < 0.02f) {
			return true;
		}
		const std::vector<int32_t> &sk = skip_of(k);
		Contact c;
		if (!overlap(b, b.x, b.y, b.a, sk, c, nullptr)) {
			return true;
		}
		// Give up the turn first (a motor against a ledge keeps its pin): back off the way it was
		// turned, past where it started if that is what it takes.
		const float pa = pre[k * 3 + 2];
		if (std::fabs(b.a - pa) > 1e-4f) {
			const float dir = pa > b.a ? 1.0f : -1.0f;
			for (float d = 0.01f; d <= 0.3f; d += 0.01f) {
				Contact c2;
				if (!overlap(b, b.x, b.y, b.a + dir * d, sk, c2, nullptr)) {
					b.a += dir * d;
					return true;
				}
			}
		}
		// Then slide out along the ground's normal.
		float nx = -c.gx, ny = -c.gy;
		float len = std::sqrt(nx * nx + ny * ny);
		if (len < 0.5f) {
			return false;
		}
		nx /= len;
		ny /= len;
		for (float d = 0.25f; d <= 4.0f; d += 0.25f) {
			Contact c2;
			if (!overlap(b, b.x + nx * d, b.y + ny * d, b.a, sk, c2, nullptr)) {
				b.x += nx * d;
				b.y += ny * d;
				return true;
			}
		}
		return false;
	};

	for (int it = 0; it < ITER; it++) {
		for (Joint &j : joints) {
			Body &A = bodies[bidx[j.a]];
			Body *B = j.b != 0 ? &bodies[bidx[j.b]] : nullptr;
			const float wa = A.drove ? 0.0f : 1.0f / A.mass, ia = A.drove ? 0.0f : 1.0f / A.inertia;
			const float wb = B && !B->drove ? 1.0f / B->mass : 0.0f, ib = B && !B->drove ? 1.0f / B->inertia : 0.0f;
			const float lever = std::max(1.0f, A.radius);
			auto pts = [&](P &pa, P &pb) {
				pa = world_pt(A, j.lax, j.lay);
				pb = B ? world_pt(*B, j.lbx, j.lby) : P{ j.lbx, j.lby };
			};
			// Moves both bodies to close C (a gap along n measured from a's anchor to b's).
			auto push = [&](float nx, float ny, float C) {
				P pa, pb;
				pts(pa, pb);
				float rax = pa.x - A.x, ray = pa.y - A.y;
				float cra = rax * ny - ray * nx;
				float k = wa + cra * cra * ia;
				float crb = 0.0f;
				if (B) {
					float rbx = pb.x - B->x, rby = pb.y - B->y;
					crb = rbx * ny - rby * nx;
					k += wb + crb * crb * ib;
				}
				if (k < 1e-9f) {
					return;
				}
				float d = C / k;
				A.x += nx * wa * d;
				A.y += ny * wa * d;
				A.a += cra * ia * d;
				joint_moved[bidx[j.a]] = 1;
				if (B) {
					B->x -= nx * wb * d;
					B->y -= ny * wb * d;
					B->a -= crb * ib * d;
					joint_moved[bidx[j.b]] = 1;
				}
				j.lx += nx * d;
				j.ly += ny * d;
			};
			// Turns both bodies to close C (the angle of a against b, less what it should be).
			auto turn = [&](float C) {
				float k = ia + ib;
				if (k < 1e-9f) {
					return;
				}
				float d = C / k;
				A.a -= ia * d;
				joint_moved[bidx[j.a]] = 1;
				if (B) {
					B->a += ib * d;
					joint_moved[bidx[j.b]] = 1;
				}
				j.lt += std::fabs(d);
			};
			auto rel = [&]() { return (double)A.a - (B ? (double)B->a : 0.0); };
			// The pin part: the anchors meet.
			auto meet = [&](bool first) {
				P pa, pb;
				pts(pa, pb);
				float dx = pb.x - pa.x, dy = pb.y - pa.y;
				float d = std::sqrt(dx * dx + dy * dy);
				if (first) {
					j.strain = d;
				}
				if (d > 1e-5f) {
					push(dx / d, dy / d, d);
				}
			};
			switch (j.type) {
				case Joint::PIN:
					meet(it == 0);
					break;
				case Joint::ROPE: {
					P pa, pb;
					pts(pa, pb);
					float dx = pb.x - pa.x, dy = pb.y - pa.y;
					float d = std::sqrt(dx * dx + dy * dy);
					if (it == 0) {
						j.strain = std::max(0.0f, d - j.len);
					}
					if (d > j.len && d > 1e-5f) {
						push(dx / d, dy / d, d - j.len);
					}
					break;
				}
				case Joint::WELD:
				case Joint::MOTOR: {
					double want = j.type == Joint::MOTOR ? j.tgt : j.rest;
					float ca = (float)(rel() - want);
					if (it == 0) {
						meet(true);
						if (j.type == Joint::WELD) {
							j.strain = std::max(j.strain, std::fabs(ca) * lever);
						}
					} else {
						meet(false);
					}
					turn((float)(rel() - want));
					break;
				}
				case Joint::SLIDE: {
					float cs = std::cos(A.a), sn = std::sin(A.a);
					float ux = cs * j.sx - sn * j.sy, uy = sn * j.sx + cs * j.sy;
					P pa, pb;
					pts(pa, pb);
					float gx = pb.x - pa.x, gy = pb.y - pa.y;
					float perp = gx * -uy + gy * ux;
					float s = gx * ux + gy * uy - j.ext0;
					float t = j.drive ? (float)j.tgt : std::clamp(s, j.lo, j.hi);
					t = std::clamp(t, j.lo, j.hi);
					if (it == 0) {
						// How far it is off its line and its angle; a drive that is held back only shows in its lead.
						j.strain = std::max(std::fabs(perp), j.drive ? 0.0f : std::fabs(s - t));
						j.strain = std::max(j.strain, (float)std::fabs(rel() - j.rest) * lever);
					}
					turn((float)(rel() - j.rest));
					cs = std::cos(A.a);
					sn = std::sin(A.a);
					ux = cs * j.sx - sn * j.sy;
					uy = sn * j.sx + cs * j.sy;
					pts(pa, pb);
					gx = pb.x - pa.x;
					gy = pb.y - pa.y;
					push(-uy, ux, gx * -uy + gy * ux);
					pts(pa, pb);
					gx = pb.x - pa.x;
					gy = pb.y - pa.y;
					s = gx * ux + gy * uy - j.ext0;
					t = j.drive ? (float)j.tgt : std::clamp(s, j.lo, j.hi);
					t = std::clamp(t, j.lo, j.hi);
					if (std::fabs(s - t) > 1e-5f) {
						push(ux, uy, s - t);
					}
					break;
				}
			}
		}
		if (it % 3 == 2 && it < ITER - 1) {
			for (size_t k = 0; k < bodies.size(); k++) {
				if (joint_moved[k]) {
					depen(k);
				}
			}
		}
	}
	// Collision wins: whatever is still in ground it was not in at the start gives up the pull, the turn
	// first (a motor against a ledge), then all of it. The joint stays stretched (that is its strain)
	// and the motor or piston behind it stalls.
	for (size_t k = 0; k < bodies.size(); k++) {
		if (!joint_moved[k] || depen(k)) {
			continue;
		}
		Body &b = bodies[k];
		const float px = pre[k * 3], py = pre[k * 3 + 1], pa = pre[k * 3 + 2];
		const std::vector<int32_t> &sk = skip_of(k);
		auto free_at = [&](float x, float y, float a) {
			Contact c2;
			return !overlap(b, x, y, a, sk, c2, nullptr);
		};
		const float nx0 = b.x, ny0 = b.y, na0 = b.a;
		float lo = 0.0f, hi = 1.0f;
		for (int step = 0; step < 8; step++) {
			float mid = 0.5f * (lo + hi);
			if (free_at(nx0, ny0, pa + (na0 - pa) * mid)) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		if (lo > 0.0f || free_at(nx0, ny0, pa)) {
			b.a = pa + (na0 - pa) * lo;
		} else {
			lo = 0.0f;
			hi = 1.0f;
			for (int step = 0; step < 8; step++) {
				float mid = 0.5f * (lo + hi);
				if (free_at(px + (nx0 - px) * mid, py + (ny0 - py) * mid, pa + (na0 - pa) * mid)) {
					lo = mid;
				} else {
					hi = mid;
				}
			}
			b.x = px + (nx0 - px) * lo;
			b.y = py + (ny0 - py) * lo;
			b.a = pa + (na0 - pa) * lo;
		}
		b.last_hit = b.age;
	}

	// What a body moved over the whole tick, bounces and pulls and all, is its speed now. A joint
	// takes the springiness out of anything it holds.
	for (size_t k = 0; k < bodies.size(); k++) {
		Body &b = bodies[k];
		if (joint_moved[k] && !b.drove) {
			b.vx = b.x - b.px0;
			b.vy = b.y - b.py0;
			b.spin = b.a - b.pa0;
		}
	}

	for (Joint &j : joints) {
		const Body &A = *body_by_id(j.a);
		// An average over a few ticks: a pull that lasts breaks it, a one tick jolt does not.
		j.load += LOAD_MIX * (std::sqrt(j.lx * j.lx + j.ly * j.ly) + j.lt / std::max(1.0f, A.radius) - j.load);
	}

	for (size_t k = 0; k < bodies.size(); k++) {
		Body &b = bodies[k];
		if (joint_moved[k] && std::fabs(b.x - b.sx) + std::fabs(b.y - b.sy) + std::fabs(b.a - b.sa) * b.radius > 0.35f) {
			restamp(b);
		}
		// A motor can turn a body round and round; keep the angle small so it stays exact.
		if (std::fabs(b.a) > 4.0 * TWO_PI) {
			double shift = TWO_PI * std::round((double)b.a / TWO_PI);
			b.a -= (float)shift;
			b.sa -= (float)shift;
			b.aa -= (float)shift;
			for (Joint &j : joints) {
				if (j.a == b.id) {
					j.rest -= shift;
					if (j.type == Joint::MOTOR) {
						j.tgt -= shift;
					}
				}
				if (j.b == b.id) {
					j.rest += shift;
					if (j.type == Joint::MOTOR) {
						j.tgt += shift;
					}
				}
			}
		}
	}
	changed = true;
}
