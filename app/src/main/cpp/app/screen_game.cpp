#include "app.h"
#include "widgets.h"
#include <algorithm>

namespace hs {

static const Col kDeep(.051f, .051f, .063f), kBone(.922f, .906f, .863f);

static std::string initialOf(const std::string& s) {
  for (size_t i = 0; i < s.size(); i++) {
    unsigned char c = s[i];
    if (std::isalnum(c)) return std::string(1, (char)std::toupper(c));
  }
  return "?";
}

void App::gameArt(const GameInfo& g, Rect r, bool su) {
  Col bg = su ? ui.th.ink : ui.th.paper2, fg = su ? ui.th.paper : ui.th.ink;
  cv_->rrect(r.x, r.y, r.w, r.h, 0, bg);
  uint32_t sd = hash32(std::hash<std::string>()(g.pkg) & 0xffffffffu);
  cv_->pushClip(r);
  for (int b = 0; b < 3; b++) {
    float yy = r.y + r.h * (.50f + b * .17f) + (rnd(sd, b) - .5f) * 8;
    float x0 = r.x - 10 + rnd(sd, b + 5) * 30, x1 = r.x + r.w + 10 - rnd(sd, b + 9) * 30;
    float al = .12f + b * .06f;
    Col mix(bg.r + (fg.r - bg.r) * al, bg.g + (fg.g - bg.g) * al, bg.b + (fg.b - bg.b) * al);
    brush(*cv_, x0, yy, x1, yy + (rnd(sd, b + 12) - .5f) * 14, 15.f - b * 2.f, mix, sd + b);
  }
  cv_->popClip();
  float cx = r.x + r.w * .5f, cy = r.y + r.h * .5f - 3;
  enso(*cv_, cx, cy, 27, 4.4f, fg, rnd(sd, 3) * .15f, .84f + rnd(sd, 4) * .1f, sd);
  ui.text(F_DISP, initialOf(g.label), cx, cy - 14, 26, fg, 1);
}

void App::gameCard(int i, Rect r) {
  GameInfo& g = m.games[i];
  bool su = g.mode == "suhsin";
  uint32_t id = Ui::id(("gc" + g.pkg).c_str());
  cv_->rrect(r.x, r.y, r.w, r.h, 2, ui.th.card);
  roughBox(*cv_, r, 200 + i, su ? 2.4f : 1.6f, ui.th.ink);
  Rect art(r.x + 7, r.y + 7, r.w - 14, 100);
  gameArt(g, art, su);
  // mode pill
  const char* pl = su ? "Suhsin" : "Hsin";
  float pw = ui.tw_(F_BOLD, pl, 11) + 16;
  Rect pr(art.x + 8, art.y + 8, pw, 20);
  cv_->rrect(pr.x, pr.y, pr.w, pr.h, 2, su ? ui.th.paper : ui.th.paper2);
  roughBox(*cv_, pr, 300 + i, 1.4f, su ? ui.th.paper : ui.th.ink);
  ui.text(F_BOLD, pl, pr.x + pr.w * .5f, pr.y + 3.5f, 11, ui.th.ink, 1);
  // name (up to two lines)
  std::vector<std::string> ls;
  fn_->wrap(F_DISP, g.label, 15, r.w - 24, &ls);
  for (int k = 0; k < (int)ls.size() && k < 2; k++) {
    std::string t = (k == 1 && ls.size() > 2) ? ui.fit(F_DISP, ls[k] + " " + ls[2], 15, r.w - 24) : ls[k];
    ui.text(F_DISP, t, r.x + 12, r.y + 111 + k * 17, 15, ui.th.ink);
  }
  std::string sub = su ? std::string(L(m, "Batas ", "Limit ")) + std::to_string(g.fps) + " FPS \xC2\xB7 " + std::to_string(g.res) + "%"
                       : std::string(L(m, "Otomatis, FPS stabil", "Auto, steady FPS"));
  ui.text(F_BODY, ui.fit(F_BODY, sub, 11.5f, r.w - 24), r.x + 12, r.y + 111 + (ls.size() > 1 ? 2 : 1) * 17 + 2, 11.5f, ui.th.ink2);
  // actions
  Rect play(r.x + 10, r.y + r.h - 50, r.w - 20 - 46, 40), gear(r.x + r.w - 10 - 40, r.y + r.h - 50, 40, 40);
  BtnStyle st; st.filled = true; st.iconId = IC_PLAY; st.size = 14;
  if (ui.button(id + 1, play, L(m, "Main", "Play"), st)) startLaunch(g, ui.ux, ui.uy);
  BtnStyle gs; gs.iconId = IC_GEAR; gs.size = 20;
  if (ui.button(id + 2, gear, "", gs)) { sheetPkg_ = g.pkg; openSheet(SH_GAME); }
}

void App::drawGame() {
  drawBg(IMG_BG_GAME, Rect(L0, 0, SW - L0, SH));
  float tw = 0;
  drawHeader(L(m, "Game", "Game"), &tw);
  BtnStyle bs; bs.iconId = IC_DEX; bs.size = 12.5f;
  Rect ob(CL + tw + 14, 18, 132, 32);
  if (ui.button(Ui::id("optAll"), ob, L(m, "Optimasi app", "Optimize apps"), bs)) {
    std::vector<PickItem> it;
    for (auto& g : m.games) it.push_back({g.pkg, g.label, false});
    if (it.empty()) m.toast(L(m, "Belum ada game untuk dioptimasi", "No games to optimize"), true);
    else openPicker("dex", L(m, "Optimasi app (dexopt)", "App optimization (dexopt)"), L(m, "Mulai", "Start"), it, true);
  }
  float cardW = 172, gap = 14, y = 66, ch = 238;
  Rect view(L0, y - 4, SW - L0, ch + 12);
  int n = (int)m.games.size();
  float len = (CL - L0) + (n + 1) * (cardW + gap) + 70;
  ui.scrollBegin(Ui::id("gameShelf"), gameScroll_, view, true);
  for (int i = 0; i < n; i++) {
    Rect r(CL + i * (cardW + gap), y, cardW, ch);
    if (r.x + r.w - gameScroll_.off < L0 - 4 || r.x - gameScroll_.off > SW + 4) continue;
    gameCard(i, r);
  }
  {  // add card
    Rect r(CL + n * (cardW + gap), y, cardW, ch);
    uint32_t id = Ui::id("gcAdd");
    bool pr = ui.pressing(id, r);
    cv_->rrect(r.x, r.y, r.w, r.h, 2, pr ? ui.th.paper2 : ui.th.card);
    roughBox(*cv_, r, 777, 1.6f, ui.th.ink, true);
    icon(*cv_, IC_PLUS, r.x + r.w * .5f - 20, r.y + r.h * .5f - 34, 40, ui.th.ink2, 2.2f);
    ui.text(F_BOLD, L(m, "Tambah game", "Add game"), r.x + r.w * .5f, r.y + r.h * .5f + 14, 13.5f, ui.th.ink2, 1);
    if (ui.clicked(id, r)) { m.cmd("apps.request"); openPicker("add", L(m, "Tambah game", "Add games"), L(m, "Tambah", "Add"), {}, false); }
  }
  ui.scrollEnd(gameScroll_, view, len, true);
}

// ------------------------------------------------------------------ sheets
void App::openSheet(int kind) {
  sheetKind_ = kind; sheetClosing_ = false; sheetT0_ = ui.now; sheetScroll_ = Scroll();
  confirmDel_ = false; sheetFrame_ = frameNo_;
  if (!animOn()) sheetT0_ = ui.now - 10;
}
void App::closeSheet() {
  if (sheetKind_ == SH_NONE || sheetClosing_) return;
  sheetClosing_ = true; sheetT0_ = ui.now;
  if (!animOn()) sheetKind_ = SH_NONE;
}
float App::sheetOpen() {
  double e = ui.now - sheetT0_;
  if (sheetClosing_) { float p = (float)std::min(1.0, e / .19); if (p >= 1) { sheetKind_ = SH_NONE; sheetClosing_ = false; } return 1.f - p; }
  return easeOut((float)std::min(1.0, e / .26));
}

void App::drawSheet() {
  if (sheetKind_ == SH_NONE) return;
  float o = sheetOpen();
  if (sheetKind_ == SH_NONE) return;
  if (o < 1.f) ui.busy = true;
  float shH = sheetKind_ == SH_PICK ? 282 : 262;
  float x = L0 + 8, w = SW - L0 - 8 - insR_ / scale_ - 8, y = SH - shH * o;
  cv_->pushClip(Rect(L0, 0, SW - L0, SH));
  cv_->rrect(L0, 0, SW - L0, SH, 0, ui.th.ink.withA(.42f * o));
  Rect sh(x, y, w, shH + 30);
  // outside tap closes
  if (!sheetClosing_ && sheetFrame_ != frameNo_ && ui.clicked(Ui::id("scrim"), Rect(L0, 0, SW - L0, std::max(0.f, y)))) closeSheet();
  cv_->rrect(sh.x, sh.y, sh.w, sh.h, 0, ui.th.paper2);
  roughBox(*cv_, sh, 555, 2.2f, ui.th.ink, false, 1.4f);
  brush(*cv_, sh.x + 8, sh.y + 1, sh.x + sh.w - 8, sh.y + 1, 4.f, ui.th.ink, 12);
  if (sheetKind_ == SH_GAME) drawGameSheet(Rect(sh.x, sh.y, sh.w, shH));
  else drawPicker(Rect(sh.x, sh.y, sh.w, shH));
  cv_->popClip();
}

void App::drawGameSheet(Rect s) {
  GameInfo* g = m.game(sheetPkg_);
  if (!g) { closeSheet(); return; }
  bool su = g->mode == "suhsin";
  ui.text(F_DISP, ui.fit(F_DISP, g->label, 20, s.w - 330), s.x + 18, s.y + 14, 20, ui.th.ink);
  // mode seg + close
  Rect cl(s.x + s.w - 14 - 36, s.y + 10, 36, 34);
  BtnStyle cs; cs.iconId = IC_CLOSE; cs.size = 16;
  if (ui.button(Ui::id("shClose"), cl, "", cs)) closeSheet();
  float sx = cl.x - 12 - 188;
  if (ui.chip(Ui::id("shHsin"), Rect(sx, s.y + 12, 92, 30), "Hsin", !su, 13) && su) { g->mode = "hsin"; m.cmd("game.set", g->pkg, "mode", "hsin"); }
  if (ui.chip(Ui::id("shSuh"), Rect(sx + 96, s.y + 12, 92, 30), "Suhsin", su, 13) && !su) { g->mode = "suhsin"; m.cmd("game.set", g->pkg, "mode", "suhsin"); }
  Rect body(s.x + 16, s.y + 54, s.w - 32, s.h - 60);
  ui.scrollBegin(Ui::id("shBody"), sheetScroll_, body);
  float bw = body.w, c3 = (bw - 28) / 3, y = body.y + 2, x0 = body.x;
  auto lab = [&](const char* t, const char* tag, float x, float yy) {
    ui.text(F_BOLD, t, x, yy, 13.5f, ui.th.ink);
    if (tag && *tag) {
      float tx = x + ui.tw_(F_BOLD, t, 13.5f) + 7, tw = ui.tw_(F_BOLD, tag, 9.5f) + 10;
      roughBox(*cv_, Rect(tx, yy + 1, tw, 15), 17, 1.3f, ui.th.ink);
      ui.text(F_BOLD, tag, tx + tw * .5f, yy + 2.5f, 9.5f, ui.th.ink, 1, .6f);
    }
  };
  auto sug = [&](const std::string& t, float x, float yy) { ui.text(F_BODY, ui.fit(F_BODY, t, 11.5f, c3), x, yy, 11.5f, ui.th.ink2); };
  float end = y;
  Opts resO = {{"100", "100%"}, {"85", "85%"}, {"70", "70%"}, {"55", "55%"}};
  auto resRow = [&](float x, float yy) {
    lab(L(m, "Resolusi", "Resolution"), L(m, "Eksperimen", "Experimental"), x, yy);
    sug(L(m, "Saran 100%. Turun hanya bila FPS kurang.", "Suggest 100%. Lower only if FPS is short."), x, yy + 18);
    float h; int k = chipRow(ui, Ui::id("res"), x, yy + 38, c3, resO, std::to_string(g->res), &h);
    if (k >= 0) { g->res = std::atoi(resO[k].first.c_str()); m.cmd("game.set", g->pkg, "res", resO[k].first); }
    return yy + 38 + h;
  };
  auto dexRow = [&](float x, float yy) {
    lab(L(m, "Optimasi app (dexopt)", "App optimization (dexopt)"), "", x, yy);
    sug(L(m, "Kompilasi ulang game agar terbuka lebih cepat.", "Recompile the game so it opens faster."), x, yy + 18);
    BtnStyle b; b.iconId = IC_DEX; b.size = 12.5f;
    if (ui.button(Ui::id("dexThis"), Rect(x, yy + 40, std::min(c3, 190.f), 32), L(m, "Optimasi game ini", "Optimize this game"), b)) {
      std::vector<PickItem> it; for (auto& gg : m.games) it.push_back({gg.pkg, gg.label, gg.pkg == g->pkg});
      openPicker("dex", L(m, "Optimasi app (dexopt)", "App optimization (dexopt)"), L(m, "Mulai", "Start"), it, true);
    }
    return yy + 72;
  };
  auto delRow = [&](float x, float yy) {
    lab(L(m, "Daftar game", "Game list"), "", x, yy);
    sug(L(m, "Game tetap terpasang di HP.", "The game stays installed on the phone."), x, yy + 18);
    BtnStyle b; b.dashed = true; b.size = 12.5f;
    if (ui.button(Ui::id("delGame"), Rect(x, yy + 40, std::min(c3, 190.f), 32), confirmDel_ ? L(m, "Ketuk lagi untuk hapus", "Tap again to remove") : L(m, "Hapus dari daftar", "Remove from list"), b)) {
      if (!confirmDel_) { confirmDel_ = true; }
      else { m.cmd("game.remove", g->pkg); closeSheet(); }
    }
    return yy + 72;
  };
  if (!su) {
    ui.text(F_BODY, L(m, "Hsin mengatur beban otomatis. Resolusi dan optimasi app boleh kamu atur. Pilih Suhsin untuk kendali penuh.", "Hsin adjusts the load automatically. You may set resolution and app optimization. Choose Suhsin for full control."), x0, y, 12.5f, ui.th.ink2);
    y += 24;
    float a = resRow(x0, y), b = dexRow(x0 + c3 + 14, y), c = delRow(x0 + 2 * (c3 + 14), y);
    end = std::max(a, std::max(b, c));
  } else {
    // row 1: FPS limit, resolution, CPU max
    lab(L(m, "Batas FPS", "FPS limit"), "", x0, y);
    sug(L(m, "Saran 60. Batas rendah = lebih dingin.", "Suggest 60. A lower limit runs cooler."), x0, y + 18);
    Opts fo = {{"30", "30"}, {"45", "45"}, {"60", "60"}, {"90", "90"}, {"120", "120"}, {"off", L(m, "Bebas", "Free")}};
    float h1; std::string curF = g->fps >= 240 ? "off" : std::to_string(g->fps);
    int k = chipRow(ui, Ui::id("fpsLim"), x0, y + 38, c3, fo, curF, &h1);
    if (k >= 0) { g->fps = fo[k].first == "off" ? 240 : std::atoi(fo[k].first.c_str()); m.cmd("game.set", g->pkg, "fps", fo[k].first); }
    float a = y + 38 + h1;
    float b = resRow(x0 + c3 + 14, y);
    float cx = x0 + 2 * (c3 + 14);
    lab(L(m, "CPU maksimum", "CPU maximum"), "", cx, y);
    bool capCpu = m.cap("cpucap", false);
    sug(capCpu ? L(m, "Saran 90%. Menyisakan ruang agar tidak cepat panas.", "Suggest 90%. Leaves headroom so it stays cool.") : L(m, "Belum didukung modul ini (butuh modul baru).", "Not supported by this module yet (needs a newer module)."), cx, y + 18);
    float cpv = (float)g->cpu;
    ui.text(F_BOLD, std::to_string(g->cpu) + "%", cx + c3, y, 13, ui.th.ink, 2);
    bool pb = ui.blockInput; if (!capCpu) { ui.blockInput = true; cv_->setAlpha(.45f); }
    if (ui.slider(Ui::id("cpuCap"), Rect(cx + 4, y + 52, c3 - 8, 14), &cpv, 50, 100, 5) ) { g->cpu = (int)cpv; cpuDirty_ = true; }
    if (!capCpu) { ui.blockInput = pb; cv_->setAlpha(1); }
    if (cpuDirty_ && !ui.down) { cpuDirty_ = false; m.cmd("game.set", g->pkg, "cpu", std::to_string(g->cpu)); }
    float c = y + 76;
    float y2 = std::max(a, std::max(b, c)) + 14;
    // row 2: renderer, dexopt, remove
    lab(L(m, "Renderer", "Renderer"), L(m, "Eksperimen", "Experimental"), x0, y2);
    sug(L(m, "Saran Bawaan. Vulkan boleh dicoba.", "Suggest Default. You may try Vulkan."), x0, y2 + 18);
    Opts ro = {{"default", L(m, "Bawaan", "Default")}, {"skiagl", "SkiaGL"}, {"skiavk", "Vulkan"}};
    std::vector<bool> rok = {true, true, m.cap("vulkan", true)};
    float h2; int rk = chipRow(ui, Ui::id("rend"), x0, y2 + 38, c3, ro, g->render, &h2, true, &rok);
    if (rk >= 0) { g->render = ro[rk].first; m.cmd("game.set", g->pkg, "render", ro[rk].first); }
    float d = dexRow(x0 + c3 + 14, y2), e = delRow(x0 + 2 * (c3 + 14), y2);
    end = std::max(y2 + 38 + h2, std::max(d, e));
  }
  ui.scrollEnd(sheetScroll_, body, end - body.y + 12);
}

// ------------------------------------------------------------------ picker
void App::openPicker(const std::string& id, const std::string& title, const std::string& action, std::vector<PickItem> items, bool modes) {
  pickId_ = id; pickTitle_ = title; pickAction_ = action; pick_ = std::move(items); pickModes_ = modes; pickSrc_ = -1;
  openSheet(SH_PICK);
}

void App::drawPicker(Rect s) {
  // live sources
  if (pickId_ == "add") {
    int n = (int)m.apps.size();
    if (n != pickSrc_) {
      std::map<std::string, bool> keep; for (auto& p : pick_) keep[p.key] = p.on;
      pick_.clear();
      for (auto& a : m.apps) if (!m.game(a.pkg)) pick_.push_back({a.pkg, a.label, keep[a.pkg]});
      pickSrc_ = n;
    }
  } else if (pickId_ == "freeze") {
    int n = (int)m.apps.size();
    if (n != pickSrc_) {
      pick_.clear();
      for (auto& a : m.apps) { bool fr = false; for (auto& f : m.frozenApps) if (f.pkg == a.pkg) fr = true; pick_.push_back({a.pkg, a.label, fr}); }
      pickSrc_ = n;
    }
  }
  ui.text(F_DISP, pickTitle_, s.x + 18, s.y + 14, 20, ui.th.ink);
  Rect cl(s.x + s.w - 14 - 36, s.y + 10, 36, 34);
  BtnStyle cs; cs.iconId = IC_CLOSE; cs.size = 16;
  if (ui.button(Ui::id("pkClose"), cl, "", cs)) closeSheet();
  float y = s.y + 54, x = s.x + 18, w = s.w - 36;
  if (pickModes_) {
    static const Opts dm = {{"speed-profile", ""}, {"speed", ""}, {"everything", ""}, {"verify", ""}, {"reset", ""}};
    Opts o = {{"speed-profile", L(m, "Seimbang", "Balanced")}, {"speed", L(m, "Cepat", "Fast")}, {"everything", L(m, "Maksimal", "Maximum")}, {"verify", L(m, "Ringan", "Light")}, {"reset", "Reset"}};
    float h; int k = chipRow(ui, Ui::id("dexMode"), x, y, w, o, pickDexMode_, &h);
    if (k >= 0) pickDexMode_ = o[k].first;
    y += h + 4;
    const char* hint = pickDexMode_ == "speed-profile" ? L(m, "Memakai pola pemakaianmu dan hemat storage. Disarankan.", "Uses your usage pattern and saves storage. Recommended.")
        : pickDexMode_ == "speed" ? L(m, "Kompilasi penuh kode yang dipakai. Lebih cepat, storage bertambah.", "Full compile of used code. Faster, uses more storage.")
        : pickDexMode_ == "everything" ? L(m, "Kompilasi semuanya. Paling cepat, storage paling besar.", "Compile everything. Fastest, largest storage.")
        : pickDexMode_ == "verify" ? L(m, "Hanya verifikasi. Storage kecil, tidak mempercepat.", "Verify only. Small storage, no speed-up.")
        : L(m, "Kembali ke kompilasi bawaan sistem.", "Back to the system default compile.");
    ui.text(F_BODY, hint, x, y, 11.5f, ui.th.ink2);
    y += 20;
  }
  float botH = 46;
  Rect lv(x - 4, y, w + 8, s.y + s.h - botH - y - 4);
  float rowH = 36, total = std::max(1, (int)pick_.size()) * rowH;
  ui.scrollBegin(Ui::id("pkList"), sheetScroll_, lv);
  if (pick_.empty()) ui.text(F_BODY, pickId_ == "add" ? L(m, "Mencari app terpasang...", "Looking for installed apps...") : L(m, "Daftar kosong.", "The list is empty."), x, y + 10, 13, ui.th.ink2);
  for (size_t i = 0; i < pick_.size(); i++) {
    float ry = y + i * rowH;
    if (ry + rowH < lv.y + sheetScroll_.off - 4 || ry > lv.y + lv.h + sheetScroll_.off + 4) continue;
    Rect row(x, ry, w, rowH);
    uint32_t id = Ui::id(("pk" + pick_[i].key).c_str());
    bool v = pick_[i].on;
    if (ui.clicked(id, row)) { pick_[i].on = !pick_[i].on; v = pick_[i].on; }
    ui.rule(x, ry + rowH - 1, x + w, ry + rowH - 1);
    bool dummy = v; bool pb = ui.blockInput; ui.blockInput = true;
    ui.checkbox(id + 7, Rect(x + 4, ry + 8, 20, 20), &dummy);
    ui.blockInput = pb;
    ui.text(F_BOLD, ui.fit(F_BOLD, pick_[i].label, 13.5f, w * .55f), x + 36, ry + 6, 13.5f, ui.th.ink);
    ui.text(F_BODY, ui.fit(F_BODY, pick_[i].key, 11, w * .4f), x + w, ry + 10, 11, ui.th.ink2, 2);
  }
  ui.scrollEnd(sheetScroll_, lv, total + 4);
  // bottom actions
  float by = s.y + s.h - botH + 4;
  int cnt = 0; for (auto& p : pick_) if (p.on) cnt++;
  BtnStyle b1; b1.size = 12.5f;
  bool all = cnt == (int)pick_.size() && !pick_.empty();
  if (ui.button(Ui::id("pkAll"), Rect(x, by, 128, 34), all ? L(m, "Kosongkan", "Clear") : L(m, "Pilih semua", "Select all"), b1)) for (auto& p : pick_) p.on = !all;
  if (pickId_ == "add") {
    if (ui.button(Ui::id("pkScan"), Rect(x + 136, by, 150, 34), L(m, "Cari otomatis", "Auto detect"), b1)) { m.cmd("game.scan"); m.toast(L(m, "Mencari game di HP...", "Looking for games...")); }
  }
  std::string prog = m.str("dex.progress");
  bool busy = pickId_ == "dex" && !prog.empty();
  std::string act = busy ? std::string(L(m, "Mengoptimasi ", "Optimizing ")) + prog : pickAction_ + (cnt ? " (" + std::to_string(cnt) + ")" : "");
  BtnStyle b2; b2.filled = true; b2.size = 13;
  Rect ab(x + w - 190, by, 190, 34);
  bool pb2 = ui.blockInput; if (busy || (cnt == 0 && pickId_ != "freeze")) { ui.blockInput = true; cv_->setAlpha(busy ? 1.f : .45f); }
  bool go = ui.button(Ui::id("pkGo"), ab, act, b2);
  ui.blockInput = pb2; cv_->setAlpha(1);
  if (go) {
    std::string keys;
    for (auto& p : pick_) if (p.on) keys += (keys.empty() ? "" : ",") + p.key;
    if (pickId_ == "dex") { m.cmd("dex", pickDexMode_, keys); m.set("dex.progress", "0/" + std::to_string(cnt)); }
    else if (pickId_ == "add") { m.cmd("game.add", keys); closeSheet(); }
    else if (pickId_ == "freeze") {
      std::string on, off;
      for (auto& p : pick_) {
        bool was = false; for (auto& f : m.frozenApps) if (f.pkg == p.key) was = true;
        if (p.on && !was) on += (on.empty() ? "" : ",") + p.key;
        if (!p.on && was) off += (off.empty() ? "" : ",") + p.key;
      }
      m.cmd("freeze", on, off); closeSheet();
    }
  }
}

}  // namespace hs
