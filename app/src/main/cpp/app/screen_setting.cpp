#include "app.h"
#include "catalog.h"
#include "widgets.h"
#include <algorithm>
#include <functional>

namespace hs {

static const char* kGroupName[][3] = {
  // key, id, en
  {"layar", "Layar", "Screen"}, {"memori", "Memori", "Memory"}, {"cpu", "CPU", "CPU"}, {"gpu", "GPU", "GPU"},
  {"vm", "Memori (VM)", "Memory (VM)"}, {"io", "Penyimpanan (IO)", "Storage (IO)"}, {"suhu", "Suhu", "Temperature"}, {"daya", "Daya", "Power"}};
static const char* kGroupDesc[][3] = {
  {"layar", "Kehalusan dan kenyamanan layar.", "Smoothness and comfort of the screen."},
  {"memori", "RAM dibersihkan supaya game tidak ditutup sistem.", "RAM is freed so the system does not close the game."},
  {"cpu", "Otak HP. Makin kencang, makin panas dan boros.", "The brain of the phone. Faster means hotter and thirstier."},
  {"gpu", "Pengolah gambar 3D. Penentu FPS di game.", "Draws 3D graphics. Decides game FPS."},
  {"vm", "Cara HP membagi RAM dan swap. Memengaruhi patah-patah saat RAM menipis.", "How the phone shares RAM and swap. Affects stutter when RAM runs low."},
  {"io", "Cara HP membaca dan menulis data. Memengaruhi waktu loading.", "How the phone reads and writes data. Affects loading time."},
  {"suhu", "Pengaman panas. Melepasnya bisa menaikkan FPS, tapi HP jadi sangat panas.", "Heat protection. Removing it can raise FPS, but the phone gets very hot."},
  {"daya", "Pengaturan listrik saat main.", "Power while playing."}};

const std::vector<std::string>& App::wrap(int font, const std::string& s, float size, float w) {
  std::string key = std::to_string(font) + "|" + std::to_string((int)(size * 10)) + "|" + std::to_string((int)w) + "|" + s;
  auto it = wrapCache_.find(key);
  if (it != wrapCache_.end()) return it->second;
  if (wrapCache_.size() > 600) wrapCache_.clear();
  std::vector<std::string> out;
  fn_->wrap(font, s, size, w, &out);
  return wrapCache_[key] = out;
}

float App::para(const std::string& s, float x, float y, float w, float size, Col c, int font, bool draw) {
  auto& ls = wrap(font, s, size, w);
  float lh = size * 1.38f;
  if (draw) for (size_t i = 0; i < ls.size(); i++) ui.text(font, ls[i], x, y + i * lh, size, c);
  return ls.size() * lh;
}

static std::string optLabel(const Model& m, const Feat& f, const FOpt& o) {
  if (o.id) return m.lang == 1 ? o.en : o.id;
  return std::string(o.v) + (f.unit ? f.unit : "");
}

// ---------- generic rows. Each returns its height; draw=false only measures.
namespace {
struct RowCtx { App* a; };
}

void App::featSet(const std::string& id, const std::string& v, const std::string& cmd) {
  const Feat* f = findFeat(id.c_str());
  m.set("f." + id, v);
  if (f && f->cmd && std::string(f->cmd) == "rec.set") m.cmd("rec.set", f->key ? f->key : id.c_str(), v);
  else m.cmd(cmd.empty() ? "feat" : cmd, f && f->key ? f->key : id, v);
}

static float rowHead(App& A, Ui& ui, Model& m, const std::string& name, const char* tag, bool warn, const std::string& desc, float x, float y, float w,
                     float ctlW, bool draw, bool first, std::function<float(const std::string&, float, float, float, float, Col, int, bool)> para) {
  float tw = w - (ctlW > 0 ? ctlW + 12 : 0);
  if (draw) {
    if (!first) ui.rule(x, y, x + w, y);
    ui.text(F_BOLD, ui.fit(F_BOLD, name, 14, tw - (tag ? 90 : 0)), x, y + 8, 14, ui.th.ink);
    if (tag) {
      float nx = x + ui.tw_(F_BOLD, ui.fit(F_BOLD, name, 14, tw - 90), 14) + 8, bw = ui.tw_(F_BOLD, tag, 9.5f) + 10;
      Rect r(nx, y + 10, bw, 15);
      if (warn) ui.cv->rrect(r.x, r.y, r.w, r.h, 2, ui.th.ink);
      roughBox(*ui.cv, r, 91, 1.3f, ui.th.ink);
      ui.text(F_BOLD, tag, r.x + r.w * .5f, r.y + 1.8f, 9.5f, warn ? ui.th.paper : ui.th.ink, 1, .6f);
    }
  }
  float dh = para(desc, x, y + 27, tw, 12, ui.th.ink2, F_BODY, draw);
  return 27 + dh + 5;
}

// ---------------------------------------------------------------- feature row (catalogue)
float App::drawFeature(const void* fp, float x, float y, float w, bool draw, bool first) {
  const Feat& f = *(const Feat*)fp;
  bool ok = f.cap ? m.cap(f.cap, f.capDef) : true;
  std::string name = m.lang ? f.nEn : f.nId, desc = m.lang ? f.dEn : f.dId;
  const char* tag = f.tag ? (m.lang ? f.tagEn : f.tag) : nullptr;
  std::string cur = m.str(std::string("f.") + f.id, f.def ? f.def : "");
  auto pf = [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); };
  for (int pass = 0; pass < 2; pass++) {
    bool d = pass == 1;
    if (d && (y + 400 < visTop_ || y > visBot_)) { /* far outside: cheap skip handled below */ }
    if (d && !(rowH_ + y >= visTop_ && y <= visBot_)) return rowH_;
    float ctlW = f.kind == FK_SW ? 50 : f.kind == FK_ACT ? 110 : f.kind == FK_INFO ? 100 : 0;
    if (d && !ok) { cv_->setAlpha(.5f); }
    bool pb = ui.blockInput; if (d && !ok) ui.blockInput = true;
    float h = rowHead(*this, ui, m, name, tag, f.warn, desc, x, y, w, ctlW, d, first, pf);
    uint32_t id = Ui::id(f.id);
    if (f.kind == FK_SW) {
      bool v = cur == "1";
      if (d && ui.toggle(id, Rect(x + w - 46, y + 10, 44, 22), &v, f.warn)) featSet(f.id, v ? "1" : "0", "");
      h = std::max(h, 46.f);
    } else if (f.kind == FK_INFO) {
      std::string val = m.str(std::string("f.") + f.id, m.lang ? "Follows mode" : "Ikut mode");
      if (d) ui.text(F_BOLD, val, x + w, y + 9, 13, ui.th.ink, 2);
      h = std::max(h, 46.f);
    } else if (f.kind == FK_CHIPS) {
      Opts o; for (auto& op : f.opts) o.push_back({op.v, optLabel(m, f, op)});
      float ch = 0;
      int k = chipRow(ui, id, x, y + h, w, o, cur, &ch, true, nullptr, 28, 12.5f, d);
      if (d && k >= 0) featSet(f.id, o[k].first, "");
      h += ch + 8;
    } else if (f.kind == FK_SLIDER) {
      float v = (float)std::atoi(cur.c_str());
      float sw = std::min(w - 70, 330.f);
      if (d) {
        ui.text(F_BOLD, std::to_string((int)v), x + w, y + 9, 13, ui.th.ink, 2);
        if (ui.slider(id, Rect(x + 4, y + h + 4, sw, 14), &v, (float)f.lo, (float)f.hi, (float)f.step)) { m.set(std::string("f.") + f.id, std::to_string((int)v)); sliderDirty_ = f.id; }
        if (!ui.down && !sliderDirty_.empty() && sliderDirty_ == f.id) { sliderDirty_.clear(); featSet(f.id, std::to_string((int)v), ""); }
      }
      h += 28;
    }
    // suggestion line
    if (f.rec) {
      std::string recLabel;
      for (auto& op : f.opts) if (std::string(op.v) == f.rec) recLabel = optLabel(m, f, op);
      if (f.opts.empty()) recLabel = f.kind == FK_SW ? std::string(std::string(f.rec) == "1" ? L(m, "Hidup", "On") : L(m, "Mati", "Off")) : std::string(f.rec);
      bool same = cur == f.rec;
      std::string txt = ok ? std::string(same ? "\xE2\x9C\x93 " : "") + L(m, "Saran: ", "Suggested: ") + recLabel + ". " + (m.lang ? f.whyEn : f.whyId)
                           : std::string(L(m, "Tidak tersedia di HP atau modul ini.", "Not available on this phone or module."));
      bool btn = ok && !same;
      float tw = w - (btn ? 108 : 0);
      float rh = para(txt, x, y + h, tw, 11.5f, ui.th.ink2, F_BODY, d);
      if (d && btn) {
        BtnStyle bs; bs.size = 11.5f;
        if (ui.button(id + 77, Rect(x + w - 100, y + h - 3, 100, 26), L(m, "Pakai saran", "Use suggestion"), bs)) featSet(f.id, f.rec, "");
      }
      h += std::max(rh, btn ? 24.f : 0.f) + 6;
    } else if (!ok) {
      float rh = para(L(m, "Tidak tersedia di HP atau modul ini.", "Not available on this phone or module."), x, y + h, w, 11.5f, ui.th.ink2, F_BODY, d);
      h += rh + 6;
    }
    ui.blockInput = pb; cv_->setAlpha(1);
    if (!d) rowH_ = h + 2;
    else return h + 2;
  }
  return rowH_;
}

