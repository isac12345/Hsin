// Small composite widgets shared by screens.
#pragma once
#include "../engine/ui.h"
#include <utility>

namespace hs {

using Opts = std::vector<std::pair<std::string, std::string>>;  // value, label

// Wrapping row of chips. Returns clicked index or -1. outH receives total height.
inline int chipRow(Ui& ui, uint32_t base, float x, float y, float maxW, const Opts& o, const std::string& cur, float* outH,
                   bool enabled = true, const std::vector<bool>* itemOk = nullptr, float h = 28, float size = 12.5f, bool draw = true) {
  float cx = x, cy = y;
  int hit = -1;
  for (size_t i = 0; i < o.size(); i++) {
    float w = std::max(46.f, ui.tw_(F_BOLD, o[i].second, size) + 22);
    if (cx + w > x + maxW && cx > x) { cx = x; cy += h + 6; }
    if (!draw) { cx += w + 7; continue; }
    bool ok = enabled && (!itemOk || (*itemOk)[i]);
    bool prevBlock = ui.blockInput;
    if (!ok) { ui.blockInput = true; ui.cv->setAlpha(.45f); }
    if (ui.chip(base + (uint32_t)i * 131u, Rect(cx, cy, w, h), o[i].second, o[i].first == cur, size) && ok) hit = (int)i;
    if (!ok) { ui.blockInput = prevBlock; ui.cv->setAlpha(1.f); }
    cx += w + 7;
  }
  if (outH) *outH = cy + h - y;
  return hit;
}

inline Opts mkOpts(std::initializer_list<const char*> vals) {
  Opts o; for (auto v : vals) o.push_back({v, v}); return o;
}

}  // namespace hs
