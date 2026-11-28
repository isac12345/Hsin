#include "soft_canvas.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../third_party/stb_image_write.h"
#include <algorithm>

namespace hs {

static inline float clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

void SoftCanvas::begin(int pw, int ph, Col c) {
  pw_ = pw; ph_ = ph; drawCalls = 0; galpha_ = 1.f;
  fb_.assign((size_t)pw * ph * 4, 0.f);
  for (size_t i = 0; i < (size_t)pw * ph; i++) {
    fb_[i * 4] = c.r * c.a; fb_[i * 4 + 1] = c.g * c.a; fb_[i * 4 + 2] = c.b * c.a; fb_[i * 4 + 3] = c.a;
  }
  setBase(0, 0, 1);
}

bool SoftCanvas::bbox(float x0, float y0, float x1, float y1, int* ix0, int* iy0, int* ix1, int* iy1) const {
  *ix0 = (int)std::floor(std::fmax(x0, clipPx_.x));
  *iy0 = (int)std::floor(std::fmax(y0, clipPx_.y));
  *ix1 = (int)std::ceil(std::fmin(x1, clipPx_.x + clipPx_.w));
  *iy1 = (int)std::ceil(std::fmin(y1, clipPx_.y + clipPx_.h));
  *ix0 = std::max(*ix0, 0); *iy0 = std::max(*iy0, 0);
  *ix1 = std::min(*ix1, pw_); *iy1 = std::min(*iy1, ph_);
  return *ix1 > *ix0 && *iy1 > *iy0;
}

void SoftCanvas::rrect(float x, float y, float w, float h, float rad, Col c, float stroke) {
  float s = cs_;
  float px = x * s + ctx_, py = y * s + cty_, pwid = w * s, phei = h * s;
  float r = std::fmin(rad * s, std::fmin(pwid, phei) * 0.5f), sw = stroke * s;
  int x0, y0, x1, y1;
  if (!bbox(px - 1, py - 1, px + pwid + 1, py + phei + 1, &x0, &y0, &x1, &y1)) return;
  drawCalls++;
  float cx = px + pwid * .5f, cy = py + phei * .5f, hx = pwid * .5f - r, hy = phei * .5f - r;
  for (int j = y0; j < y1; j++) for (int i = x0; i < x1; i++) {
    float qx = std::fabs(i + .5f - cx) - hx, qy = std::fabs(j + .5f - cy) - hy;
    float d = std::hypot(std::fmax(qx, 0.f), std::fmax(qy, 0.f)) + std::fmin(std::fmax(qx, qy), 0.f) - r;
    float a = clamp01(.5f - d);
    if (stroke > 0) a *= clamp01(d + sw + .5f);
    if (a <= 0) continue;
    a *= c.a * galpha_;
    put(i, j, c.r * a, c.g * a, c.b * a, a);
  }
}

void SoftCanvas::line(float ax, float ay, float bx, float by, float w, Col c) {
  float s = cs_;
  float x0 = ax * s + ctx_, y0 = ay * s + cty_, x1 = bx * s + ctx_, y1 = by * s + cty_, hw = w * s * .5f;
  int i0, j0, i1, j1;
  if (!bbox(std::fmin(x0, x1) - hw - 1, std::fmin(y0, y1) - hw - 1, std::fmax(x0, x1) + hw + 1, std::fmax(y0, y1) + hw + 1, &i0, &j0, &i1, &j1)) return;
  drawCalls++;
  float dx = x1 - x0, dy = y1 - y0, l2 = dx * dx + dy * dy;
  for (int j = j0; j < j1; j++) for (int i = i0; i < i1; i++) {
    float pxx = i + .5f - x0, pyy = j + .5f - y0;
    float t = l2 > 1e-6f ? clamp01((pxx * dx + pyy * dy) / l2) : 0.f;
    float d = std::hypot(pxx - dx * t, pyy - dy * t) - hw;
    float a = clamp01(.5f - d) * c.a * galpha_;
    if (a <= 0) continue;
    put(i, j, c.r * a, c.g * a, c.b * a, a);
  }
}

int SoftCanvas::texCreate(int w, int h, TexFmt f, const uint8_t* data) {
  Tex t; t.w = w; t.h = h; t.f = f; t.used = true;
  size_t n = (size_t)w * h * (f == TEX_RGBA ? 4 : 1);
  t.d.assign(n, 0);
  if (data) std::copy(data, data + n, t.d.begin());
  for (size_t i = 0; i < tex_.size(); i++) if (!tex_[i].used) { tex_[i] = std::move(t); return (int)i + 1; }
  tex_.push_back(std::move(t));
  return (int)tex_.size();
}

void SoftCanvas::texUpdate(int id, int x, int y, int w, int h, const uint8_t* data, int stride) {
  if (id < 1 || id > (int)tex_.size()) return;
  Tex& t = tex_[id - 1];
  int bpp = t.f == TEX_RGBA ? 4 : 1;
  for (int j = 0; j < h; j++)
    std::copy(data + (size_t)j * stride * bpp, data + (size_t)(j * stride + w) * bpp, t.d.begin() + ((size_t)(y + j) * t.w + x) * bpp);
}

void SoftCanvas::texDestroy(int id) {
  if (id < 1 || id > (int)tex_.size()) return;
  tex_[id - 1] = Tex();
}

void SoftCanvas::texSize(int id, int* w, int* h) {
  if (id < 1 || id > (int)tex_.size()) { *w = *h = 0; return; }
  *w = tex_[id - 1].w; *h = tex_[id - 1].h;
}

void SoftCanvas::quad(int id, Rect dst, Rect src, Col tint, float rad) {
  if (id < 1 || id > (int)tex_.size() || !tex_[id - 1].used) return;
  const Tex& t = tex_[id - 1];
  float s = cs_;
  float dx = dst.x * s + ctx_, dy = dst.y * s + cty_, dw = dst.w * s, dh = dst.h * s;
  int x0, y0, x1, y1;
  if (dw <= 0 || dh <= 0 || !bbox(dx, dy, dx + dw, dy + dh, &x0, &y0, &x1, &y1)) return;
  drawCalls++;
  int bpp = t.f == TEX_RGBA ? 4 : 1;
  float rr = std::fmin(rad * s, std::fmin(dw, dh) * .5f);
  auto texel = [&](int tx, int ty, float* o) {
    tx = std::min(std::max(tx, 0), t.w - 1); ty = std::min(std::max(ty, 0), t.h - 1);
    const uint8_t* p = &t.d[((size_t)ty * t.w + tx) * bpp];
    if (bpp == 4) { o[0] = p[0] / 255.f; o[1] = p[1] / 255.f; o[2] = p[2] / 255.f; o[3] = p[3] / 255.f; }
    else { o[0] = o[1] = o[2] = 0; o[3] = p[0] / 255.f; }
  };
  for (int j = y0; j < y1; j++) for (int i = x0; i < x1; i++) {
    float u = src.x + (i + .5f - dx) / dw * src.w - .5f, v = src.y + (j + .5f - dy) / dh * src.h - .5f;
    int iu = (int)std::floor(u), iv = (int)std::floor(v);
    float fu = u - iu, fv = v - iv, a[4], b[4], c[4], d[4], o[4];
    texel(iu, iv, a); texel(iu + 1, iv, b); texel(iu, iv + 1, c); texel(iu + 1, iv + 1, d);
    for (int k = 0; k < 4; k++) o[k] = (a[k] * (1 - fu) + b[k] * fu) * (1 - fv) + (c[k] * (1 - fu) + d[k] * fu) * fv;
    float r, g, bl, al, cov = 1.f;
    if (rad >= 0) {
      float hx = dw * .5f - rr, hy = dh * .5f - rr;
      float qx = std::fabs(i + .5f - dx - dw * .5f) - hx, qy = std::fabs(j + .5f - dy - dh * .5f) - hy;
      cov = clamp01(.5f - (std::hypot(std::fmax(qx, 0.f), std::fmax(qy, 0.f)) + std::fmin(std::fmax(qx, qy), 0.f) - rr));
      if (cov <= 0) continue;
    }
    if (bpp == 4) {  // premultiplied source * tint (tint.a = opacity)
      r = o[0] * tint.r * tint.a; g = o[1] * tint.g * tint.a; bl = o[2] * tint.b * tint.a; al = o[3] * tint.a;
    } else {
      al = o[3] * tint.a; r = tint.r * al; g = tint.g * al; bl = tint.b * al;
    }
    if (al <= 0) continue;
    cov *= galpha_;
    put(i, j, r * cov, g * cov, bl * cov, al * cov);
  }
}

bool SoftCanvas::savePng(const char* path) const {
  std::vector<uint8_t> o((size_t)pw_ * ph_ * 3);
  for (size_t i = 0; i < (size_t)pw_ * ph_; i++)
    for (int k = 0; k < 3; k++) o[i * 3 + k] = (uint8_t)std::lround(clamp01(fb_[i * 4 + k]) * 255.f);
  return stbi_write_png(path, pw_, ph_, 3, o.data(), pw_ * 3) != 0;
}

}  // namespace hs
