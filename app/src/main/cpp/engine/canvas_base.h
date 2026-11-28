// Shared transform + clip stack for both backends.
#pragma once
#include "gfx.h"

namespace hs {

class CanvasBase : public Canvas {
 public:
  void setBase(float tx, float ty, float s) override {
    baseTx_ = tx; baseTy_ = ty; baseS_ = s;
    ctx_ = tx; cty_ = ty; cs_ = s;
    tstack_.clear(); cstack_.clear();
    clipPx_ = Rect(0, 0, (float)pw_, (float)ph_);
    syncClip();
  }
  void pushT(float dx, float dy, float scale = 1.f) override {
    tstack_.push_back({ctx_, cty_, cs_});
    ctx_ += dx * cs_; cty_ += dy * cs_; cs_ *= scale;
  }
  void popT() override {
    if (tstack_.empty()) return;
    auto t = tstack_.back(); tstack_.pop_back();
    ctx_ = t[0]; cty_ = t[1]; cs_ = t[2];
  }
  void pushClip(Rect r) override {
    cstack_.push_back(clipPx_);
    Rect p(r.x * cs_ + ctx_, r.y * cs_ + cty_, r.w * cs_, r.h * cs_);
    clipPx_ = clipPx_.inter(p);
    syncClip();
  }
  void popClip() override {
    if (cstack_.empty()) return;
    clipPx_ = cstack_.back(); cstack_.pop_back();
    syncClip();
  }

 protected:
  struct T3 { float v[3]; float operator[](int i) const { return v[i]; } };
  std::vector<T3> tstack_;
  std::vector<Rect> cstack_;
  Rect clipPx_;
  virtual void onClip() {}
  void syncClip() {
    clipStage_ = Rect((clipPx_.x - baseTx_) / baseS_, (clipPx_.y - baseTy_) / baseS_, clipPx_.w / baseS_, clipPx_.h / baseS_);
    onClip();
  }
};

}  // namespace hs