// ---------------------------------------------------------------- group (accordion)
static const char* gname(const Model& m, const char* key) { for (auto& g : kGroupName) if (!std::strcmp(g[0], key)) return m.lang ? g[2] : g[1]; return key; }
static const char* gdesc(const Model& m, const char* key) { for (auto& g : kGroupDesc) if (!std::strcmp(g[0], key)) return m.lang ? g[2] : g[1]; return ""; }

float App::groupBox(const std::string& key, const std::string& name, const std::string& desc, float x, float y, float w, bool openDef, const std::function<float(float, float, float)>& content) {
  uint32_t id = Ui::id(("grp" + key).c_str());
  auto it = groupOpen_.find(key);
  if (it == groupOpen_.end()) it = groupOpen_.emplace(key, openDef).first;
  bool open = it->second;
  Tw& t = ui.tw(id, open ? 1.f : 0.f);
  t.to(open ? 1.f : 0.f, ui.now, animOn() ? 200 : 1);
  if (t.running(ui.now)) ui.busy = true;
  float k = t.get(ui.now);
  float prevH = groupH_.count(key) ? groupH_[key] : 300.f;
  float hh = 54, contentH = prevH * k;
  float total = hh + (k > 0.001f ? contentH + 6 * k : 0);
  Rect box(x, y, w, total);
  bool vis = y + total >= visTop_ && y <= visBot_;
  if (vis) {
    cv_->rrect(box.x, box.y, box.w, box.h, 2, ui.th.card);
    roughBox(*cv_, box, Ui::id(key.c_str()), 1.6f, ui.th.ink);
    Rect hr(x, y, w, hh);
    bool pr = ui.pressing(id, hr);
    ui.text(F_DISP, name, x + 14, y + 8, 16, ui.th.ink);
    ui.text(F_BODY, ui.fit(F_BODY, desc, 11.5f, w - 60), x + 14, y + 30, 11.5f, ui.th.ink2);
    cv_->pushT(x + w - 26, y + hh * .5f - 8, 1.f);
    icon(*cv_, open ? IC_CHEV_D : IC_CHEV_R, 0, 0, 16, pr ? ui.th.ink2 : ui.th.ink, 2.2f);
    cv_->popT();
    if (ui.clicked(id, hr)) it->second = !it->second;
  }
  if (k > 0.001f) {
    float cy = y + hh;
    float h = 0;
    if (open || k > .001f) {
      cv_->pushClip(Rect(x, y + hh - 1, w, std::max(0.f, contentH + 4)));
      cv_->setAlpha(k < 1.f ? k : 1.f);
      h = content(x + 14, cy, w - 28);
      cv_->setAlpha(1.f);
      cv_->popClip();
    }
    groupH_[key] = h + 4;
    if (k >= .999f) total = hh + h + 10;
  }
  return total + 10;
}

