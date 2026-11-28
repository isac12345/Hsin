#include "font.h"
#define STB_TRUETYPE_IMPLEMENTATION
#include "../third_party/stb_truetype.h"
#include <algorithm>

namespace hs {

struct Fonts::Face {
  stbtt_fontinfo info;
  int asc = 0, desc = 0, gap = 0;
};

Fonts::~Fonts() {
  for (auto f : faces_) delete f;
}

static uint32_t nextCp(const std::string& s, size_t* i) {
  unsigned char c = s[*i];
  uint32_t cp = c;
  int n = 0;
  if (c >= 0xF0) { cp = c & 7; n = 3; } else if (c >= 0xE0) { cp = c & 15; n = 2; } else if (c >= 0xC0) { cp = c & 31; n = 1; }
  (*i)++;
  while (n-- > 0 && *i < s.size() && (((unsigned char)s[*i]) & 0xC0) == 0x80) { cp = (cp << 6) | (s[*i] & 63); (*i)++; }
  return cp;
}

int Fonts::add(const uint8_t* ttf, size_t) {
  Face* f = new Face();
  int off = stbtt_GetFontOffsetForIndex(ttf, 0);
  if (!stbtt_InitFont(&f->info, ttf, off)) { delete f; return -1; }
  stbtt_GetFontVMetrics(&f->info, &f->asc, &f->desc, &f->gap);
  faces_.push_back(f);
  if (!tex_) {
    atlas_.assign((size_t)aw_ * ah_, 0);
    tex_ = cv_->texCreate(aw_, ah_, TEX_A8, atlas_.data());
  }
  return (int)faces_.size() - 1;
}

void Fonts::recreate(Canvas* c) {
  cv_ = c;
  tex_ = 0;
  cache_.clear();
  atlas_.assign((size_t)aw_ * ah_, 0);
  penX_ = penY_ = 1; rowH_ = 0; dirty_ = false; needReset_ = false;
  if (!faces_.empty()) tex_ = cv_->texCreate(aw_, ah_, TEX_A8, atlas_.data());
}

void Fonts::frameStart() {
  if (needReset_) {
    cache_.clear();
    std::fill(atlas_.begin(), atlas_.end(), 0);
    penX_ = penY_ = 1; rowH_ = 0; needReset_ = false;
    cv_->texUpdate(tex_, 0, 0, aw_, ah_, atlas_.data(), aw_);
    dirty_ = false;
  }
}

const Fonts::G& Fonts::glyph(int font, int px, uint32_t cp) {
  uint64_t key = ((uint64_t)font << 48) | ((uint64_t)px << 32) | cp;
  auto it = cache_.find(key);
  if (it != cache_.end()) return it->second;
  G g;
  Face* f = faces_[font];
  float sc = stbtt_ScaleForPixelHeight(&f->info, (float)px);
  int gi = stbtt_FindGlyphIndex(&f->info, (int)cp);
  int adv = 0, lsb = 0;
  stbtt_GetGlyphHMetrics(&f->info, gi, &adv, &lsb);
  g.adv = adv * sc;
  if (gi != 0) {
    int x0, y0, x1, y1;
    stbtt_GetGlyphBitmapBox(&f->info, gi, sc, sc, &x0, &y0, &x1, &y1);
    int w = x1 - x0, h = y1 - y0;
    if (w > 0 && h > 0) {
      if (penX_ + w + 1 > aw_) { penX_ = 1; penY_ += rowH_ + 1; rowH_ = 0; }
      if (penY_ + h + 1 > ah_) {
        needReset_ = true;  // flush at next frame start; skip this glyph now
        return cache_[key] = g;
      }
      stbtt_MakeGlyphBitmap(&f->info, &atlas_[(size_t)penY_ * aw_ + penX_], w, h, aw_, sc, sc, gi);
      g.u = (float)penX_; g.v = (float)penY_; g.w = (float)w; g.h = (float)h;
      g.xo = (float)x0; g.yo = (float)y0; g.ok = true;
      if (!dirty_) { dx0_ = penX_; dy0_ = penY_; dx1_ = penX_ + w; dy1_ = penY_ + h; dirty_ = true; }
      else { dx0_ = std::min(dx0_, penX_); dy0_ = std::min(dy0_, penY_); dx1_ = std::max(dx1_, penX_ + w); dy1_ = std::max(dy1_, penY_ + h); }
      penX_ += w + 1;
      rowH_ = std::max(rowH_, h);
    }
  }
  return cache_[key] = g;
}

void Fonts::sync() {
  if (!dirty_) return;
  cv_->texUpdate(tex_, dx0_, dy0_, dx1_ - dx0_, dy1_ - dy0_, &atlas_[(size_t)dy0_ * aw_ + dx0_], aw_);
  dirty_ = false;
}

static int pxFor(float size, float scale) {
  int px = (int)std::lround(size * scale);
  return px < 4 ? 4 : (px > 220 ? 220 : px);
}

float Fonts::ascent(int font, float size) {
  Face* f = faces_[font];
  return f->asc * stbtt_ScaleForPixelHeight(&f->info, size);
}

float Fonts::width(int font, const std::string& s, float size, float spacing) {
  if (font < 0 || font >= (int)faces_.size()) return 0;
  float scale = 1.f;  // measure at 1:1 stage units using unscaled metrics (no rasterising)
  Face* f = faces_[font];
  float sc = stbtt_ScaleForPixelHeight(&f->info, size * scale), w = 0;
  for (size_t i = 0; i < s.size();) {
    uint32_t cp = nextCp(s, &i);
    int adv, lsb;
    stbtt_GetCodepointHMetrics(&f->info, (int)cp, &adv, &lsb);
    w += adv * sc + spacing;
  }
  return w;
}

void Fonts::draw(Canvas& cv, int font, const std::string& s, float x, float y, float size, Col col, int align, float spacing) {
  if (font < 0 || font >= (int)faces_.size() || s.empty()) return;
  float S = cv.curS();
  int px = pxFor(size, S);
  float k = S / (float)std::max(1, 1);  // physical per stage unit
  (void)k;
  // Layout in physical px at the rasterised size, so spacing stays pixel-true.
  Face* f = faces_[font];
  float sc = stbtt_ScaleForPixelHeight(&f->info, (float)px);
  float base = y * S + cv.curTy() + f->asc * sc;
  float totalPx = 0;
  for (size_t i = 0; i < s.size();) {
    uint32_t cp = nextCp(s, &i);
    totalPx += glyph(font, px, cp).adv + spacing * S;
  }
  float ox = x * S + cv.curTx();
  if (align == 1) ox -= totalPx * .5f; else if (align == 2) ox -= totalPx;
  float penx = std::round(ox), by = std::round(base);
  // Base transform has no per-level offset in our maths: convert physical -> current stage coords.
  // Current local x = (phys - tx)/S.
  float tx = cv.curTx(), ty = cv.curTy();
  sync();  // glyphs may have been added by the width pass above
  std::vector<std::pair<Rect, Rect>> quads;
  for (size_t i = 0; i < s.size();) {
    uint32_t cp = nextCp(s, &i);
    const G& g = glyph(font, px, cp);
    if (g.ok) {
      float gx = std::round(penx + g.xo), gy = by + g.yo;
      quads.push_back({Rect((gx - tx) / S, (gy - ty) / S, g.w / S, g.h / S), Rect(g.u, g.v, g.w, g.h)});
    }
    penx += g.adv + spacing * S;
  }
  sync();
  for (auto& q : quads) cv.quad(tex_, q.first, q.second, col);
}

void Fonts::wrap(int font, const std::string& s, float size, float maxW, std::vector<std::string>* out) {
  std::string line, word;
  auto flushWord = [&]() {
    if (word.empty()) return;
    std::string t = line.empty() ? word : line + " " + word;
    if (!line.empty() && width(font, t, size) > maxW) { out->push_back(line); line = word; }
    else line = t;
    word.clear();
  };
  for (char c : s) {
    if (c == ' ') flushWord();
    else if (c == '\n') { flushWord(); out->push_back(line); line.clear(); }
    else word += c;
  }
  flushWord();
  if (!line.empty() || out->empty()) out->push_back(line);
}

}  // namespace hs
