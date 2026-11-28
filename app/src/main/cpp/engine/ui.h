// Immediate-mode UI toolkit in ink style. One instance, driven once per frame.
#pragma once
#include "font.h"
#include "ink.h"
#include <unordered_map>
#include <functional>

namespace hs {

struct Theme {
  Col paper, paper2, ink, ink2, line, card, veil;
  bool dark = false;
  static Theme light();
  static Theme dark_();
};

inline float easeOut(float t) { t = 1 - t; return 1 - t * t * t; }
inline float easeIO(float t) { return t < .5f ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t); }

struct Ui;

// A value that moves to a target over time.
struct Tw {
  float a = 0, b = 0;
  double t0 = 0, d = 0;
  bool init = false;
  void set(float v) { a = b = v; d = 0; init = true; }
  void to(float v, double now, double dur) {
    if (!init) { set(v); return; }
    if (v == b) return;
    a = get(now); b = v; t0 = now; d = dur * 0.001;  // dur in ms; clock in seconds
  }
  float get(double now) const {
    if (d <= 0 || now >= t0 + d) return b;
    return a + (b - a) * easeOut((float)((now - t0) / d));
  }
  bool running(double now) const { return d > 0 && now < t0 + d; }
};

struct Scroll {
  float off = 0, vel = 0, max = 0;
  bool drag = false;
};

enum { F_DISP = 0, F_BODY = 1, F_BOLD = 2 };

struct BtnStyle {
  bool filled = false;      // ink background
  bool dashed = false;
  int iconId = -1;          // Icon or -1
  float size = 13;
  bool thick = false;
};

struct Ui {
  Canvas* cv = nullptr;
  Fonts* fn = nullptr;
  Theme th = Theme::light();
  double now = 0, dt = 0.016;
  bool busy = false;  // some animation still running -> render next frame
  bool blockInput = false;  // true while drawing layers under a modal

  // ---- pointer (stage coords) ----
  bool down = false, justDown = false, justUp = false, cancelled = false;
  float px = 0, py = 0, dx = 0, dy = 0, ux = 0, uy = 0;
  float mvx = 0, mvy = 0, velx = 0, vely = 0;
  uint32_t claim = 0, capture = 0;
  double lastMoveT = 0, upT = 0;
  void touch(int type, float x, float y, double t);  // 0 down 1 move 2 up 3 cancel
  void frameBegin(double t);
  void frameEnd();

  // ---- state helpers ----
  Tw& tw(uint32_t id, float init = 0);
  std::unordered_map<uint32_t, Tw> tws;
  static uint32_t id(const char* s, int i = 0);

  // ---- drawing ----
  void text(int font, const std::string& s, float x, float y, float size, Col c, int align = 0, float spacing = 0) { fn->draw(*cv, font, s, x, y, size, c, align, spacing); }
  float tw_(int font, const std::string& s, float size) { return fn->width(font, s, size); }
  // Fits text into maxW by trimming with an ellipsis.
  std::string fit(int font, const std::string& s, float size, float maxW);
  void rule(float x0, float y0, float x1, float y1) { cv->line(x0, y0, x1, y1, 1.f, th.line); }
  void card(Rect r, uint32_t seed, bool filled = false, bool dashed = false, float bw = 1.6f);

  // ---- hit ----
  Rect hitRect(Rect local) const;  // visible stage rect of a local rect
  bool pressing(uint32_t id, Rect local);  // finger down on it (not claimed by a scroller)
  bool clicked(uint32_t id, Rect local);   // released on it as a tap

  // ---- widgets ----
  bool button(uint32_t id, Rect r, const std::string& label, const BtnStyle& st = BtnStyle());
  bool chip(uint32_t id, Rect r, const std::string& label, bool on, float size = 12.5f);
  bool toggle(uint32_t id, Rect r, bool* v, bool danger = false);
  // v in [lo,hi]; returns true when changed.
  bool slider(uint32_t id, Rect r, float* v, float lo, float hi, float step);
  bool checkbox(uint32_t id, Rect r, bool* v);

  // ---- scroll area ----
  void scrollBegin(uint32_t id, Scroll& s, Rect view, bool horiz = false);
  void scrollEnd(Scroll& s, Rect view, float contentLen, bool horiz = false);
};

}  // namespace hs
