// Host harness: renders screens with the software canvas and drives taps to check commands.
#include "../engine/soft_canvas.h"
#include "../app/app.h"
#include <fstream>
#include <cstdio>
#include <cstring>
using namespace hs;

static std::vector<uint8_t> rd(const std::string& p) { std::ifstream f(p, std::ios::binary); return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), {}); }
static std::string root, imgDir, outDir;
static int W = 1200, H = 540, fails = 0, checks = 0;
static double T = 1.0;
static float SC() { return H / 360.f; }

#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; printf("FAIL: %s\n", msg); } else printf("ok:   %s\n", msg); } while (0)

struct Rig {
  SoftCanvas cv; Fonts fn{&cv}; App* app; std::vector<std::vector<uint8_t>> keep;
  Rig() {
    for (const char* f : {"disp", "body", "bold"}) { keep.push_back(rd(root + "/fonts/" + f + ".ttf")); fn.add(keep.back().data(), keep.back().size()); }
    app = new App(&cv, &fn);
    const char* names[] = {"bgMode", "bgGame", "bgSet", "av0", "av1", "av2", "av3", "avS"};
    for (int i = 0; i < 8; i++) {
      std::ifstream sz(imgDir + "/" + names[i] + ".txt"); int w = 0, h = 0; if (!(sz >> w >> h)) continue;
      auto d = rd(imgDir + "/" + names[i] + ".rgba"); app->setImage(i, w, h, d.data());
    }
  }
  void frames(int n) { for (int i = 0; i < n; i++) { T += 0.0167; app->frame(T, W, H); } }
  void settle() { frames(40); }
  void shot(const char* name) { frames(2); cv.savePng((outDir + "/" + name + ".png").c_str()); }
  void tap(float sx, float sy) {  // stage coords (scale 2)
    app->touch(0, sx * SC(), sy * SC(), T); frames(2); app->touch(2, sx * SC(), sy * SC(), T); frames(3);
  }
  void drag(float x0, float y0, float x1, float y1, int steps = 8) {
    app->touch(0, x0 * SC(), y0 * SC(), T); frames(1);
    for (int i = 1; i <= steps; i++) { app->touch(1, (x0 + (x1 - x0) * i / steps) * SC(), (y0 + (y1 - y0) * i / steps) * SC(), T); frames(1); }
    app->touch(2, x1 * SC(), y1 * SC(), T); frames(1);
  }
  std::vector<std::string> cmds() { return app->takeCmds(); }
};

static bool has(const std::vector<std::string>& v, const std::string& s) { for (auto& x : v) if (x.find(s) != std::string::npos) return true; return false; }

#include "seed.h"

int main(int, char** argv) {
  root = argv[1]; imgDir = argv[2]; outDir = argv[3];
  Rig r; App& a = *r.app;
  seed(a); r.settle();
  r.shot("01_mode_hsin");
  r.tap(600, 120); r.settle();
  CHECK(has(r.cmds(), "mode\tsuhsin"), "tap Suhsin card sends mode command");
  r.shot("02_mode_suhsin");
  r.tap(598, 187); r.frames(30);
  CHECK(has(r.cmds(), "feat\tthermaloff\t1"), "thermal toggle sends feat thermaloff 1");
  r.tap(250, 120); r.settle(); r.cmds();
  r.tap(38, 176); r.settle(); CHECK(a.tab == 1, "rail Game tab opens");
  r.shot("03_game");
  r.tap(240, 274); r.settle(); printf("sheetKind via tab=%d\n", a.tab);
  r.shot("04_sheet_suhsin_game");
  r.tap(176, 206); r.frames(6);
  CHECK(has(r.cmds(), "game.set\tcom.mho\tfps\t45"), "FPS chip sends game.set fps 45");
  r.tap(415, 206); r.frames(6);
  CHECK(has(r.cmds(), "game.set\tcom.mho\tres\t85"), "resolution chip sends game.set res 85");
  r.drag(640, 213, 700, 213); r.frames(4); r.drag(700, 213, 647, 213); r.frames(10);
  { auto c = r.cmds(); CHECK(has(c, "game.set\tcom.mho\tcpu\t"), "CPU slider sends game.set cpu on release"); }
  r.drag(400, 320, 400, 200); r.frames(30);
  r.shot("05_sheet_scrolled");
  r.tap(760, 125); r.settle();
  r.tap(428, 274); r.settle();
  r.shot("06_sheet_hsin_game");
  r.tap(760, 125); r.settle();
  r.tap(263, 34); r.settle();
  r.shot("07_dex_picker");
  r.tap(116, 200); r.frames(4);
  r.tap(679, 335); r.frames(6);
  CHECK(has(r.cmds(), "dex\tspeed-profile\tcom.mho"), "dex picker sends dex command with selected game");
  r.tap(759, 105); r.settle();
  r.tap(38, 250); r.settle(); CHECK(a.tab == 2, "rail Setting tab opens");
  r.shot("08_set_fitur");
  const float sx[6] = {146, 251, 355, 460, 565, 669};
  const char* nm[6] = {"09_set_fitur2", "10_set_suhsin_locked", "11_set_rekam", "12_set_alat", "13_set_umum", "14_set_info"};
  a.m.push("set mode hsin\n");
  for (int i = 1; i < 6; i++) { r.tap(sx[i], 84); r.settle(); r.shot(nm[i]); }
  a.m.push("set mode suhsin\n");
  r.tap(sx[1], 84); r.settle(); r.shot("15_set_suhsin");
  printf("%d checks, %d failed\n", checks, fails);
  return fails ? 1 : 0;
}
