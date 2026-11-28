// OpenGL ES 3.0 backend: one batched shader that evaluates the same SDF maths as SoftCanvas.
#pragma once
#include "canvas_base.h"
#include <GLES3/gl3.h>

namespace hs {

class GlCanvas : public CanvasBase {
 public:
  ~GlCanvas() override { release(); }
  bool init();     // compile shaders, create buffers. Call with a current context.
  void release();  // free GL objects (context still current) or forget them (context lost)
  void lost();     // context lost: forget everything without deleting
  void begin(int pw, int ph, Col clear) override;
  void end() override { flush(); }
  void rrect(float x, float y, float w, float h, float rad, Col c, float stroke = 0) override;
  void line(float x0, float y0, float x1, float y1, float w, Col c) override;
  void quad(int tex, Rect dst, Rect src, Col tint, float rad = -1) override;
  int texCreate(int w, int h, TexFmt f, const uint8_t* data) override;
  void texUpdate(int id, int x, int y, int w, int h, const uint8_t* data, int stridePx) override;
  void texDestroy(int id) override;
  void texSize(int id, int* w, int* h) override;
  void readPixels(std::vector<uint8_t>* rgba);  // for tests (bottom-up flipped to top-down)

 protected:
  void onClip() override { flush(); applyScissor(); }

 private:
  struct Tex { GLuint id = 0; int w = 0, h = 0; TexFmt f = TEX_RGBA; };
  std::vector<Tex> tex_;
  GLuint prog_ = 0, vao_ = 0, vbo_ = 0, ibo_ = 0;
  GLint uView_ = -1, uTex_ = -1;
  std::vector<float> v_;
  int curTex_ = 0, quads_ = 0;
  static const int kMaxQuads = 4096;
  void flush();
  void applyScissor();
  void pushQuad(const float* corners /*x0,y0,x1,y1*/, const float* loc, const float* uv, Col c, const float* p, float mode, float q1, int tex);
};

}  // namespace hs
