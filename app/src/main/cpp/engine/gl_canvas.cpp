#include "gl_canvas.h"
#include <cstdio>
#include <cstring>
#include <algorithm>

namespace hs {

static const char* kVS = R"(#version 300 es
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aUv;
layout(location=2) in vec2 aLoc;
layout(location=3) in vec4 aCol;
layout(location=4) in vec4 aP;
layout(location=5) in vec2 aQ;
uniform vec2 uView;
out vec2 vUv; out vec2 vLoc; out vec4 vCol; out vec4 vP; out vec2 vQ;
void main() {
  gl_Position = vec4(aPos.x * uView.x - 1.0, 1.0 - aPos.y * uView.y, 0.0, 1.0);
  vUv = aUv; vLoc = aLoc; vCol = aCol; vP = aP; vQ = aQ;
}
)";

static const char* kFS = R"(#version 300 es
precision highp float;
in vec2 vUv; in vec2 vLoc; in vec4 vCol; in vec4 vP; in vec2 vQ;
uniform sampler2D uTex;
out vec4 oCol;
float sdr(vec2 p, vec2 h, float r) {
  vec2 q = abs(p) - h;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
void main() {
  float m = vQ.x;
  vec4 c;
  if (m < 0.5) {
    float d = sdr(vLoc, vP.xy, vP.z);
    float a = clamp(0.5 - d, 0.0, 1.0);
    if (vP.w > 0.0) a *= clamp(d + vP.w + 0.5, 0.0, 1.0);
    a *= vCol.a;
    c = vec4(vCol.rgb * a, a);
  } else if (m < 1.5) {
    vec2 pa = vLoc - vP.xy, ba = vP.zw - vP.xy;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    float d = length(pa - ba * h) - vQ.y;
    float a = clamp(0.5 - d, 0.0, 1.0) * vCol.a;
    c = vec4(vCol.rgb * a, a);
  } else {
    vec4 t = texture(uTex, vUv);
    float cov = 1.0;
    if (vP.w > 0.5) cov = clamp(0.5 - sdr(vLoc, vP.xy, vP.z), 0.0, 1.0);
    if (m < 2.5) {
      c = vec4(t.rgb * vCol.rgb * vCol.a, t.a * vCol.a) * cov;
    } else {
      float a = t.r * vCol.a * cov;
      c = vec4(vCol.rgb * a, a);
    }
  }
  oCol = c;
}
)";

static GLuint compile(GLenum type, const char* src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, nullptr);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) { char log[1024]; glGetShaderInfoLog(s, sizeof log, nullptr, log); std::fprintf(stderr, "HSIN shader: %s\n", log); glDeleteShader(s); return 0; }
  return s;
}

bool GlCanvas::init() {
  GLuint vs = compile(GL_VERTEX_SHADER, kVS), fs = compile(GL_FRAGMENT_SHADER, kFS);
  if (!vs || !fs) return false;
  prog_ = glCreateProgram();
  glAttachShader(prog_, vs); glAttachShader(prog_, fs);
  glLinkProgram(prog_);
  glDeleteShader(vs); glDeleteShader(fs);
  GLint ok = 0;
  glGetProgramiv(prog_, GL_LINK_STATUS, &ok);
  if (!ok) { char log[1024]; glGetProgramInfoLog(prog_, sizeof log, nullptr, log); std::fprintf(stderr, "HSIN link: %s\n", log); return false; }
  uView_ = glGetUniformLocation(prog_, "uView");
  uTex_ = glGetUniformLocation(prog_, "uTex");
  glGenVertexArrays(1, &vao_);
  glGenBuffers(1, &vbo_);
  glGenBuffers(1, &ibo_);
  glBindVertexArray(vao_);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)kMaxQuads * 4 * 16 * sizeof(float), nullptr, GL_STREAM_DRAW);
  const GLsizei stride = 16 * sizeof(float);
  const int sizes[6] = {2, 2, 2, 4, 4, 2};
  size_t off = 0;
  for (int i = 0; i < 6; i++) {
    glEnableVertexAttribArray(i);
    glVertexAttribPointer(i, sizes[i], GL_FLOAT, GL_FALSE, stride, (const void*)off);
    off += sizes[i] * sizeof(float);
  }
  std::vector<uint16_t> idx((size_t)kMaxQuads * 6);
  for (int q = 0; q < kMaxQuads; q++) {
    uint16_t b = (uint16_t)(q * 4);
    uint16_t* p = &idx[(size_t)q * 6];
    p[0] = b; p[1] = b + 1; p[2] = b + 2; p[3] = b + 2; p[4] = b + 1; p[5] = b + 3;
  }
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo_);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)idx.size() * 2, idx.data(), GL_STATIC_DRAW);
  glBindVertexArray(0);
  v_.reserve((size_t)kMaxQuads * 4 * 16);
  return true;
}

