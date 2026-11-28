#include "ink.h"
#include <algorithm>

namespace hs {

static const float PI = 3.14159265f;

void roughBox(Canvas& cv, Rect r, uint32_t seed, float w, Col c, bool dashed, float amp) {
  if (r.w < 4 || r.h < 4) return;
  const float step = 26.f;
  int nx = std::max(1, (int)std::lround(r.w / step)), ny = std::max(1, (int)std::lround(r.h / step));
  std::vector<std::pair<float, float>> pts;
  pts.reserve((nx + ny) * 2 + 1);
  uint32_t k = 0;
  auto j = [&]() { return (rnd(seed, k++) - .5f) * 2.f * amp; };
  for (int i = 0; i < nx; i++) pts.push_back({r.x + r.w * i / nx, r.y + j()});
  for (int i = 0; i < ny; i++) pts.push_back({r.x + r.w + j(), r.y + r.h * i / ny});
  for (int i = 0; i < nx; i++) pts.push_back({r.x + r.w - r.w * i / nx, r.y + r.h + j()});
  for (int i = 0; i < ny; i++) pts.push_back({r.x + j(), r.y + r.h - r.h * i / ny});
  size_t n = pts.size();
  for (size_t i = 0; i < n; i++) {
    auto a = pts[i], b = pts[(i + 1) % n];
    if (dashed) {
      for (int d = 0; d < 3; d++) {
        float t0 = d / 3.f + .04f, t1 = (d + 1) / 3.f - .1f;
        cv.line(lerpf(a.first, b.first, t0), lerpf(a.second, b.second, t0), lerpf(a.first, b.first, t1), lerpf(a.second, b.second, t1), w, c);
      }
    } else cv.line(a.first, a.second, b.first, b.second, w, c);
  }
}

void brush(Canvas& cv, float x0, float y0, float x1, float y1, float w, Col c, uint32_t seed) {
  float len = std::hypot(x1 - x0, y1 - y0);
  int n = std::max(2, (int)(len / 9.f));
  float px = x0, py = y0;
  for (int i = 1; i <= n; i++) {
    float t = (float)i / n;
    float taper = std::min(1.f, std::min(t, 1.f - t) * 5.f + .25f);
    float wob = .75f + .25f * rnd(seed, i);
    float x = lerpf(x0, x1, t), y = lerpf(y0, y1, t) + (rnd(seed, i + 99) - .5f) * 1.2f;
    cv.line(px, py, x, y, w * taper * wob, c);
    px = x; py = y;
  }
}

void enso(Canvas& cv, float cx, float cy, float r, float w, Col c, float from, float to, uint32_t seed) {
  int n = std::max(8, (int)((to - from) * 56));
  float px = 0, py = 0;
  for (int i = 0; i <= n; i++) {
    float t = from + (to - from) * i / n;
    float a = (t - .25f) * 2 * PI;
    float rr = r + (rnd(seed, i) - .5f) * .7f + 1.2f * std::sin(t * 2 * PI + 1.3f);
    float x = cx + std::cos(a) * rr, y = cy + std::sin(a) * rr;
    float u = (float)i / n, taper = .55f + .45f * std::sin(u * PI * .9f + .15f) ;
    if (i) cv.line(px, py, x, y, w * (.6f + .4f * (1 - u)) * taper * 1.25f, c);
    px = x; py = y;
  }
}

int makeGrainTile(Canvas& cv, int tile) {
  std::vector<uint8_t> d((size_t)tile * tile);
  for (int y = 0; y < tile; y++) for (int x = 0; x < tile; x++) {
    float v = rnd(7, y * tile + x) * .6f + rnd(13, (y / 3) * tile + x / 3) * .4f;
    d[(size_t)y * tile + x] = (uint8_t)(v * 255.f);
  }
  return cv.texCreate(tile, tile, TEX_A8, d.data());
}

void grain(Canvas& cv, int tex, int tile, Rect a, Col c) {
  for (float y = a.y; y < a.y + a.h; y += tile) for (float x = a.x; x < a.x + a.w; x += tile) {
    float w = std::min((float)tile, a.x + a.w - x), h = std::min((float)tile, a.y + a.h - y);
    cv.quad(tex, Rect(x, y, w, h), Rect(0, 0, w, h), c);
  }
}

// ---- icons: 24 grid ----
static void poly(Canvas& cv, float X, float Y, float k, const float* p, int n, float sw, Col c, bool close = false) {
  for (int i = 0; i + 1 < n; i++) cv.line(X + p[i * 2] * k, Y + p[i * 2 + 1] * k, X + p[i * 2 + 2] * k, Y + p[i * 2 + 3] * k, sw, c);
  if (close && n > 2) cv.line(X + p[(n - 1) * 2] * k, Y + p[(n - 1) * 2 + 1] * k, X + p[0] * k, Y + p[1] * k, sw, c);
}
static void arc(Canvas& cv, float X, float Y, float k, float cx, float cy, float r, float a0, float a1, float sw, Col c) {
  int n = std::max(6, (int)(std::fabs(a1 - a0) / 18.f));
  float px = 0, py = 0;
  for (int i = 0; i <= n; i++) {
    float a = (a0 + (a1 - a0) * i / n) * PI / 180.f;
    float x = X + (cx + std::cos(a) * r) * k, y = Y + (cy + std::sin(a) * r) * k;
    if (i) cv.line(px, py, x, y, sw, c);
    px = x; py = y;
  }
}
static void dot(Canvas& cv, float X, float Y, float k, float cx, float cy, float r, Col c) {
  cv.rrect(X + (cx - r) * k, Y + (cy - r) * k, r * 2 * k, r * 2 * k, r * k, c);
}

void icon(Canvas& cv, Icon id, float X, float Y, float size, Col c, float sw) {
  float k = size / 24.f;
  switch (id) {
    case IC_MODE:
      arc(cv, X, Y, k, 12, 12, 8, -60, 240, sw, c);
      dot(cv, X, Y, k, 12, 12, 2.3f, c);
      break;
    case IC_GAME: {
      cv.rrect(X + 2.5f * k, Y + 7 * k, 19 * k, 11 * k, 5.5f * k, c, sw);
      const float h[] = {7, 12.5f, 11, 12.5f}, v[] = {9, 10.5f, 9, 14.5f};
      cv.line(X + h[0] * k, Y + h[1] * k, X + h[2] * k, Y + h[3] * k, sw, c);
      cv.line(X + v[0] * k, Y + v[1] * k, X + v[2] * k, Y + v[3] * k, sw, c);
      dot(cv, X, Y, k, 15.5f, 11.5f, 1.1f, c); dot(cv, X, Y, k, 18, 13.8f, 1.1f, c);
      break;
    }
    case IC_SETTING: {
      for (int i = 0; i < 3; i++) {
        float y = 6.5f + i * 5.5f, kx = i == 0 ? 9.f : (i == 1 ? 15.f : 8.f);
        cv.line(X + 3.5f * k, Y + y * k, X + (kx - 2.4f) * k, Y + y * k, sw, c);
        cv.line(X + (kx + 2.4f) * k, Y + y * k, X + 20.5f * k, Y + y * k, sw, c);
        arc(cv, X, Y, k, kx, y, 2.2f, 0, 360, sw, c);
      }
      break;
    }
    case IC_PLAY: {
      for (float y = 5; y <= 19; y += .7f) {
        float t = std::fabs(y - 12) / 7.f, x1 = 19 - 11 * t;
        cv.line(X + 8 * k, Y + y * k, X + x1 * k, Y + y * k, 1.1f * k, c);
      }
      break;
    }
    case IC_GEAR:
      arc(cv, X, Y, k, 12, 12, 4, 0, 360, sw, c);
      for (int i = 0; i < 8; i++) {
        float a = i * PI / 4;
        cv.line(X + (12 + std::cos(a) * 6.8f) * k, Y + (12 + std::sin(a) * 6.8f) * k, X + (12 + std::cos(a) * 9.3f) * k, Y + (12 + std::sin(a) * 9.3f) * k, sw + .3f, c);
      }
      break;
    case IC_PLUS:
      cv.line(X + 12 * k, Y + 5 * k, X + 12 * k, Y + 19 * k, sw, c);
      cv.line(X + 5 * k, Y + 12 * k, X + 19 * k, Y + 12 * k, sw, c);
      break;
    case IC_CHEV_R: { const float p[] = {9, 5, 16, 12, 9, 19}; poly(cv, X, Y, k, p, 3, sw, c); break; }
    case IC_CHEV_D: { const float p[] = {5, 9, 12, 16, 19, 9}; poly(cv, X, Y, k, p, 3, sw, c); break; }
    case IC_CHECK: { const float p[] = {4.5f, 12.5f, 10, 18, 19.5f, 6.5f}; poly(cv, X, Y, k, p, 3, sw + .3f, c); break; }
    case IC_REC:
      arc(cv, X, Y, k, 12, 12, 8.5f, 0, 360, sw, c);
      dot(cv, X, Y, k, 12, 12, 4.2f, c);
      break;
    case IC_FPS: { const float p[] = {3, 15, 8, 15, 11, 6, 14, 19, 17, 11, 21, 11}; poly(cv, X, Y, k, p, 6, sw, c); break; }
    case IC_RAM:
      cv.rrect(X + 3 * k, Y + 7 * k, 18 * k, 10 * k, 2 * k, c, sw);
      for (int i = 0; i < 4; i++) cv.line(X + (7 + i * 3.4f) * k, Y + 17 * k, X + (7 + i * 3.4f) * k, Y + 20.5f * k, sw, c);
      cv.line(X + 7 * k, Y + 12 * k, X + 17 * k, Y + 12 * k, sw * .8f, c);
      break;
    case IC_LOCK:
      cv.rrect(X + 5 * k, Y + 11 * k, 14 * k, 9.5f * k, 2.2f * k, c, sw);
      arc(cv, X, Y, k, 12, 11, 4.2f, 180, 360, sw, c);
      cv.line(X + 7.8f * k, Y + 11 * k, X + 7.8f * k, Y + 8.5f * k, sw, c);
      cv.line(X + 16.2f * k, Y + 11 * k, X + 16.2f * k, Y + 8.5f * k, sw, c);
      break;
    case IC_STAR: {
      float p[12];
      for (int i = 0; i < 6; i++) {
        int m = (i * 2) % 5; float a = -PI / 2 + m * 2 * PI / 5;
        p[i * 2] = 12 + std::cos(a) * 9; p[i * 2 + 1] = 12.5f + std::sin(a) * 9;
      }
      poly(cv, X, Y, k, p, 6, sw, c);
      break;
    }
    case IC_TOOL: {
      cv.line(X + 5 * k, Y + 19 * k, X + 14 * k, Y + 10 * k, sw + .8f, c);
      arc(cv, X, Y, k, 16.5f, 7.5f, 4.2f, 20, 330, sw, c);
      break;
    }
    case IC_INFO:
      arc(cv, X, Y, k, 12, 12, 9, 0, 360, sw, c);
      cv.line(X + 12 * k, Y + 11 * k, X + 12 * k, Y + 17 * k, sw, c);
      dot(cv, X, Y, k, 12, 7.6f, 1.2f, c);
      break;
    case IC_SUHSIN:
      arc(cv, X, Y, k, 12, 12, 9, 0, 360, sw, c);
      dot(cv, X, Y, k, 12, 12, 4.6f, c);
      break;
    case IC_CLOSE: {
      cv.line(X + 6 * k, Y + 6 * k, X + 18 * k, Y + 18 * k, sw, c);
      cv.line(X + 18 * k, Y + 6 * k, X + 6 * k, Y + 18 * k, sw, c);
      break;
    }
    case IC_GLOBE:
      arc(cv, X, Y, k, 12, 12, 9, 0, 360, sw, c);
      arc(cv, X, Y, k, 12, 12, 4, 0, 360, sw * .8f, c);
      cv.line(X + 3 * k, Y + 12 * k, X + 21 * k, Y + 12 * k, sw * .8f, c);
      break;
    case IC_DEX: {
      cv.rrect(X + 4 * k, Y + 4 * k, 16 * k, 16 * k, 3 * k, c, sw);
      const float p[] = {8, 12, 11, 15, 16, 9}; poly(cv, X, Y, k, p, 3, sw, c);
      break;
    }
    case IC_TEMP:
      cv.line(X + 12 * k, Y + 4.5f * k, X + 12 * k, Y + 15 * k, sw + 3.2f * k, c.withA(.0f));
      cv.rrect(X + 9.4f * k, Y + 3 * k, 5.2f * k, 12 * k, 2.6f * k, c, sw);
      arc(cv, X, Y, k, 12, 17.2f, 3.6f, 0, 360, sw, c);
      dot(cv, X, Y, k, 12, 17.2f, 1.9f, c);
      cv.line(X + 12 * k, Y + 8 * k, X + 12 * k, Y + 16 * k, sw, c);
      break;
    default: break;
  }
}

static float easeInOut(float t) { return t < .5f ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t); }