// ---------------------------------------------------------------- tier page
float App::pageFitur(int tier, float x, float y, float w) {
  float cy = y;
  const char* intro = tier == 0 ? L(m, "Fitur dasar, aman dipakai di Hsin maupun Suhsin. Tiap fitur punya saran yang cocok untuk HP-mu.", "Basic features, safe in both Hsin and Suhsin. Each one has a suggestion for your phone.")
                                : L(m, "Atur sendiri. Nyalakan yang perlu saja; kalau ragu, ikuti saran.", "Set it yourself. Turn on only what you need; when unsure, follow the suggestion.");
  cy += note(intro, x, cy, w) + 8;
  std::string dev = m.str("dev.line", "itel P65 \xC2\xB7 Unisoc T606 \xC2\xB7 8 GB \xC2\xB7 720x1600");
  std::string dl = std::string(L(m, "HP: ", "Phone: ")) + dev;
  float dw = std::min(w - 250, ui.tw_(F_BOLD, dl, 11.5f) + 20);
  Rect dr(x, cy, std::max(120.f, dw), 28);
  ui.cv->rrect(dr.x, dr.y, dr.w, dr.h, 2, ui.th.card);
  roughBox(*cv_, dr, 31, 1.4f, ui.th.ink);
  ui.text(F_BOLD, ui.fit(F_BOLD, dl, 11.5f, dr.w - 14), dr.x + 8, dr.y + 6, 11.5f, ui.th.ink);
  BtnStyle b1; b1.filled = true; b1.size = 12;
  float bx = dr.x + dr.w + 10;
  if (ui.button(Ui::id("allRec", tier), Rect(bx, cy, 130, 28), L(m, "Pakai semua saran", "Use all suggestions"), b1)) {
    int n = 0;
    for (auto& f : catalog()) {
      if (f.tier != tier || !f.rec) continue;
      if (f.cap && !m.cap(f.cap, f.capDef)) continue;
      if (m.str(std::string("f.") + f.id, f.def ? f.def : "") != f.rec) { featSet(f.id, f.rec, ""); n++; }
    }
    m.toast(std::string(L(m, "Saran dipakai: ", "Suggestions applied: ")) + std::to_string(n) + " " + L(m, "fitur", "features"));
  }
  BtnStyle b2; b2.size = 12;
  if (ui.button(Ui::id("allDef", tier), Rect(bx + 138, cy, 100, 28), L(m, "Bawaan", "Defaults"), b2)) {
    for (auto& f : catalog()) {
      if (f.tier != tier || !f.def) continue;
      if (f.cap && !m.cap(f.cap, f.capDef)) continue;
      if (m.str(std::string("f.") + f.id, f.def) != f.def) featSet(f.id, f.def, "");
    }
    m.toast(L(m, "Kembali ke bawaan", "Back to defaults"));
  }
  cy += 36;
  if (tier == 0) {
    cy += note(L(m, "Resolusi game, renderer, dan optimasi app (dexopt) ada di tab Game, diatur per game.", "Game resolution, renderer, and app optimization (dexopt) are in the Game tab, set per game."), x, cy, w) + 8;
  }
  const char* order0[] = {"layar", "memori"};
  const char* order1[] = {"cpu", "gpu", "vm", "io", "suhu", "daya"};
  const char** ord = tier == 0 ? order0 : order1;
  int nord = tier == 0 ? 2 : 6;
  for (int gi = 0; gi < nord; gi++) {
    const char* g = ord[gi];
    cy += groupBox(std::string("t") + std::to_string(tier) + g, gname(m, g), gdesc(m, g), x, cy, w, gi == 0, [&](float gx, float gy, float gw) {
      float h = 0; bool first = true;
      for (auto& f : catalog()) if (f.tier == tier && !std::strcmp(f.grp, g)) { h += drawFeature(&f, gx, gy + h, gw, true, first); first = false; }
      return h;
    });
  }
  return cy - y;
}

