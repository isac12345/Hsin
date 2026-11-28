#include "app.h"
#include <algorithm>
#include <cstdio>

namespace hs {

static const Col kDeep(.051f, .051f, .063f), kBone(.922f, .906f, .863f);

App::App(Canvas* cv, Fonts* fn) : cv_(cv), fn_(fn) {
  ui.cv = cv; ui.fn = fn;
  m.set("mode", "hsin"); m.set("beban", "1"); m.set("pref.anim", "1");
}

void App::setImage(int slot, int w, int h, const uint8_t* rgba) {
  if (slot < 0 || slot >= IMG_COUNT) return;
  if (img_[slot].tex) cv_->texDestroy(img_[slot].tex);
  img_[slot].tex = cv_->texCreate(w, h, TEX_RGBA, rgba);
  img_[slot].w = w; img_[slot].h = h;
}

void App::applyTheme() {
  std::string t = m.str("pref.theme", "system");
  bool dark = t == "dark" || (t != "light" && sysDark_);
  ui.th = dark ? Theme::dark_() : Theme::light();
}

int App::wantFrame() const { return wantAnim_ ? 2 : (wantAmbient_ ? 1 : 0); }

bool App::back() {
  if (launch_.on) return true;
  if (sheetKind_ != SH_NONE && !sheetClosing_) { closeSheet(); return true; }
  return false;
}

void App::touch(int type, float x, float y, double t) {
  ui.touch(type, x / scale_, y / scale_, t);
}

void App::gotoTab(int t, int sub) {
  if (sub >= 0) { sub_ = subShown_ = sub; setScroll_ = Scroll(); }
  if (t == tab) return;
  if (sheetKind_ != SH_NONE) closeSheet();
  if (!animOn()) { tab = t; return; }
  tabTarget_ = t; sweepT0_ = ui.now; sweepSwapped_ = false;
}

void App::gotoSub(int s) {
  if (s == sub_) return;
  sub_ = s; subT0_ = ui.now;
  if (!animOn()) { subShown_ = s; setScroll_ = Scroll(); subT0_ = -10; }
}

// ------------------------------------------------------------------ frame
void App::frame(double t, int pw, int ph) {
  applyTheme();
  cv_->begin(pw, ph, ui.th.paper);
  scale_ = ph / 360.f;
  SW = pw / scale_;
  if (SW < 640) { scale_ = pw / 640.f; SW = 640; }
  SH = ph / scale_;
  cv_->setBase(0, 0, scale_);
  float iL = insL_ / scale_, iR = insR_ / scale_;
  L0 = 76 + iL; CL = L0 + 22; CR = SW - 16 - iR;
  ui.frameBegin(t);
  frameNo_++;
  fn_->frameStart();
  if (!grainTex_) grainTex_ = makeGrainTile(*cv_, 128);
  if (tab == 0) { std::string md = m.str("mode", "hsin"); if (md != prevMode_) { prevMode_ = md; } }

  bool sweeping = ui.now - sweepT0_ < .54;
  if (!sweepSwapped_ && ui.now - sweepT0_ >= .27) { tab = tabTarget_; sweepSwapped_ = true; }
  bool modal = sheetKind_ != SH_NONE || launch_.on;
  ui.blockInput = modal || sweeping;

  cv_->pushClip(Rect(L0, 0, SW - L0, SH));
  if (tab == 0) drawMode(); else if (tab == 1) drawGame(); else drawSetting();
  if (sweeping) {
    float p = (float)((ui.now - sweepT0_) / .54);
    inkSweep(*cv_, Rect(L0, 0, SW - L0, SH), p, ui.th.ink, 11);
    ui.busy = true;
  }
  cv_->popClip();
  ui.blockInput = modal;
  drawRail();
  ui.blockInput = false;
  drawSheet();
  drawLaunch();
  drawToast();
  ui.frameEnd();
  cv_->end();
  wantAnim_ = ui.busy;
  wantAmbient_ = animOn() && (tab != 2 || true);
}

// ------------------------------------------------------------------ chrome
void App::drawBg(int slot, Rect a) {
  Img& im = img_[slot];
  cv_->rrect(a.x, a.y, a.w, a.h, 0, ui.th.paper);
  if (im.tex) {
    float dx = 0, dy = 0;
    if (animOn()) { dx = std::sin((float)ui.now / 9.f * 6.2832f) * 9.f; dy = std::cos((float)ui.now / 11.f * 6.2832f) * 5.f; }
    float mg = 12;
    Rect d(a.x - mg + dx, a.y - mg + dy, a.w + mg * 2, a.h + mg * 2);
    // cover fit
    float sc = std::max(d.w / im.w, d.h / im.h), sw = d.w / sc, sh = d.h / sc;
    Rect src((im.w - sw) * .5f, (im.h - sh) * .5f, sw, sh);
    cv_->pushClip(a);
    cv_->quad(im.tex, d, src, Col(1, 1, 1, ui.th.dark ? .72f : 1.f));
    cv_->popClip();
  }
  cv_->rrect(a.x, a.y, a.w, a.h, 0, ui.th.veil);
  grain(*cv_, grainTex_, 128, a, ui.th.ink.withA(ui.th.dark ? .05f : .03f));
}

void App::drawRail() {
  float iL = insL_ / scale_, cx = iL + 38;
  cv_->rrect(0, 0, L0, SH, 0, ui.th.paper2);
  brush(*cv_, L0 - 1, -4, L0 - 1, SH + 4, 3.2f, ui.th.ink.withA(.85f), 5);
  // logo: open circle (enso)
  enso(*cv_, cx, 34, 17, 3.4f, ui.th.ink, 0, .9f, 21);
  cv_->rrect(cx - 4.5f, 34 - 4.5f, 9, 9, 4.5f, ui.th.ink);
  const char* names[3] = {L(m, "Mode", "Mode"), L(m, "Game", "Game"), L(m, "Setting", "Settings")};
  Icon ics[3] = {IC_MODE, IC_GAME, IC_SETTING};
  for (int i = 0; i < 3; i++) {
    float y = 68 + i * 74;
    Rect hit(iL, y, 76, 68);
    bool on = tab == i && sweepSwapped_ ? true : (!sweepSwapped_ && tabTarget_ == i);
    Tw& t = ui.tw(Ui::id("tab", i), on ? 1.f : 0.f);
    t.to(on ? 1.f : 0.f, ui.now, 220);
    if (t.running(ui.now)) ui.busy = true;
    float k = t.get(ui.now);
    Col c(lerpf(ui.th.ink2.r, ui.th.ink.r, k), lerpf(ui.th.ink2.g, ui.th.ink.g, k), lerpf(ui.th.ink2.b, ui.th.ink.b, k));
    if (k > .02f) brush(*cv_, iL + 3, y + 8, iL + 3, y + 8 + 52 * k, 5.f, ui.th.ink, 30 + i);
    bool pr = ui.pressing(Ui::id("tab", i), hit);
    icon(*cv_, ics[i], cx - 13.5f, y + 8 + (pr ? 1.f : 0.f), 27, c, 1.9f);
    ui.text(F_BOLD, names[i], cx, y + 40, 11.5f, c, 1);
    if (ui.clicked(Ui::id("tab", i), hit)) gotoTab(i);
  }
}

void App::drawHeader(const char* title, float* outW) {
  float tw = ui.tw_(F_DISP, title, 26) + 36;
  Rect r(CL, 14, tw, 40);
  cv_->rrect(r.x, r.y, r.w, r.h, 2, ui.th.paper2);
  roughBox(*cv_, r, 77, 1.8f, ui.th.ink);
  ui.text(F_DISP, title, r.x + tw * .5f, r.y + 5, 26, ui.th.ink, 1);
  if (outW) *outW = tw;
  // avatar + fps badge
  bool su = m.str("mode", "hsin") == "suhsin";
  int slot = su ? IMG_AVS : IMG_AV0 + std::min(3, std::max(0, m.num("beban", 1)));
  float d = 56, ax = CR - d, ay = 10;
  cv_->rrect(ax - 4, ay - 4, d + 8, d + 8, (d + 8) * .5f, ui.th.paper2);
  if (img_[slot].tex) cv_->quad(img_[slot].tex, Rect(ax, ay, d, d), Rect(0, 0, (float)img_[slot].w, (float)img_[slot].h), Col(1, 1, 1, 1), d * .5f);
  cv_->rrect(ax - 4, ay - 4, d + 8, d + 8, (d + 8) * .5f, ui.th.ink, 2.2f);
  enso(*cv_, ax + d * .5f, ay + d * .5f, d * .5f + 7, 2.2f, ui.th.ink.withA(.8f), 0.02f, .82f, 9);
  int fps = m.num("fps", 0);
  if (fps > 0) {
    std::string fs = std::to_string(fps) + " FPS";
    float bw = ui.tw_(F_BOLD, fs, 12.5f) + 18;
    Rect b(ax - 12 - bw, ay + 17, bw, 22);
    cv_->rrect(b.x, b.y, b.w, b.h, 2, ui.th.ink);
    ui.text(F_BOLD, fs, b.x + b.w * .5f, b.y + 3, 12.5f, ui.th.paper, 1);
  }
}

void App::drawToast() {
  if (m.toastNew) { m.toastNew = false; toastT0_ = ui.now; toastShow_ = m.toastMsg; toastBad_ = m.toastBad; }
  double life = toastBad_ ? 4.0 : 2.5, e = ui.now - toastT0_;
  if (toastShow_.empty() || e > life) return;
  ui.busy = true;
  float a = e < .18 ? (float)(e / .18) : (e > life - .3 ? (float)((life - e) / .3) : 1.f);
  float w = std::min(SW - L0 - 40, ui.tw_(F_BOLD, toastShow_, 13.5f) + 34), h = 34;
  float x = L0 + (SW - L0 - w) * .5f, y = SH - 46 + (1 - a) * 10;
  cv_->setAlpha(a);
  cv_->rrect(x, y, w, h, 2, kDeep);
  roughBox(*cv_, Rect(x, y, w, h), 99, toastBad_ ? 2.4f : 1.4f, kBone, toastBad_);
  ui.text(F_BOLD, ui.fit(F_BOLD, toastShow_, 13.5f, w - 24), x + w * .5f, y + 8, 13.5f, kBone, 1);
  cv_->setAlpha(1);
}

// ------------------------------------------------------------------ Mode
void App::drawMode() {
  drawBg(IMG_BG_MODE, Rect(L0, 0, SW - L0, SH));
  drawHeader(L(m, "Mode", "Mode"));
  bool su = m.str("mode", "hsin") == "suhsin";
  int beban = std::min(3, std::max(0, m.num("beban", 1)));
  float gap = 14, cw = (CR - CL - gap) * .5f, y = 66, h = 146;
  for (int i = 0; i < 2; i++) {
    Rect r(CL + i * (cw + gap), y, cw, h);
    bool active = (i == 1) == su;
    uint32_t id = Ui::id("mode", i);
    Tw& a = ui.tw(id, active ? 1.f : 0.f);
    a.to(active ? 1.f : 0.f, ui.now, animOn() ? 520 : 1);
    if (a.running(ui.now)) ui.busy = true;
    float k = a.get(ui.now);
    bool pr = ui.pressing(id, r);
    cv_->pushT(r.x + r.w * .5f, r.y + r.h * .5f, pr ? .985f : 1.f);
    Rect lr(-r.w * .5f, -r.h * .5f, r.w, r.h);
    cv_->rrect(lr.x, lr.y, lr.w, lr.h, 2, ui.th.card);
    float wx = modeWashX_[i] - r.x + lr.x, wy = modeWashY_[i] - r.y + lr.y;
    if (modeWashX_[i] == 0) { wx = lr.x + lr.w * .5f; wy = lr.y + lr.h * .5f; }
    if (k > .001f) inkWash(*cv_, lr, wx, wy, k, ui.th.ink);
    roughBox(*cv_, lr, 40 + i, i == 1 ? 2.2f : 1.8f, ui.th.ink);
    Col fg(lerpf(ui.th.ink.r, ui.th.paper.r, k > .5f ? 1.f : 0.f), lerpf(ui.th.ink.g, ui.th.paper.g, k > .5f ? 1.f : 0.f), lerpf(ui.th.ink.b, ui.th.paper.b, k > .5f ? 1.f : 0.f));
    Col fg2 = fg.withA(.78f);
    ui.text(F_DISP, i == 0 ? "Hsin" : "Suhsin", lr.x + 18, lr.y + 10, 40, fg);
    ui.text(F_BODY, i == 0 ? L(m, "Beban diatur otomatis", "Load adjusts automatically") : L(m, "Semua diatur manual", "Everything set by hand"), lr.x + 18, lr.y + 60, 13, fg2);
    // avatar
    int slot = i == 0 ? IMG_AV0 + beban : IMG_AVS;
    float d = i == 0 ? 92.f : 100.f, ax = lr.x + lr.w - d - 20, ay = lr.y + (lr.h - d) * .5f - 6;
    if (img_[slot].tex) cv_->quad(img_[slot].tex, Rect(ax, ay, d, d), Rect(0, 0, (float)img_[slot].w, (float)img_[slot].h), Col(1, 1, 1, 1), d * .5f);
    cv_->rrect(ax - 1, ay - 1, d + 2, d + 2, d * .5f + 1, fg, i == 1 ? 3.6f : 2.4f);
    enso(*cv_, ax + d * .5f, ay + d * .5f, d * .5f + 8, 2.6f, fg.withA(.6f), .05f, .8f, 7 + i);
    // bottom-left
    float by = lr.y + lr.h - 38;
    if (i == 0) {
      for (int b = 0; b < 4; b++) {
        float cx = lr.x + 26 + b * 22, cyy = by + 15;
        cv_->rrect(cx - 7, cyy - 7, 14, 14, 7, fg, 1.8f);
        if (b <= beban && active) cv_->rrect(cx - 4, cyy - 4, 8, 8, 4, fg);
      }
      ui.text(F_BOLD, active ? std::string(L(m, "Beban ", "Load ")) + std::to_string(beban) : L(m, "Siaga", "Standby"), lr.x + 26 + 4 * 22 + 4, by + 6, 13, fg);
    }
    if (active) {
      Rect st(lr.x + lr.w - 66, lr.y + lr.h - 32, 52, 21);
      roughBox(*cv_, st, 61 + i, 1.8f, fg);
      ui.text(F_BOLD, L(m, "AKTIF", "ACTIVE"), st.x + st.w * .5f, st.y + 4.2f, 10.5f, fg, 1, 1.2f);
    }
    cv_->popT();
    if (ui.clicked(id, r) && !active) {
      modeWashX_[i] = ui.ux; modeWashY_[i] = ui.uy;
      m.set("mode", i == 1 ? "suhsin" : "hsin");
      m.cmd("mode", i == 1 ? "suhsin" : "hsin");
    }
  }
  // thermal switch lives on Suhsin card (drawn on top so taps do not select the card)
  {
    Rect r(CL + cw + gap, y, cw, h);
    bool supported = m.cap("thermaloff", false);
    bool on = m.flag("f.thermaloff", false);
    float k = ui.tw(Ui::id("mode", 1)).get(ui.now);
    Col fg = k > .5f ? ui.th.paper : ui.th.ink;
    float tx = r.x + 18, ty = r.y + r.h - 38;
    ui.text(F_BOLD, L(m, "Matikan thermal", "Disable thermal"), tx, ty + 6, 13, fg.withA(supported ? 1.f : .5f));
    Rect tg(tx + ui.tw_(F_BOLD, L(m, "Matikan thermal", "Disable thermal"), 13) + 12, ty + 2, 42, 22);
    if (supported && su) {
      bool v = on;
      uint32_t tid = Ui::id("modeThermal");
      cv_->pushT(0, 0);
      if (ui.toggle(tid, tg, &v, true)) { m.set("f.thermaloff", v ? "1" : "0"); m.cmd("feat", "thermaloff", v ? "1" : "0"); }
      cv_->popT();
    } else {
      cv_->setAlpha(.45f);
      bool v = false; ui.blockInput = true; ui.toggle(Ui::id("modeThermalX"), tg, &v, true); ui.blockInput = false;
      cv_->setAlpha(1);
    }
  }
  // quick tiles
  struct Tile { Icon ic; std::string name, sub; int act; };
  std::string last = m.str("lastgame.label");
  int fps = m.num("fps", 0);
  int ram = m.num("ram.free", 0);
  char buf[48];
  std::string ramS = ram > 0 ? (std::snprintf(buf, sizeof buf, "%.1f GB %s", ram / 1024.0, L(m, "bebas", "free")), std::string(buf)) : std::string(L(m, "Tutup app latar", "Close background apps"));
  std::string tempS = m.num("temp", 0) > 0 ? std::to_string(m.num("temp")) + " \xC2\xB0" "C" : "--";
  Tile tiles[4] = {
    {IC_PLAY, L(m, "Lanjut", "Resume"), last.empty() ? L(m, "Belum ada game", "No game yet") : last, 0},
    {IC_FPS, "FPS", fps > 0 ? std::to_string(fps) + " " + L(m, "sekarang", "now") : L(m, "Belum ada game", "No game yet"), 1},
    {IC_RAM, L(m, "Bersihkan RAM", "Clean RAM"), ramS, 2},
    {IC_TEMP, L(m, "Suhu", "Temperature"), tempS, 3}};
  float tg = 10, tw = (CR - CL - tg * 3) / 4, ty = 226, th = 76;
  for (int i = 0; i < 4; i++) {
    Rect r(CL + i * (tw + tg), ty, tw, th);
    uint32_t id = Ui::id("tile", i);
    bool pr = ui.pressing(id, r);
    cv_->rrect(r.x, r.y, r.w, r.h, 2, pr ? ui.th.ink : ui.th.card);
    roughBox(*cv_, r, 70 + i, 1.6f, ui.th.ink);
    Col fg = pr ? ui.th.paper : ui.th.ink;
    icon(*cv_, tiles[i].ic, r.x + 11, r.y + 9, 22, fg, 1.8f);
    ui.text(F_BOLD, ui.fit(F_BOLD, tiles[i].name, 13.5f, r.w - 20), r.x + 11, r.y + 34, 13.5f, fg);
    ui.text(F_BODY, ui.fit(F_BODY, tiles[i].sub, 11.5f, r.w - 20), r.x + 11, r.y + 54, 11.5f, fg.withA(.78f));
    if (ui.clicked(id, r)) {
      if (i == 0) {
        std::string pk = m.str("lastgame.pkg");
        GameInfo* g = pk.empty() ? nullptr : m.game(pk);
        if (g) startLaunch(*g, ui.ux, ui.uy); else m.toast(L(m, "Belum ada game terakhir", "No last game yet"), true);
      } else if (i == 1) gotoTab(2, 2);
      else if (i == 2) { m.cmd("act", "ram"); }
      else gotoTab(2, 3);
    }
  }
  std::string note = su ? L(m, "Suhsin: kamu yang mengatur. Pilihan lanjutan ada di Setting > Suhsin dan di tiap game.", "Suhsin: you are in control. Advanced options are in Settings > Suhsin and in each game.")
                        : L(m, "Hsin menyesuaikan beban tiap game sendiri supaya FPS tetap stabil. Tidak perlu diatur.", "Hsin adjusts the load for each game by itself to keep FPS steady. Nothing to set.");
  float nw = CR - CL;
  ui.text(F_BODY, ui.fit(F_BODY, note, 12, nw), CL, SH - 30, 12, ui.th.ink);
}

// ------------------------------------------------------------------ launch overlay
void App::startLaunch(const GameInfo& g, float cx, float cy) {
  launch_ = Launch(); launch_.on = true; launch_.t0 = ui.now; launch_.cx = cx; launch_.cy = cy; launch_.name = g.label; launch_.pkg = g.pkg;
  if (!animOn()) { m.cmd("game.launch", g.pkg); launch_.sent = true; launch_.on = false; }
}

void App::drawLaunch() {
  if (!launch_.on) return;
  double e = ui.now - launch_.t0;
  ui.busy = true;
  Rect st(0, 0, SW, SH);
  float p = (float)std::min(1.0, e / .45);
  float ret = e > 2.3 ? (float)std::min(1.0, (e - 2.3) / .4) : 0.f;
  if (!launch_.sent && e > .3) { launch_.sent = true; m.cmd("game.launch", launch_.pkg); }
  float grow = ret > 0 ? 1.f - ret : p;
  inkWash(*cv_, st, launch_.cx, launch_.cy, grow, kDeep);
  if (e > .35 && ret < .6f) {
    float q = std::min(1.f, (float)(e - .35) / .5f), a = ret > 0 ? 1.f - ret / .6f : q;
    cv_->setAlpha(a);
    float cx = (L0 + SW) * .5f, cy = SH * .5f - 14;
    float prog = easeOut(std::min(1.f, (float)(e - .4) / 1.1f));
    enso(*cv_, cx, cy, 34, 5.2f, kBone, 0.f, .12f + .8f * prog, 3);
    ui.text(F_DISP, launch_.name, cx, cy + 50, 22, kBone, 1, 1.3f);
    ui.text(F_BODY, L(m, "MENYIAPKAN", "PREPARING"), cx, cy + 82, 11.5f, kBone.withA(.75f), 1, 2.f);
    cv_->setAlpha(1);
  }
  if (e > 2.7) launch_.on = false;
}

}  // namespace hs
