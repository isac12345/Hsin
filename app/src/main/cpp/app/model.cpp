#include "model.h"
#include <sstream>

namespace hs {

const std::string Model::empty_;

static std::vector<std::string> split(const std::string& s, char d) {
  std::vector<std::string> o; std::string cur;
  for (char c : s) { if (c == d) { o.push_back(cur); cur.clear(); } else cur += c; }
  o.push_back(cur);
  return o;
}
static std::string at(const std::vector<std::string>& v, size_t i) { return i < v.size() ? v[i] : std::string(); }

// Protocol (one command per line):
//   set <key> <value...>      store a value
//   games.clear / game <pkg>|<label>|<mode>|<fps>|<res>|<cpu>|<render>|<dex 0/1>
//   apps.clear / app <pkg>|<label>          frozen.clear / frozen <pkg>|<label>
//   hist.clear / hist <name>|<avg>|<low>|<dur>|<jank>|<temp>
//   vid.clear / vid <id>|<name>|<info>
//   fps <n>                   append to the live FPS graph
//   log.clear / log <text>
//   toast <text> / toastbad <text>
void Model::push(const std::string& text) {
  std::istringstream in(text);
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty()) continue;
    size_t sp = line.find(' ');
    std::string c = line.substr(0, sp), r = sp == std::string::npos ? "" : line.substr(sp + 1);
    if (c == "set") {
      size_t s2 = r.find(' ');
      std::string k = r.substr(0, s2), v = s2 == std::string::npos ? "" : r.substr(s2 + 1);
      kv[k] = v;
      if (k == "lang") lang = (v == "EN" || v == "1" || v == "en") ? 1 : 0;
    } else if (c == "games.clear") games.clear();
    else if (c == "game") {
      auto f = split(r, '|'); GameInfo g;
      g.pkg = at(f, 0); g.label = at(f, 1); g.mode = at(f, 2) == "suhsin" ? "suhsin" : "hsin";
      g.fps = std::atoi(at(f, 3).c_str()); g.res = std::atoi(at(f, 4).c_str()); g.cpu = std::atoi(at(f, 5).c_str());
      g.render = at(f, 6).empty() ? "default" : at(f, 6); g.dex = at(f, 7) == "1";
      if (g.fps <= 0) g.fps = 60;
      if (g.res <= 0) g.res = 100;
      if (g.cpu <= 0) g.cpu = 100;
      games.push_back(g);
    } else if (c == "apps.clear") apps.clear();
    else if (c == "app") { auto f = split(r, '|'); apps.push_back({at(f, 0), at(f, 1)}); }
    else if (c == "frozen.clear") frozenApps.clear();
    else if (c == "frozen") { auto f = split(r, '|'); frozenApps.push_back({at(f, 0), at(f, 1)}); }
    else if (c == "hist.clear") hist.clear();
    else if (c == "hist") {
      auto f = split(r, '|'); HistEntry h; h.name = at(f, 0); h.avg = std::atoi(at(f, 1).c_str()); h.low = std::atoi(at(f, 2).c_str());
      h.dur = at(f, 3); h.jank = std::atoi(at(f, 4).c_str()); h.temp = std::atoi(at(f, 5).c_str()); hist.push_back(h);
    } else if (c == "vid.clear") vids.clear();
    else if (c == "vid") { auto f = split(r, '|'); vids.push_back({at(f, 0), at(f, 1), at(f, 2)}); }
    else if (c == "fps") { fpsLive.push_back(std::atoi(r.c_str())); if (fpsLive.size() > 60) fpsLive.erase(fpsLive.begin()); }
    else if (c == "log.clear") logLines.clear();
    else if (c == "log") { logLines.push_back(r); if (logLines.size() > 200) logLines.erase(logLines.begin()); }
    else if (c == "toast") toast(r, false);
    else if (c == "toastbad") toast(r, true);
  }
}

}  // namespace hs