bool inkSweep(Canvas& cv, Rect st, float p, Col ink, uint32_t seed) {
  const int bands = 10;
  float bh = st.h / bands, W = st.w + 80;
  bool cover = p >= .46f && p <= .54f;
  for (int i = 0; i < bands; i++) {
    float delay = rnd(seed, i) * .22f;
    float tc = clampf((p * 2 - delay) / (1 - .22f), 0, 1);          // cover 0..0.5
    float tr = clampf(((p - .5f) * 2 - delay) / (1 - .22f), 0, 1);  // reveal 0.5..1
    float front = easeInOut(tc) * W, tail = easeInOut(tr) * W;
    float rag = (rnd(seed, i + 50) - .5f) * 30;
    float y = st.y + bh * (i + .5f);
    float x0 = st.x - 40 + tail + (tr > 0 ? rag : 0), x1 = st.x - 40 + front + rag;
    if (x1 - x0 > 2) brush(cv, x0, y, x1, y + (rnd(seed, i + 9) - .5f) * 6, bh * 1.7f, ink, seed + i);
  }
  return cover;
}

void inkWash(Canvas& cv, Rect st, float cx, float cy, float p, Col ink) {
  float maxR = std::hypot(std::fmax(cx - st.x, st.x + st.w - cx), std::fmax(cy - st.y, st.y + st.h - cy)) + 8;
  float r = maxR * easeInOut(clampf(p, 0, 1));
  if (r < 1) return;
  cv.pushClip(st);
  cv.rrect(cx - r, cy - r, r * 2, r * 2, r, ink);
  cv.popClip();
}

}  // namespace hs
