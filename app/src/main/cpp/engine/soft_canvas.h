// CPU reference backend: used by host tests and screenshots (same maths as the GL shader).
#pragma once
#include "canvas_base.h"

namespace hs {

class SoftCanvas : public CanvasBase {
 public:
  void begin(int pw, int ph, Col clear) override;
  void end() override {}
  void rrect(float x, float y, float w, float h, float rad, Col c, float stroke = 0) override;
  void line(float x0, float y0, float x1, float y1, float w, Col c) override;
  void quad(int tex, Rect dst, Rect src, Col tint, float rad = -1) override;
  int texCreate(int w, int h, TexFmt f, const uint8_t* data) override;
  void texUpdate(int id, int x, int y, int w, int h, const uint8_t* data, int stridePx) override;
  void texDestroy(int id) override;
  void texSize(int id, int* w, int* h) override;
  // Writes the frame as RGB PNG.
  bool savePng(const char* path) const;
  const std::vector<float>& pixels() const { return fb_; }

 private:
  struct Tex { int w = 0, h = 0; TexFmt f = TEX_RGBA; std::vector<uint8_t> d; bool used = false; };
  std::vector<Tex> tex_;
  std::vector<float> fb_;
  inline void put(int x, int y, float r, float g, float b, float a) {
    float* p = &fb_[((size_t)y * pw_ + x) * 4];
    float k = 1.f - a;
    p[0] = r + p[0] * k; p[1] = g + p[1] * k; p[2] = b + p[2] * k; p[3] = a + p[3] * k;
  }
  bool bbox(float x0, float y0, float x1, float y1, int* ix0, int* iy0, int* ix1, int* iy1) const;
};

}  // namespace hs
