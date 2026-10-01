// Machine casings (the game's scripts/machines/): a module is a rigid body whose walls
// are real cells. The engine's part is small. A module body never settles back into
// ground (set_module), and the game can read its bitmap and change single pixels, which
// is how a port opens and closes and how a wall is knocked through without a blast.
// Everything else (faces, integrity, breach, wreckage) lives in GDScript.

#include "crucible_sim.h"

using namespace godot;

// Body `id` never turns back into ground, however still it lies. False if there's no
// such body.
bool CrucibleSim::set_module(int id, bool on) {
	for (Body &b : bodies) {
		if (b.id == id) {
			b.module = on;
			return true;
		}
	}
	return false;
}

// Body `id`'s bitmap: [width, height, centre of mass x, centre of mass y, pixels]. The
// centre is in bitmap cells (a pixel's middle is at +0.5), the same frame body_state's
// pose uses. Empty if there's no such body.
PackedFloat32Array CrucibleSim::body_info(int id) const {
	PackedFloat32Array out;
	for (const Body &b : bodies) {
		if (b.id == id) {
			out.resize(5);
			float *o = out.ptrw();
			o[0] = (float)b.w;
			o[1] = (float)b.h;
			o[2] = b.cx;
			o[3] = b.cy;
			o[4] = (float)b.count;
			break;
		}
	}
	return out;
}

// Body `id`'s material per pixel, row by row (0 is empty); empty if there's no such body.
PackedByteArray CrucibleSim::body_pixels(int id) const {
	PackedByteArray out;
	for (const Body &b : bodies) {
		if (b.id == id) {
			out.resize((int64_t)b.mat.size());
			memcpy(out.ptrw(), b.mat.data(), b.mat.size());
			break;
		}
	}
	return out;
}

// Sets pixel (lx, ly) of body `id` to material m (0 removes it) and returns the pixels
// it has now, or -1 if there's no such body or pixel or nothing would be left. The
// body keeps its place in the world as its centre of mass shifts.
int CrucibleSim::body_set_pixel(int id, int lx, int ly, int m) {
	if (m < 0 || m > 255) {
		return -1;
	}
	for (Body &b : bodies) {
		if (b.id != id) {
			continue;
		}
		if (lx < 0 || ly < 0 || lx >= b.w || ly >= b.h) {
			return -1;
		}
		int li = ly * b.w + lx;
		if (b.mat[li] == m) {
			return b.count;
		}
		unstamp(b);
		b.mat[li] = (uint8_t)m;
		b.aux[li] = 0;
		if (!body_shape(b)) {
			return -1; // nothing left: the game removes the body
		}
		restamp(b);
		return b.count;
	}
	return -1;
}
