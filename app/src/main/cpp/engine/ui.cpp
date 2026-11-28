#include "ui.h"
#include <algorithm>

namespace hs {

Theme Theme::light() {
  Theme t;
  t.paper = Col(.914f, .898f, .855f); t.paper2 = Col(.953f, .941f, .910f);
  t.ink = Col(.09f, .09f, .102f); t.ink2 = Col(.333f, .333f, .361f);
  t.line = Col(.09f, .09f, .102f, .30f); t.card = Col(.957f, .945f, .914f, .90f); t.veil = Col(.925f, .91f, .867f, .20f);
  t.dark = false;
  return t;
}
Theme Theme::dark_() {
  Theme t;
  t.paper = Col(.063f, .063f, .075f); t.paper2 = Col(.102f, .102f, .122f);
  t.ink = Col(.922f, .906f, .863f); t.ink2 = Col(.651f, .643f, .612f);
  t.line = Col(.922f, .906f, .863f, .30f); t.card = Col(.094f, .094f, .114f, .90f); t.veil = Col(.04f, .04f, .05f, .40f);
  t.dark = true;
  return t;
}

uint32_t Ui::id(const char* s, int i) {
  uint32_t h = 2166136261u;
  for (; *s; s++) { h ^= (unsigned char)*s; h *= 16777619u; }
  return hash32(h + (uint32_t)i * 977u + 1u);
}

Tw& Ui::tw(uint32_t id, float init) {
  auto it = tws.find(id);
  if (it == tws.end()) { Tw t; t.set(init); it = tws.emplace(id, t).first; }
  return it->second;
}

void Ui::touch(int type, float x, float y, double t) {
  if (type == 0) {
    down = true; justDown = true; dx = px = x; dy = py = y; mvx = mvy = velx = vely = 0; claim = capture = 0; lastMoveT = t; cancelled = false;
  } else if (type == 1) {
    if (!down) return;
    mvx += x - px; mvy += y - py;
    double d = t - lastMoveT;
    if (d > 0.002) { velx = .55f * velx + .45f * (float)((x - px) / d); vely = .55f * vely + .45f * (float)((y - py) / d); lastMoveT = t; }
    px = x; py = y;
  } else if (type == 2) {
    if (!down) return;
    down = false; justUp = true; ux = x; uy = y; px = x; py = y; upT = t;
  } else {
    down = false; cancelled = true; justUp = false;
  }
}

void Ui::frameBegin(double t) {
  dt = std::min(0.05, std::max(0.001, t - now));
  if (now == 0) dt = 0.016;
  now = t; busy = false;
}

void Ui::frameEnd() {
  justDown = justUp = cancelled = false;
  mvx = mvy = 0;
  if (!down) { claim = 0; capture = 0; }
}

Rect Ui::hitRect(Rect local) const { return cv->toStage(local).inter(cv->curClipStage()); }

bool Ui::pressing(uint32_t, Rect local) {
  if (blockInput || !down || claim || capture) return false;
  Rect h = hitRect(local);
  return h.has(dx, dy) && h.has(px, py);
}

bool Ui::clicked(uint32_t, Rect local) {
  if (blockInput || !justUp || cancelled || claim || capture) return false;
  Rect h = hitRect(local);
  return h.has(dx, dy) && h.has(ux, uy);
}

std::string Ui::fit(int font, const std::string& s, float size, float maxW) {
  if (fn->width(font, s, size) <= maxW) return s;
  std::string t = s;
  while (!t.empty()) {
    do { t.pop_back(); } while (!t.empty() && (((unsigned char)t.back()) & 0xC0) == 0x80);
    if (fn->width(font, t + "...", size) <= maxW) return t + "...";
  }
  return "";
}

void Ui::card(Rect r, uint32_t seed, bool filled, bool dashed, float bw) {
  cv->rrect(r.x, r.y, r.w, r.h, 2, filled ? th.ink : th.card);
  roughBox(*cv, r, seed, bw, filled ? th.paper : th.ink, dashed);
  if (filled) roughBox(*cv, Rect(r.x - .5f, r.y - .5f, r.w + 1, r.h + 1), seed + 1, 1.0f, th.ink);
}

bool Ui::button(uint32_t id, Rect r, const std::string& label, const BtnStyle& st) {
  bool pr = pressing(id, r), ck = clicked(id, r);
  Tw& t = tw(id);
  t.to(pr ? 1.f : 0.f, now, 70);
  if (t.running(now)) busy = true;
  float k = t.get(now);
  bool filled = st.filled != (k > .5f);
  cv->pushT(r.x + r.w * .5f, r.y + r.h * .5f, 1.f - .03f * k);
  Rect lr(-r.w * .5f, -r.h * .5f, r.w, r.h);
  card(lr, id, filled, st.dashed, st.thick ? 2.6f : 1.6f);
  Col fg = filled ? th.paper : th.ink;
  float sz = st.size;
  float tw_ = label.empty() ? 0 : fn->width(F_BOLD, label, sz);
  float iw = st.iconId >= 0 ? sz + 5 : 0, total = tw_ + iw, x0 = -total * .5f;
  if (st.iconId >= 0) icon(*cv, (Icon)st.iconId, x0, -sz * .5f - 1, sz + 2, fg, 1.7f);
  if (!label.empty()) text(F_BOLD, label, x0 + iw + tw_ * .5f, -sz * .5f - 1, sz, fg, 1);
  cv->popT();
  return ck;
}

bool Ui::chip(uint32_t id, Rect r, const std::string& label, bool on, float size) {
  bool pr = pressing(id, r), ck = clicked(id, r);
  bool filled = on || pr;
  cv->rrect(r.x, r.y, r.w, r.h, 2, filled ? th.ink : th.card);
  roughBox(*cv, r, id, on ? 1.5f : 1.3f, th.ink);
  text(F_BOLD, fit(F_BOLD, label, size, r.w - 10), r.x + r.w * .5f, r.y + r.h * .5f - size * .55f - 1, size, filled ? th.paper : th.ink, 1);
  return ck;
}

bool Ui::toggle(uint32_t id, Rect r, bool* v, bool danger) {
  Rect hit(r.x - 8, r.y - 9, r.w + 16, r.h + 18);
  bool ck = clicked(id, hit);
  if (ck) *v = !*v;
  Tw& t = tw(id, *v ? 1.f : 0.f);
  if (ck || (t.b > .5f) != *v) t.to(*v ? 1.f : 0.f, now, 150);
  if (t.running(now)) busy = true;
  float k = t.get(now), h = r.h, kr = h * .5f - 4.5f;
  Col on = th.ink;
  cv->rrect(r.x, r.y, r.w, r.h, h * .5f, th.card);
  if (k > .02f) cv->rrect(r.x, r.y, r.w, r.h, h * .5f, on.withA(k));
  cv->rrect(r.x, r.y, r.w, r.h, h * .5f, th.ink, danger ? 2.6f : 1.7f);
  float cx = r.x + h * .5f + (r.w - h) * k, cy = r.y + h * .5f;
  Col kc(lerpf(th.ink.r, th.paper.r, k), lerpf(th.ink.g, th.paper.g, k), lerpf(th.ink.b, th.paper.b, k));
  cv->rrect(cx - kr, cy - kr, kr * 2, kr * 2, kr, kc);
  return ck;
}

bool Ui::checkbox(uint32_t id, Rect r, bool* v) {
  Rect hit(r.x - 8, r.y - 8, r.w + 16, r.h + 16);
  bool ck = clicked(id, hit);
  if (ck) *v = !*v;
  cv->rrect(r.x, r.y, r.w, r.h, 2, *v ? th.ink : th.card);
  roughBox(*cv, r, id, 1.5f, th.ink);
  if (*v) icon(*cv, IC_CHECK, r.x + 1, r.y + 1, r.w - 2, th.paper, 2.0f);
  return ck;
}

bool Ui::slider(uint32_t id, Rect r, float* v, float lo, float hi, float step) {
  Rect hit(r.x - 10, r.y - 14, r.w + 20, r.h + 28);
  bool ch = false;
  if (!blockInput && down && !claim && (capture == id || (!capture && hitRect(hit).has(dx, dy)))) {
    capture = id;
    float lx = cv->stageToLocalX(px);
    float t = clampf((lx - r.x) / r.w, 0, 1);
    float nv = lo + t * (hi - lo);
    if (step > 0) nv = lo + std::round((nv - lo) / step) * step;
    nv = clampf(nv, lo, hi);
    if (nv != *v) { *v = nv; ch = true; }
  }
  float t = hi > lo ? (*v - lo) / (hi - lo) : 0, cy = r.y + r.h * .5f, x = r.x + r.w * t;
  cv->line(r.x, cy, r.x + r.w, cy, 2.2f, th.line);
  if (x > r.x + 1) brush(*cv, r.x, cy, x, cy, 4.4f, th.ink, id);
  bool act = capture == id;
  float kr = act ? 9.f : 7.5f;
  cv->rrect(x - kr, cy - kr, kr * 2, kr * 2, kr, th.paper2);
  cv->rrect(x - kr, cy - kr, kr * 2, kr * 2, kr, th.ink, 2.2f);
  cv->rrect(x - 2.2f, cy - 2.2f, 4.4f, 4.4f, 2.2f, th.ink);
  return ch;
}

void Ui::scrollBegin(uint32_t id, Scroll& s, Rect view, bool horiz) {
  Rect hv = hitRect(view);
  float tot = horiz ? px - dx : py - dy, oth = horiz ? py - dy : px - dx, mv = horiz ? mvx : mvy;
  if (justDown && hv.has(dx, dy) && !blockInput) s.vel = 0;
  if (!blockInput && down && !claim && !capture && hv.has(dx, dy) && std::fabs(tot) > 7.f && std::fabs(tot) > std::fabs(oth)) { claim = id; s.drag = true; s.vel = 0; }
  if (claim == id && down) { s.off -= mv; }
  if (claim == id && justUp) {
    s.drag = false;
    float v = horiz ? velx : vely;
    s.vel = (upT - lastMoveT < 0.09) ? -v : 0;
  }
  if (!down && !justUp) s.drag = false;
  if (!s.drag && std::fabs(s.vel) > 8.f) {
    s.off += s.vel * (float)dt; s.vel *= std::exp(-4.2f * (float)dt); busy = true;
  } else if (!s.drag) s.vel = 0;
  if (s.off < 0) { s.off = 0; s.vel = 0; }
  if (s.off > s.max) { s.off = s.max; s.vel = 0; }
  cv->pushClip(view);
  cv->pushT(horiz ? -s.off : 0, horiz ? 0 : -s.off);
}

void Ui::scrollEnd(Scroll& s, Rect view, float len, bool horiz) {
  cv->popT();
  cv->popClip();
  s.max = std::max(0.f, len - (horiz ? view.w : view.h));
  if (s.off > s.max) s.off = s.max;
  if (s.max > 0 && !horiz) {
    float frac = view.h / len, bh = std::max(18.f, view.h * frac), pos = s.max > 0 ? s.off / s.max : 0;
    float y0 = view.y + 3 + (view.h - 6 - bh) * pos;
    cv->line(view.x + view.w - 2.5f, y0, view.x + view.w - 2.5f, y0 + bh, 2.2f, th.ink2.withA(.55f));
  }
}

}  // namespace hs
