// The sim's random numbers, shared by crucible_sim.cpp and bodies.cpp.

#ifndef CRUCIBLE_RNG_H
#define CRUCIBLE_RNG_H

#include <cstdint>

namespace crucible {

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

} // namespace crucible

#endif