void GlCanvas::lost() {
  prog_ = vao_ = vbo_ = ibo_ = 0;
  tex_.clear(); v_.clear(); quads_ = 0; curTex_ = 0;
}

void GlCanvas::release() {
  if (prog_) {
    for (auto& t : tex_) if (t.id) glDeleteTextures(1, &t.id);
    glDeleteBuffers(1, &vbo_); glDeleteBuffers(1, &ibo_); glDeleteVertexArrays(1, &vao_); glDeleteProgram(prog_);
  }
  lost();
}

void GlCanvas::applyScissor() {
  int x = (int)std::floor(clipPx_.x), y = (int)std::floor(clipPx_.y);
  int x1 = (int)std::ceil(clipPx_.x + clipPx_.w), y1 = (int)std::ceil(clipPx_.y + clipPx_.h);
  x = std::max(0, x); y = std::max(0, y); x1 = std::min(pw_, x1); y1 = std::min(ph_, y1);
  glScissor(x, ph_ - y1, std::max(0, x1 - x), std::max(0, y1 - y));
}

void GlCanvas::begin(int pw, int ph, Col c) {
  pw_ = pw; ph_ = ph; drawCalls = 0; galpha_ = 1.f;
  glViewport(0, 0, pw, ph);
  glDisable(GL_SCISSOR_TEST);
  glClearColor(c.r * c.a, c.g * c.a, c.b * c.a, c.a);
  glClear(GL_COLOR_BUFFER_BIT);
  glEnable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_DEPTH_TEST); glDisable(GL_CULL_FACE);
  v_.clear(); quads_ = 0; curTex_ = 0;
  setBase(0, 0, 1);
}

void GlCanvas::flush() {
  if (!quads_ || !prog_) { v_.clear(); quads_ = 0; return; }
  glUseProgram(prog_);
  glUniform2f(uView_, 2.f / pw_, 2.f / ph_);
  glUniform1i(uTex_, 0);
  glActiveTexture(GL_TEXTURE0);
  if (curTex_ >= 1 && curTex_ <= (int)tex_.size()) glBindTexture(GL_TEXTURE_2D, tex_[curTex_ - 1].id);
  glBindVertexArray(vao_);
  glBindBuffer(GL_ARRAY_BUFFER, vbo_);
  glBufferSubData(GL_ARRAY_BUFFER, 0, (GLsizeiptr)v_.size() * sizeof(float), v_.data());
  glDrawElements(GL_TRIANGLES, quads_ * 6, GL_UNSIGNED_SHORT, nullptr);
  drawCalls++;
  v_.clear(); quads_ = 0;
}

void GlCanvas::pushQuad(const float* b, const float* loc, const float* uv, Col c, const float* p, float mode, float q1, int tex) {
  if (tex != curTex_ && quads_) flush();
  curTex_ = tex;
  if (quads_ >= kMaxQuads) flush();
  // corners: (x0,y0) (x1,y0) (x0,y1) (x1,y1)
  for (int k = 0; k < 4; k++) {
    float fx = (k & 1) ? 1.f : 0.f, fy = (k & 2) ? 1.f : 0.f;
    float px = b[0] + (b[2] - b[0]) * fx, py = b[1] + (b[3] - b[1]) * fy;
    float lx, ly;
    if (mode == 1.f) { lx = px; ly = py; }  // line: physical position
    else { lx = loc[0] + (loc[2] - loc[0]) * fx; ly = loc[1] + (loc[3] - loc[1]) * fy; }
    float u = uv ? uv[0] + (uv[2] - uv[0]) * fx : 0, vv = uv ? uv[1] + (uv[3] - uv[1]) * fy : 0;
    float vert[16] = {px, py, u, vv, lx, ly, c.r, c.g, c.b, c.a, p[0], p[1], p[2], p[3], mode, q1};
    v_.insert(v_.end(), vert, vert + 16);
  }
  quads_++;
}

void GlCanvas::rrect(float x, float y, float w, float h, float rad, Col c, float stroke) {
  float s = cs_;
  float px = x * s + ctx_, py = y * s + cty_, pwid = w * s, phei = h * s;
  if (px + pwid < clipPx_.x - 1 || py + phei < clipPx_.y - 1 || px > clipPx_.x + clipPx_.w + 1 || py > clipPx_.y + clipPx_.h + 1) return;
  float r = std::fmin(rad * s, std::fmin(pwid, phei) * .5f), sw = stroke * s;
  float b[4] = {px - 1, py - 1, px + pwid + 1, py + phei + 1};
  float hw = pwid * .5f, hh = phei * .5f;
  float loc[4] = {-hw - 1, -hh - 1, hw + 1, hh + 1};
  float p[4] = {hw - r, hh - r, r, sw};
  c.a *= galpha_;
  pushQuad(b, loc, nullptr, c, p, 0.f, 0.f, 0);
}

