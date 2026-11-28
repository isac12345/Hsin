// HSIN engine: abstract 2D canvas. Stage coordinates, uniform scale, no rotation.
// Alpha is premultiplied everywhere.
#pragma once
#include <cstdint>
#include <cmath>
#include <vector>
#include <string>

namespace hs {

struct Col {
  float r = 0, g = 0, b = 0, a = 1;
  Col() {}
  Col(float r_, float g_, float b_, float a_ = 1) : r(r_), g(g_), b(b_), a(a_) {}
  Col withA(float na) const { return Col(r, g, b, a * na); }
};

struct Rect {
  float x = 0, y = 0, w = 0, h = 0;
  Rect() {}
  Rect(float x_, float y_, float w_, float h_) : x(x_), y(y_), w(w_), h(h_) {}
  bool has(float px, float py) const { return px >= x && py >= y && px < x + w && py < y + h; }
  Rect inter(const Rect& o) const {
    float x0 = std::fmax(x, o.x), y0 = std::fmax(y, o.y);
    float x1 = std::fmin(x + w, o.x + o.w), y1 = std::fmin(y + h, o.y + o.h);
    return Rect(x0, y0, std::fmax(0.f, x1 - x0), std::fmax(0.f, y1 - y0));
  }
  bool empty() const { return w <= 0 || h <= 0; }
};

enum TexFmt { TEX_RGBA = 0, TEX_A8 = 1 };

class Canvas {
 public:
  virtual ~Canvas() {}
  // Physical pixel size of the target. Clears with c.
  virtual void begin(int pw, int ph, Col clear) = 0;
  virtual void end() = 0;

  // Base transform stage -> physical px: p*s + t
  virtual void setBase(float tx, float ty, float s) = 0;
  virtual void pushT(float dx, float dy, float scale = 1.f) = 0;  // child transform (stage units)
  virtual void popT() = 0;
  virtual void pushClip(Rect r) = 0;                              // current stage coords
  virtual void popClip() = 0;

  // Primitives (current stage coords). stroke==0 -> fill.
  virtual void rrect(float x, float y, float w, float h, float rad, Col c, float stroke = 0) = 0;
  virtual void line(float x0, float y0, float x1, float y1, float w, Col c) = 0;
  // Texture quad. src in texels. RGBA: colour = tex * tint. A8: colour = tint * tex.r.
  virtual void quad(int tex, Rect dst, Rect src, Col tint, float rad = -1) = 0;  // rad >= 0: rounded-rect mask

  virtual int texCreate(int w, int h, TexFmt f, const uint8_t* data) = 0;
  virtual void texUpdate(int id, int x, int y, int w, int h, const uint8_t* data, int stridePx) = 0;
  virtual void texDestroy(int id) = 0;
  virtual void texSize(int id, int* w, int* h) = 0;

  // Current transform queries (for pixel-aligned text and hit tests).
  float curS() const { return cs_; }
  float curTx() const { return ctx_; }
  float curTy() const { return cty_; }
  Rect curClipStage() const { return clipStage_; }  // in base stage coords
  Rect toStage(Rect r) const {                      // local -> base stage
    float s = cs_ / baseS_;
    return Rect((r.x * cs_ + ctx_ - baseTx_) / baseS_, (r.y * cs_ + cty_ - baseTy_) / baseS_, r.w * s, r.h * s);
  }
  float stageToLocalX(float sx) const { return (sx * baseS_ + baseTx_ - ctx_) / cs_; }
  float stageToLocalY(float sy) const { return (sy * baseS_ + baseTy_ - cty_) / cs_; }
  void setAlpha(float a) { galpha_ = a; }
  float alpha() const { return galpha_; }
  int physW() const { return pw_; }
  int physH() const { return ph_; }
  int drawCalls = 0;  // stats

 protected:
  float galpha_ = 1.f;
  int pw_ = 0, ph_ = 0;
  float baseTx_ = 0, baseTy_ = 0, baseS_ = 1;
  float ctx_ = 0, cty_ = 0, cs_ = 1;
  Rect clipStage_;
};

}  // namespace hs