float App::note(const std::string& t, float x, float y, float w) {
  float h = para(t, x + 10, y + 5, w - 20, 12, ui.th.ink, F_BODY, false) + 10;
  ui.cv->rrect(x, y, w, h, 2, ui.th.card);
  roughBox(*cv_, Rect(x, y, w, h), Ui::id(t.c_str()), 1.2f, ui.th.ink);
  para(t, x + 10, y + 5, w - 20, 12, ui.th.ink, F_BODY, true);
  return h;
}

float App::lockBox(float x, float y, float w) {
  float h = 150;
  Rect r(x, y, w, h);
  ui.cv->rrect(r.x, r.y, r.w, r.h, 2, ui.th.card);
  roughBox(*cv_, r, 515, 1.9f, ui.th.ink, true);
  ui.text(F_DISP, L(m, "Fitur lanjutan khusus Suhsin", "Advanced features for Suhsin only"), x + 18, y + 14, 19, ui.th.ink);
  float th = para(L(m, "Di Suhsin kamu mengatur sendiri CPU, GPU, memori, penyimpanan, dan suhu. Hsin tidak memakai fitur ini karena sudah diatur otomatis.", "In Suhsin you set CPU, GPU, memory, storage, and temperature yourself. Hsin does not use these because it is automatic."), x + 18, y + 42, w - 36, 12.5f, ui.th.ink2, F_BODY, true);
  float px = x + 18, py = y + 48 + th;
  const char* names[] = {"CPU", "GPU", L(m, "Memori", "Memory"), L(m, "Penyimpanan", "Storage"), L(m, "Suhu", "Temperature"), L(m, "Daya", "Power")};
  for (auto n : names) {
    float pw = ui.tw_(F_BOLD, n, 11) + 16;
    Rect pr(px, py, pw, 20);
    roughBox(*cv_, pr, 52, 1.3f, ui.th.ink);
    ui.text(F_BOLD, n, pr.x + pr.w * .5f, pr.y + 3.5f, 11, ui.th.ink, 1);
    px += pw + 6;
  }
  BtnStyle bs; bs.filled = true; bs.iconId = IC_SUHSIN; bs.size = 13;
  if (ui.button(Ui::id("goSuh"), Rect(x + 18, y + h - 44, 170, 34), L(m, "Pindah ke Suhsin", "Switch to Suhsin"), bs)) { m.set("mode", "suhsin"); m.cmd("mode", "suhsin"); }
  return h + 10;
}

