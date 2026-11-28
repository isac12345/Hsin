// Glyph cache on top of stb_truetype. Fonts are TTF blobs that must outlive Fonts.
#pragma once
#include "gfx.h"
#include <unordered_map>

namespace hs {

class Fonts {
 public:
  explicit Fonts(Canvas* c) : cv_(c) {}
  ~Fonts();
  int add(const uint8_t* ttf, size_t n);  // returns font id or -1
  // Width in stage units at size (stage units).
  float width(int font, const std::string& s, float size, float spacing = 0);
  // Draw text with baseline at y + ascent. align: 0 left, 1 centre, 2 right (relative to x).
  void draw(Canvas& cv, int font, const std::string& s, float x, float y, float size, Col col, int align = 0, float spacing = 0);
  // Greedy word wrap.
  void wrap(int font, const std::string& s, float size, float maxW, std::vector<std::string>* out);
  float ascent(int font, float size);
  void frameStart();  // call once per frame (handles atlas reset)
  void recreate(Canvas* c);  // after GL context loss
 private:
  struct Face;
  struct G { float u = 0, v = 0, w = 0, h = 0, xo = 0, yo = 0, adv = 0; bool ok = false; };
  const G& glyph(int font, int px, uint32_t cp);
  void sync();
  Canvas* cv_;
  std::vector<Face*> faces_;
  std::unordered_map<uint64_t, G> cache_;
  std::vector<uint8_t> atlas_;
  int tex_ = 0, aw_ = 1024, ah_ = 1024, penX_ = 1, penY_ = 1, rowH_ = 0;
  bool dirty_ = false, needReset_ = false;
  int dx0_ = 0, dy0_ = 0, dx1_ = 0, dy1_ = 0;
};

}  // namespace hs
