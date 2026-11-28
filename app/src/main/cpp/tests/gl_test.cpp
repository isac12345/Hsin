// Runs the real GlCanvas through Mesa software EGL and compares against SoftCanvas.
#include "../engine/gl_canvas.h"
#include "../engine/soft_canvas.h"
#include "../app/app.h"
#include "seed.h"
#include <EGL/egl.h>
#include <fstream>
#include <cstdio>
#include "../third_party/stb_image_write.h"
using namespace hs;

static std::vector<uint8_t> rd(const std::string& p) { std::ifstream f(p, std::ios::binary); return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), {}); }

struct Scene {
  Canvas* cv; Fonts fn; App app; std::vector<std::vector<uint8_t>> keep;
  Scene(Canvas* c, const std::string& fonts, const std::string& img) : cv(c), fn(c), app(c, &fn) {
    for (const char* f : {"disp", "body", "bold"}) { keep.push_back(rd(fonts + "/" + f + ".ttf")); fn.add(keep.back().data(), keep.back().size()); }
    const char* names[] = {"bgMode", "bgGame", "bgSet", "av0", "av1", "av2", "av3", "avS"};
    for (int i = 0; i < 8; i++) {
      std::ifstream sz(img + "/" + names[i] + ".txt"); int w = 0, h = 0; if (!(sz >> w >> h)) continue;
      auto d = rd(img + "/" + names[i] + ".rgba"); app.setImage(i, w, h, d.data());
    }
    seed(app);
  }
};

int main(int, char** argv) {
  std::string fonts = argv[1], img = argv[2], out = argv[3];
  EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  EGLint maj, min;
  if (!eglInitialize(dpy, &maj, &min)) { std::printf("EGL init failed\n"); return 2; }
  eglBindAPI(EGL_OPENGL_ES_API);
  const EGLint ca[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
  EGLConfig cfg; EGLint n = 0;
  if (!eglChooseConfig(dpy, ca, &cfg, 1, &n) || !n) { std::printf("no config\n"); return 2; }
  const int W = 1200, H = 540;
  const EGLint pb[] = {EGL_WIDTH, W, EGL_HEIGHT, H, EGL_NONE};
  EGLSurface sf = eglCreatePbufferSurface(dpy, cfg, pb);
  const EGLint cx[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, cx);
  if (!eglMakeCurrent(dpy, sf, sf, ctx)) { std::printf("make current failed\n"); return 2; }
  std::printf("GL: %s\n", (const char*)glGetString(GL_RENDERER));
  GlCanvas gl; if (!gl.init()) { std::printf("GL init failed\n"); return 3; }
  SoftCanvas soft;
  Scene sg(&gl, fonts, img), ss(&soft, fonts, img);
  struct Step { const char* name; int tx, ty; };
  double T = 1.0;
  auto frames = [&](Scene& s, int n) { for (int i = 0; i < n; i++) { T += 0.0167; s.app.frame(T, W, H); } };
  auto both = [&](int n) { double t0 = T; frames(sg, n); double t1 = T; T = t0; frames(ss, n); (void)t1; };
  auto tap = [&](float x, float y) {
    float k = H / 360.f;
    sg.app.touch(0, x * k, y * k, T); ss.app.touch(0, x * k, y * k, T); both(2);
    sg.app.touch(2, x * k, y * k, T); ss.app.touch(2, x * k, y * k, T); both(3);
  };
  both(40);
  int bad = 0;
  auto cmp = [&](const char* name) {
    both(2);
    std::vector<uint8_t> a; gl.readPixels(&a);
    std::vector<uint8_t> b((size_t)W * H * 4);
    // soft canvas buffer is premultiplied float
    // (re-render soft last frame already done in both())
    const auto& px = soft.pixels();
    double sum = 0; long big = 0;
    for (size_t i = 0; i < (size_t)W * H; i++) for (int k = 0; k < 3; k++) {
      float v = px[i * 4 + k]; v = v < 0 ? 0 : (v > 1 ? 1 : v);
      int sv = (int)std::lround(v * 255), gv = a[i * 4 + k];
      b[i * 4 + k] = (uint8_t)sv; b[i * 4 + 3] = 255;
      int d = std::abs(sv - gv); sum += d; if (d > 40) big++;
    }
    double mean = sum / ((double)W * H * 3);
    std::printf("%-14s mean abs diff %.3f  pixels>40: %ld (%.3f%%)\n", name, mean, big, 100.0 * big / ((double)W * H));
    std::string p = out + "/gl_" + name + ".png";
    for (size_t i = 0; i < (size_t)W * H; i++) a[i * 4 + 3] = 255;
    stbi_write_png(p.c_str(), W, H, 4, a.data(), W * 4);
    if (mean > 2.0) bad++;
  };
  cmp("mode");
  tap(38, 176); both(40); cmp("game");
  tap(240, 274); both(40); cmp("sheet");
  tap(760, 125); both(30);
  tap(38, 250); both(40); cmp("setting");
  tap(355, 84); both(40); cmp("rekam");
  std::printf("%s\n", bad ? "GL MISMATCH" : "GL matches software reference");
  return bad ? 1 : 0;
}