// ---------------------------------------------------------------- Rekaman
float App::pageRekam(float x, float y, float w) {
  float cy = y;
  // live graph card
  {
    float h = 146;
    Rect r(x, cy, w, h);
    ui.cv->rrect(r.x, r.y, r.w, r.h, 2, ui.th.card);
    roughBox(*cv_, r, 601, 1.6f, ui.th.ink);
    ui.text(F_DISP, L(m, "FPS langsung", "Live FPS"), x + 14, cy + 8, 15, ui.th.ink);
    auto& fp = m.fpsLive;
    int last = fp.empty() ? 0 : fp.back();
    ui.text(F_BOLD, fp.empty() ? "--" : std::to_string(last) + " FPS", x + w - 14, cy + 9, 13, ui.th.ink2, 2);
    Rect g(x + 14, cy + 34, w - 28, 74);
    ui.cv->line(g.x, g.y + g.h * .25f, g.x + g.w, g.y + g.h * .25f, 1.f, ui.th.line);
    ui.cv->line(g.x, g.y + g.h * .75f, g.x + g.w, g.y + g.h * .75f, 1.f, ui.th.line);
    int n = (int)fp.size(); long sum = 0; int mn = 999, jank = 0, base = 0;
    for (int v : fp) base = std::max(base, v);
    for (int i = 0; i < n; i++) {
      sum += fp[i]; mn = std::min(mn, fp[i]); if (fp[i] < base - 9) jank++;
      if (i) {
        float x0 = g.x + (i - 1) * g.w / 59.f, x1 = g.x + i * g.w / 59.f;
        float y0 = g.y + g.h - (fp[i - 1] / 150.f) * g.h, y1 = g.y + g.h - (fp[i] / 150.f) * g.h;
        ui.cv->line(x0, std::max(g.y, y0), x1, std::max(g.y, y1), 2.2f, ui.th.ink);
      }
    }
    std::string st = n ? std::string(L(m, "Rata-rata ", "Average ")) + std::to_string(sum / n) + " \xC2\xB7 " + L(m, "terendah ", "lowest ") + std::to_string(mn) + " \xC2\xB7 " + L(m, "patah ", "drops ") + std::to_string(jank) + L(m, " kali (30 dtk)", " (30 s)")
                       : std::string(L(m, "Buka game untuk melihat FPS di sini.", "Open a game to see FPS here."));
    ui.text(F_BODY, st, x + 14, cy + h - 26, 11.5f, ui.th.ink2);
    cy += h + 10;
  }
  cy += groupBox("rk_set", L(m, "Rekam layar", "Screen recording"), L(m, "Pengaturan video. Tombol rekam ada di panel floating.", "Video settings. The record button is in the floating panel."), x, cy, w, true, [&](float gx, float gy, float gw) {
    float h = 0; bool first = true;
    for (auto& f : catalog()) if (f.tier == 2 && !std::strcmp(f.grp, "rekam") && std::strncmp(f.id, "fpsrec", 6)) { h += drawFeature(&f, gx, gy + h, gw, true, first); first = false; }
    return h;
  });
  cy += groupBox("rk_hist", L(m, "Riwayat FPS", "FPS history"), L(m, "Ringkasan tiap sesi game.", "Summary of every game session."), x, cy, w, true, [&](float gx, float gy, float gw) {
    float h = drawFeature(findFeat("fpsrec"), gx, gy, gw, true, true);
    if (m.hist.empty()) { h += para(L(m, "Belum ada sesi.", "No sessions yet."), gx, gy + h + 4, gw, 12, ui.th.ink2, F_BODY, true) + 8; return h; }
    for (size_t i = 0; i < m.hist.size(); i++) {
      auto& s = m.hist[i];
      float ry = gy + h;
      bool open = histOpen_[(int)i];
      float rh = open ? 78 : 44;
      ui.rule(gx, ry, gx + gw, ry);
      ui.text(F_BOLD, ui.fit(F_BOLD, s.name, 13.5f, gw - 190), gx, ry + 6, 13.5f, ui.th.ink);
      ui.text(F_BODY, std::string(L(m, "Rata-rata ", "Average ")) + std::to_string(s.avg) + " FPS \xC2\xB7 " + s.dur, gx, ry + 24, 11.5f, ui.th.ink2);
      BtnStyle sm; sm.size = 11.5f;
      if (ui.button(Ui::id("hDet", (int)i), Rect(gx + gw - 138, ry + 8, 64, 26), L(m, "Detail", "Details"), sm)) histOpen_[(int)i] = !open;
      if (ui.button(Ui::id("hDel", (int)i), Rect(gx + gw - 68, ry + 8, 64, 26), L(m, "Hapus", "Delete"), sm)) { m.cmd("hist.del", std::to_string(i)); m.hist.erase(m.hist.begin() + i); return h + rh; }
      if (open) ui.text(F_BODY, std::string(L(m, "Terendah ", "Lowest ")) + std::to_string(s.low) + " FPS \xC2\xB7 " + L(m, "patah ", "drops ") + std::to_string(s.jank) + " \xC2\xB7 " + L(m, "suhu maks ", "max temp ") + std::to_string(s.temp) + " \xC2\xB0" "C", gx, ry + 48, 11.5f, ui.th.ink2);
      h += rh;
    }
    return h + 4;
  });
  cy += groupBox("rk_vid", L(m, "Video rekaman", "Recorded videos"), L(m, "Putar atau hapus video yang sudah direkam.", "Play or delete recorded videos."), x, cy, w, false, [&](float gx, float gy, float gw) {
    if (m.vids.empty()) return para(L(m, "Belum ada video.", "No videos yet."), gx, gy + 4, gw, 12, ui.th.ink2, F_BODY, true) + 10;
    float h = 0;
    for (size_t i = 0; i < m.vids.size(); i++) {
      auto& v = m.vids[i]; float ry = gy + h;
      if (i) ui.rule(gx, ry, gx + gw, ry);
      ui.text(F_BOLD, ui.fit(F_BOLD, v.name, 13.5f, gw - 150), gx, ry + 6, 13.5f, ui.th.ink);
      ui.text(F_BODY, ui.fit(F_BODY, v.info, 11.5f, gw - 150), gx, ry + 24, 11.5f, ui.th.ink2);
      BtnStyle sm; sm.size = 11.5f;
      if (ui.button(Ui::id("vPlay", (int)i), Rect(gx + gw - 138, ry + 8, 64, 26), L(m, "Putar", "Play"), sm)) m.cmd("vid.play", v.id);
      if (ui.button(Ui::id("vDel", (int)i), Rect(gx + gw - 68, ry + 8, 64, 26), L(m, "Hapus", "Delete"), sm)) { m.cmd("vid.del", v.id); m.vids.erase(m.vids.begin() + i); return h + 44; }
      h += 44;
    }
    return h + 4;
  });
  return cy - y;
}

