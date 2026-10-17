// SPIKE (throwaway): position-based joints between bodies, to see whether the approach holds up
// against pixel ground. Not the A8 implementation.

#include "crucible_sim.h"

using namespace godot;

namespace {
struct P {
	float x, y;
};
} // namespace

static P world_pt(const CrucibleSim::Body &b, float lx, float ly) {
	float cs = std::cos(b.a), sn = std::sin(b.a);
	float dx = lx - b.cx, dy = ly - b.cy;
	return { b.x + cs * dx - sn * dy, b.y + sn * dx + cs * dy };
}

static P local_pt(const CrucibleSim::Body &b, float wx, float wy) {
	float cs = std::cos(b.a), sn = std::sin(b.a);
	float qx = wx - b.x, qy = wy - b.y;
	return { cs * qx + sn * qy + b.cx, -sn * qx + cs * qy + b.cy };
}

int CrucibleSim::add_joint(int a, float ax, float ay, int b, float bx, float by, int type, float len, float motor) {
	Joint j;
	j.id = next_joint++;
	j.a = a;
	j.b = b;
	j.type = type;
	j.motor = motor;
	P pa = { ax, ay }, pb = { bx, by };
	for (const Body &bd : bodies) {
		if (bd.id == a) {
			pa = local_pt(bd, ax, ay);
		}
		if (b != 0 && bd.id == b) {
			pb = local_pt(bd, bx, by);
		}
	}
	j.lax = pa.x;
	j.lay = pa.y;
	j.lbx = pb.x;
	j.lby = pb.y;
	j.len = len;
	if (len < 0) {
		j.len = std::sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
	}
	joints.push_back(j);
	rebuild_partners();
	return j.id;
}

bool CrucibleSim::remove_joint(int id) {
	for (size_t k = 0; k < joints.size(); k++) {
		if (joints[k].id == id) {
			joints.erase(joints.begin() + k);
			rebuild_partners();
			return true;
		}
	}
	return false;
}

PackedFloat32Array CrucibleSim::joint_state(int id) const {
	PackedFloat32Array out;
	for (const Joint &j : joints) {
		if (j.id == id) {
			out.push_back(j.strain);
		}
	}
	return out;
}

void CrucibleSim::set_joint_limit(int id, float limit) {
	for (Joint &j : joints) {
		if (j.id == id) {
			j.limit = limit;
		}
	}
}

void CrucibleSim::rebuild_partners() {
	// Bodies in one jointed assembly (a cluster) don't collide with each other.
	std::vector<int> root(bodies.size());
	for (size_t k = 0; k < bodies.size(); k++) {
		root[k] = (int)k;
		bodies[k].partners.clear();
	}
	auto find = [&](int x) {
		while (root[x] != x) {
			root[x] = root[root[x]];
			x = root[x];
		}
		return x;
	};
	auto index = [&](int id) {
		for (size_t k = 0; k < bodies.size(); k++) {
			if (bodies[k].id == id) {
				return (int)k;
			}
		}
		return -1;
	};
	for (const Joint &j : joints) {
		if (j.b == 0) {
			continue;
		}
		int ia = index(j.a), ib = index(j.b);
		if (ia >= 0 && ib >= 0) {
			root[find(ia)] = find(ib);
		}
	}
	for (size_t k = 0; k < bodies.size(); k++) {
		for (size_t m = 0; m < bodies.size(); m++) {
			if (m != k && find((int)m) == find((int)k)) {
				bodies[k].partners.push_back((uint16_t)bodies[m].id);
			}
		}
	}
}

void CrucibleSim::solve_joints() {
	if (joints.empty()) {
		return;
	}
	if (bidx.size() < 65536) {
		bidx.assign(65536, -1);
	}
	for (size_t k = 0; k < bodies.size(); k++) {
		bidx[bodies[k].id] = (int)k;
	}
	// Snap what is over its limit, drop what lost a body.
	bool dropped = false;
	for (size_t k = 0; k < joints.size();) {
		Joint &j = joints[k];
		bool gone = bidx[j.a] < 0 || (j.b != 0 && bidx[j.b] < 0) || j.strain > j.limit;
		if (gone) {
			joints.erase(joints.begin() + k);
			dropped = true;
		} else {
			k++;
		}
	}
	if (dropped) {
		rebuild_partners();
	}
	std::vector<char> moved(bodies.size(), 0);
	const int ITER = 8;
	for (int it = 0; it < ITER; it++) {
		for (Joint &j : joints) {
			Body &A = bodies[bidx[j.a]];
			Body *B = j.b != 0 ? &bodies[bidx[j.b]] : nullptr;
			float wa = A.drive > 0 ? 0.0f : 1.0f / A.mass, ia = A.drive > 0 ? 0.0f : 1.0f / A.inertia;
			float wb = B && B->drive == 0 ? 1.0f / B->mass : 0.0f, ib = B && B->drive == 0 ? 1.0f / B->inertia : 0.0f;
			int axes = j.type == 1 ? 1 : 2;
			for (int ax = 0; ax < axes; ax++) {
				P pa = world_pt(A, j.lax, j.lay);
				P pb = B ? world_pt(*B, j.lbx, j.lby) : P{ j.lbx, j.lby };
				float nx, ny, C;
				if (j.type == 1) {
					float dx = pb.x - pa.x, dy = pb.y - pa.y;
					float d = std::sqrt(dx * dx + dy * dy);
					if (d <= j.len || d < 1e-5f) {
						break;
					}
					nx = dx / d;
					ny = dy / d;
					C = d - j.len;
				} else {
					nx = ax == 0 ? 1.0f : 0.0f;
					ny = ax == 0 ? 0.0f : 1.0f;
					C = (pb.x - pa.x) * nx + (pb.y - pa.y) * ny;
				}
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
					continue;
				}
				float d = C / k;
				if (it == 0) {
					j.strain = ax == 0 ? std::fabs(C) : std::max(j.strain, std::fabs(C));
				}
				A.x += nx * wa * d;
				A.y += ny * wa * d;
				A.a += cra * ia * d;
				A.vx += nx * wa * d;
				A.vy += ny * wa * d;
				A.spin += cra * ia * d;
				moved[bidx[j.a]] = 1;
				if (B) {
					B->x -= nx * wb * d;
					B->y -= ny * wb * d;
					B->a -= crb * ib * d;
					B->vx -= nx * wb * d;
					B->vy -= ny * wb * d;
					B->spin -= crb * ib * d;
					moved[bidx[j.b]] = 1;
				}
			}
		}
	}
	for (Joint &j : joints) {
		if (j.type == 2) {
			bodies[bidx[j.a]].spin = j.motor / 60.0f;
		}
	}
	for (size_t k = 0; k < bodies.size(); k++) {
		Body &b = bodies[k];
		if (moved[k] && std::fabs(b.x - b.sx) + std::fabs(b.y - b.sy) + std::fabs(b.a - b.sa) * b.radius > 0.35f) {
			restamp(b);
		}
	}
	for (size_t k = 0; k < bodies.size(); k++) {
		bidx[bodies[k].id] = -1;
	}
}