void GlCanvas::line(float ax, float ay, float bx, float by, float w, Col c) {
  float s = cs_;
  float x0 = ax * s + ctx_, y0 = ay * s + cty_, x1 = bx * s + ctx_, y1 = by * s + cty_, hw = w * s * .5f;
  float minx = std::fmin(x0, x1) - hw - 1, miny = std::fmin(y0, y1) - hw - 1, maxx = std::fmax(x0, x1) + hw + 1, maxy = std::fmax(y0, y1) + hw + 1;
  if (maxx < clipPx_.x || maxy < clipPx_.y || minx > clipPx_.x + clipPx_.w || miny > clipPx_.y + clipPx_.h) return;
  float b[4] = {minx, miny, maxx, maxy};
  float p[4] = {x0, y0, x1, y1};
  c.a *= galpha_;
  pushQuad(b, nullptr, nullptr, c, p, 1.f, hw, 0);
}

void GlCanvas::quad(int id, Rect dst, Rect src, Col tint, float rad) {
  if (id < 1 || id > (int)tex_.size() || !tex_[id - 1].id) return;
  const Tex& t = tex_[id - 1];
  float s = cs_;
  float dx = dst.x * s + ctx_, dy = dst.y * s + cty_, dw = dst.w * s, dh = dst.h * s;
  if (dw <= 0 || dh <= 0) return;
  if (dx + dw < clipPx_.x || dy + dh < clipPx_.y || dx > clipPx_.x + clipPx_.w || dy > clipPx_.y + clipPx_.h) return;
  float b[4] = {dx, dy, dx + dw, dy + dh};
  float uv[4] = {src.x / t.w, src.y / t.h, (src.x + src.w) / t.w, (src.y + src.h) / t.h};
  float hw = dw * .5f, hh = dh * .5f, rr = rad >= 0 ? std::fmin(rad * s, std::fmin(hw, hh)) : 0.f;
  float loc[4] = {-hw, -hh, hw, hh};
  float p[4] = {hw - rr, hh - rr, rr, rad >= 0 ? 1.f : 0.f};
  tint.a *= galpha_;
  pushQuad(b, loc, uv, tint, p, t.f == TEX_RGBA ? 2.f : 3.f, 0.f, id);
}

int GlCanvas::texCreate(int w, int h, TexFmt f, const uint8_t* data) {
  Tex t; t.w = w; t.h = h; t.f = f;
  glGenTextures(1, &t.id);
  glBindTexture(GL_TEXTURE_2D, t.id);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
  if (f == TEX_RGBA) glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
  else glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, w, h, 0, GL_RED, GL_UNSIGNED_BYTE, data);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  for (size_t i = 0; i < tex_.size(); i++) if (!tex_[i].id) { tex_[i] = t; return (int)i + 1; }
  tex_.push_back(t);
  return (int)tex_.size();
}

void GlCanvas::texUpdate(int id, int x, int y, int w, int h, const uint8_t* data, int stride) {
  if (id < 1 || id > (int)tex_.size() || !tex_[id - 1].id) return;
  flush();  // pending quads may sample this texture
  Tex& t = tex_[id - 1];
  glBindTexture(GL_TEXTURE_2D, t.id);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, stride);
  glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, t.f == TEX_RGBA ? GL_RGBA : GL_RED, GL_UNSIGNED_BYTE, data);
  glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
}

void GlCanvas::texDestroy(int id) {
  if (id < 1 || id > (int)tex_.size() || !tex_[id - 1].id) return;
  flush();
  glDeleteTextures(1, &tex_[id - 1].id);
  tex_[id - 1] = Tex();
}

void GlCanvas::texSize(int id, int* w, int* h) {
  if (id < 1 || id > (int)tex_.size()) { *w = *h = 0; return; }
  *w = tex_[id - 1].w; *h = tex_[id - 1].h;
}

void GlCanvas::readPixels(std::vector<uint8_t>* out) {
  flush();
  glDisable(GL_SCISSOR_TEST);
  std::vector<uint8_t> raw((size_t)pw_ * ph_ * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, pw_, ph_, GL_RGBA, GL_UNSIGNED_BYTE, raw.data());
  out->assign(raw.size(), 0);
  for (int y = 0; y < ph_; y++) std::memcpy(&(*out)[(size_t)y * pw_ * 4], &raw[(size_t)(ph_ - 1 - y) * pw_ * 4], (size_t)pw_ * 4);
  glEnable(GL_SCISSOR_TEST);
}

}  // namespace hs