// ---------------------------------------------------------------- Alat
float App::actRow(const char* key, const char* nameId, const char* nameEn, const char* dId, const char* dEn, const char* btnId, const char* btnEn,
                  float x, float y, float w, bool first, bool* clicked) {
  std::string name = m.lang ? nameEn : nameId, desc = m.lang ? dEn : dId;
  bool busy = m.flag(std::string("busy.") + key, false);
  float h = rowHead(*this, ui, m, name, nullptr, false, desc, x, y, w, 110, true, first, [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); });
  h = std::max(h, 46.f);
  BtnStyle bs; bs.size = 12.5f; bs.filled = !busy;
  bool pb = ui.blockInput; if (busy) ui.blockInput = true;
  bool ck = ui.button(Ui::id(key), Rect(x + w - 104, y + 8, 104, 30), busy ? "..." : (m.lang ? btnEn : btnId), bs);
  ui.blockInput = pb;
  if (clicked) *clicked = ck;
  return h + 2;
}

float App::pageAlat(float x, float y, float w) {
  float cy = y;
  cy += note(L(m, "Alat sekali ketuk. Aman dipakai kapan saja, kecuali saat game sedang berjalan.", "One-tap tools. Safe any time, except while a game is running."), x, cy, w) + 8;
  cy += groupBox("al_clean", L(m, "Pembersih", "Cleaners"), L(m, "Membebaskan RAM dan merapikan penyimpanan.", "Frees RAM and tidies storage."), x, cy, w, true, [&](float gx, float gy, float gw) {
    bool c1 = false, c2 = false;
    float h = actRow("ram", "Bersihkan RAM", "Clean RAM", "Menutup app latar yang menumpuk. App penting tidak disentuh.", "Closes piled-up background apps. Important apps are left alone.", "Bersihkan", "Clean", gx, gy, gw, true, &c1);
    h += actRow("trim", "Rapikan penyimpanan (trim)", "Tidy storage (trim)", "Memberi tahu penyimpanan blok yang tidak dipakai supaya tulis berikutnya tidak melambat.", "Tells storage which blocks are unused so later writes do not slow down.", "Mulai", "Start", gx, gy + h, gw, false, &c2);
    if (c1) m.cmd("act", "ram");
    if (c2) m.cmd("act", "trim");
    return h;
  });
  cy += groupBox("al_power", L(m, "Daya dan suhu", "Power and temperature"), L(m, "Pengisian baterai dan pemantauan suhu.", "Battery charging and temperature."), x, cy, w, true, [&](float gx, float gy, float gw) {
    float h = drawFeature(findFeat("charge"), gx, gy, gw, true, true);
    int t = m.num("temp", 0);
    float rh = 46;
    ui.rule(gx, gy + h, gx + gw, gy + h);
    ui.text(F_BOLD, L(m, "Monitor suhu", "Temperature monitor"), gx, gy + h + 8, 14, ui.th.ink);
    ui.text(F_BODY, L(m, "Suhu baterai sekarang.", "Current battery temperature."), gx, gy + h + 27, 12, ui.th.ink2);
    ui.text(F_BOLD, t > 0 ? std::to_string(t) + " \xC2\xB0" "C" : "--", gx + gw, gy + h + 9, 13, ui.th.ink, 2);
    h += rh + 2;
    h += drawFeature(findFeat("dac"), gx, gy + h, gw, true, false);
    h += drawFeature(findFeat("led"), gx, gy + h, gw, true, false);
    return h;
  });
  cy += groupBox("al_app", L(m, "Aplikasi", "Apps"), L(m, "Mengurangi beban dari app yang tidak dipakai.", "Reduces load from apps you are not using."), x, cy, w, false, [&](float gx, float gy, float gw) {
    bool c1 = false;
    std::string label = std::string(L(m, "Pilih app", "Pick apps")) + (m.frozenApps.empty() ? "" : " (" + std::to_string(m.frozenApps.size()) + ")");
    float h = rowHead(*this, ui, m, L(m, "Bekukan app latar", "Freeze background apps"), nullptr, false, L(m, "App yang kamu pilih dimatikan sementara supaya RAM dan CPU tidak terpakai.", "Apps you pick are paused so they stop using RAM and CPU."), gx, gy, gw, 130, true, true,
                      [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); });
    h = std::max(h, 46.f);
    BtnStyle bs; bs.size = 12.5f; bs.filled = true;
    c1 = ui.button(Ui::id("frzPick"), Rect(gx + gw - 124, gy + 8, 124, 30), label, bs);
    if (c1) { m.cmd("apps.request"); openPicker("freeze", L(m, "Bekukan app latar", "Freeze background apps"), L(m, "Terapkan", "Apply"), {}, false); }
    return h + 2;
  });
  return cy - y;
}

