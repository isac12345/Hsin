// Procedural ink-art drawing helpers (no bitmaps needed except optional grain).
#pragma once
#include "gfx.h"

namespace hs {

inline uint32_t hash32(uint32_t x) {
  x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
  return x;
}
inline float rnd(uint32_t seed, uint32_t i) { return (hash32(seed * 2654435761U + i * 40503U + 17U) & 0xFFFFFF) / 16777216.f; }
inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
inline float lerpf(float a, float b, float t) { return a + (b - a) * t; }

// Hand-drawn rectangle border. dashed draws gaps.
void roughBox(Canvas& cv, Rect r, uint32_t seed, float w, Col c, bool dashed = false, float amp = 0.8f);
// Brush stroke with taper and width wobble.
void brush(Canvas& cv, float x0, float y0, float x1, float y1, float w, Col c, uint32_t seed);
// Open circle stroke (ensō). from/to in turns [0,1], start at top going clockwise.
void enso(Canvas& cv, float cx, float cy, float r, float w, Col c, float from, float to, uint32_t seed);
// Tiled paper grain; tex is an A8 tile of size tile x tile.
void grain(Canvas& cv, int tex, int tile, Rect area, Col c);
int makeGrainTile(Canvas& cv, int tile);

enum Icon {
  IC_MODE, IC_GAME, IC_SETTING, IC_PLAY, IC_GEAR, IC_PLUS, IC_CHEV_R, IC_CHEV_D, IC_CHECK, IC_REC, IC_FPS, IC_RAM,
  IC_LOCK, IC_STAR, IC_TOOL, IC_INFO, IC_SUHSIN, IC_CLOSE, IC_GLOBE, IC_DEX, IC_TEMP, IC_COUNT
};
// Draws icon within square (x,y,size). sw = stroke width in stage units.
void icon(Canvas& cv, Icon id, float x, float y, float size, Col c, float sw = 1.9f);

// Full-stage ink sweep. p: 0..1. Covers until 0.5, reveals after. Returns true when the screen is fully covered.
bool inkSweep(Canvas& cv, Rect stage, float p, Col ink, uint32_t seed);
// Expanding wash from a point. p 0..1.
void inkWash(Canvas& cv, Rect stage, float cx, float cy, float p, Col ink);

}  // namespace hs