// ---------------------------------------------------------------- Umum
float App::pageUmum(float x, float y, float w) {
  float cy = y;
  cy += groupBox("um_look", L(m, "Tampilan", "Appearance"), L(m, "Bahasa, tema, dan gerak.", "Language, theme, and motion."), x, cy, w, true, [&](float gx, float gy, float gw) {
    float h = 0;
    auto chipsRow = [&](const char* key, const char* nId, const char* nEn, const char* dId, const char* dEn, const Opts& o, const std::string& cur, const char* prefKey, bool first) {
      std::string name = m.lang ? nEn : nId, desc = m.lang ? dEn : dId;
      float hh = rowHead(*this, ui, m, name, nullptr, false, desc, gx, gy + h, gw, 0, true, first, [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); });
      float ch; int k = chipRow(ui, Ui::id(key), gx, gy + h + hh, gw, o, cur, &ch);
      if (k >= 0) { m.set(std::string("pref.") + prefKey, o[k].first); m.cmd("pref", prefKey, o[k].first); if (!std::strcmp(prefKey, "lang")) { m.lang = o[k].first == "EN" ? 1 : 0; } }
      h += hh + ch + 10;
    };
    auto swRow = [&](const char* key, const char* nId, const char* nEn, const char* dId, const char* dEn, const char* prefKey, bool def) {
      std::string name = m.lang ? nEn : nId, desc = m.lang ? dEn : dId;
      float hh = rowHead(*this, ui, m, name, nullptr, false, desc, gx, gy + h, gw, 50, true, false, [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); });
      bool v = m.flag(std::string("pref.") + prefKey, def);
      if (ui.toggle(Ui::id(key), Rect(gx + gw - 46, gy + h + 10, 44, 22), &v)) { m.set(std::string("pref.") + prefKey, v ? "1" : "0"); m.cmd("pref", prefKey, v ? "1" : "0"); }
      h += std::max(hh, 46.f) + 2;
    };
    chipsRow("lang", "Bahasa", "Language", "Bahasa yang dipakai di seluruh app.", "Language used across the app.", {{"ID", "Indonesia"}, {"EN", "English"}}, m.lang ? "EN" : "ID", "lang", true);
    chipsRow("theme", "Tema", "Theme", "Terang seperti kertas, gelap seperti tinta, atau ikut sistem.", "Light like paper, dark like ink, or follow the system.",
             {{"system", L(m, "Sistem", "System")}, {"light", L(m, "Terang", "Light")}, {"dark", L(m, "Gelap", "Dark")}}, m.str("pref.theme", "system"), "theme", false);
    swRow("anim", "Animasi HSIN", "HSIN animation", "Gerak tinta dan peralihan. Mati = lebih hemat baterai dan lebih ringan di HP lemah.", "Ink motion and transitions. Off = saves battery and is lighter on weak phones.", "anim", true);
    swRow("vib", "Getar", "Vibration", "Getar ringan saat mengganti mode.", "A light buzz when you change mode.", "vib", true);
    {
      std::string name = m.lang ? "Orb size" : "Ukuran orb", desc = m.lang ? "Size of the floating orb over the screen." : "Ukuran bulatan melayang di atas layar.";
      float hh = rowHead(*this, ui, m, name, nullptr, false, desc, gx, gy + h, gw, 0, true, false, [&](const std::string& s, float xx, float yy, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy, ww, sz, c, fo, d); });
      float v = (float)m.num("pref.orb", 84);
      ui.text(F_BOLD, std::to_string((int)v) + " px", gx + gw, gy + h + 9, 13, ui.th.ink, 2);
      if (ui.slider(Ui::id("orbSz"), Rect(gx + 4, gy + h + hh + 4, std::min(gw - 70, 330.f), 14), &v, 60, 120, 4)) { m.set("pref.orb", std::to_string((int)v)); sliderDirty_ = "orb"; }
      if (!ui.down && sliderDirty_ == "orb") { sliderDirty_.clear(); m.cmd("pref", "orb", std::to_string((int)v)); }
      h += hh + 32;
    }
    return h;
  });
  return cy - y;
}

// ---------------------------------------------------------------- Info
float App::pageInfo(float x, float y, float w) {
  float cy = y;
  cy += groupBox("in_stat", L(m, "Status", "Status"), L(m, "Kondisi modul dan game.", "State of the module and games."), x, cy, w, true, [&](float gx, float gy, float gw) {
    auto info = [&](const char* nId, const char* nEn, const char* dId, const char* dEn, const std::string& val, float yy, bool first) {
      float hh = rowHead(*this, ui, m, m.lang ? nEn : nId, nullptr, false, m.lang ? dEn : dId, gx, yy, gw, 110, true, first, [&](const std::string& s, float xx, float yy2, float ww, float sz, Col c, int fo, bool d) { return para(s, xx, yy2, ww, sz, c, fo, d); });
      ui.text(F_BOLD, val, gx + gw, yy + 9, 13, ui.th.ink, 2);
      return std::max(hh, 46.f) + 2;
    };
    float h = info("Status modul", "Module status", "Modul HSIN di sistem.", "The HSIN module in the system.", m.str("module.state", L(m, "Memeriksa", "Checking")), gy, true);
    h += info("Game terdaftar", "Registered games", "Jumlah game yang dikenali.", "Number of games recognised.", std::to_string(m.games.size()), gy + h, false);
    h += info("Versi", "Version", "Versi app.", "App version.", m.str("ver", "6.0 beta"), gy + h, false);
    return h;
  });
  cy += groupBox("in_diag", L(m, "Diagnosa", "Diagnostics"), L(m, "Catatan teknis untuk mencari masalah.", "Technical notes for finding problems."), x, cy, w, false, [&](float gx, float gy, float gw) {
    bool c1 = false, c2 = false;
    float h = actRow("logexp", "Ekspor log", "Export log", "Simpan catatan modul ke folder Download untuk dikirim saat melapor masalah.", "Save module notes to the Download folder to send with a bug report.", "Ekspor", "Export", gx, gy, gw, true, &c1);
    h += actRow("caps", "Cek kemampuan HP", "Check phone abilities", "Memeriksa fitur apa saja yang didukung HP ini.", "Checks which features this phone supports.", "Periksa", "Check", gx, gy + h, gw, false, &c2);
    if (c1) m.cmd("act", "logexport");
    if (c2) m.cmd("act", "caps");
    std::string caps = m.str("caps.text");
    if (!caps.empty()) {
      std::string t; for (char ch : caps) t += ch == '|' ? '\n' : ch;
      h += para(t, gx, gy + h + 2, gw, 11, ui.th.ink, F_BODY, true) + 8;
    }
    if (!m.logLines.empty()) {
      ui.rule(gx, gy + h, gx + gw, gy + h);
      int n = (int)m.logLines.size(), from = std::max(0, n - 8);
      for (int i = from; i < n; i++) { ui.text(F_BODY, ui.fit(F_BODY, m.logLines[i], 10.5f, gw), gx, gy + h + 6 + (i - from) * 14, 10.5f, ui.th.ink2); }
      h += 12 + (n - from) * 14;
    }
    return h;
  });
  {
    float h = 96;
    Rect r(x, cy, w, h);
    ui.cv->rrect(r.x, r.y, r.w, r.h, 2, ui.th.card);
    roughBox(*cv_, r, 812, 1.6f, ui.th.ink);
    ui.text(F_DISP, L(m, "Tentang", "About"), x + 14, cy + 8, 16, ui.th.ink);
    para(L(m, "HSIN v6 beta. Hsin menyesuaikan beban sendiri; Suhsin memberi kendali penuh. Cerita singkat keduanya menyusul di versi berikutnya.", "HSIN v6 beta. Hsin adjusts the load by itself; Suhsin gives full control. Their short story follows in a later version."), x + 14, cy + 34, w - 28, 12, ui.th.ink2, F_BODY, true);
    cy += h + 10;
  }
  return cy - y;
}

// ---------------------------------------------------------------- screen
void App::drawSetting() {
  drawBg(IMG_BG_SET, Rect(L0, 0, SW - L0, SH));
  drawHeader(L(m, "Setting", "Settings"));
  bool su = m.str("mode", "hsin") == "suhsin";
  struct Sub { Icon ic; const char* id; const char* en; };
  Sub subs[6] = {{IC_STAR, "Fitur", "Features"}, {su ? IC_SUHSIN : IC_LOCK, "Suhsin", "Suhsin"}, {IC_REC, "Rekaman", "Recording"}, {IC_TOOL, "Alat", "Tools"}, {IC_SETTING, "Umum", "General"}, {IC_INFO, "Info", "Info"}};
  float gap = 8, bw = (CR - CL - 5 * gap - 66) / 6, by = 62;
  for (int i = 0; i < 6; i++) {
    Rect r(CL + i * (bw + gap), by, bw, 44);
    BtnStyle st; st.filled = sub_ == i; st.iconId = subs[i].ic; st.size = 12.5f; st.dashed = i == 1 && !su; st.thick = i == 1 && su;
    if (ui.button(Ui::id("subtab", i), r, m.lang ? subs[i].en : subs[i].id, st)) { gotoSub(i); }
  }
  Rect view(CL - 6, 114, CR - CL + 12, SH - 114 - 4);
  // transition
  float alpha = 1, slide = 0;
  double e = ui.now - subT0_;
  if (e < .32) {
    ui.busy = true;
    if (e < .09) alpha = 1.f - (float)(e / .09);
    else { if (subShown_ != sub_) { subShown_ = sub_; setScroll_ = Scroll(); } float q = (float)((e - .09) / .23); alpha = q; slide = 14 * (1 - easeOut(q)); }
  } else subShown_ = sub_;
  ui.scrollBegin(Ui::id("setScroll"), setScroll_, view);
  visTop_ = view.y + setScroll_.off - 8; visBot_ = view.y + view.h + setScroll_.off + 8;
  cv_->setAlpha(alpha);
  cv_->pushT(slide, 0);
  float x = CL, w = CR - CL - 8, y = view.y + 4, h = 0;
  switch (subShown_) {
    case 0: h = pageFitur(0, x, y, w); break;
    case 1: h = su ? pageFitur(1, x, y, w) : lockBox(x, y, w); break;
    case 2: h = pageRekam(x, y, w); break;
    case 3: h = pageAlat(x, y, w); break;
    case 4: h = pageUmum(x, y, w); break;
    default: h = pageInfo(x, y, w); break;
  }
  cv_->popT();
  cv_->setAlpha(1);
  ui.scrollEnd(setScroll_, view, h + 12);
}

}  // namespace hs
