// Data the UI draws, pushed from Kotlin as text lines; commands go back as text lines.
#pragma once
#include <string>
#include <vector>
#include <map>
#include <functional>
#include <cstdlib>

namespace hs {

struct GameInfo {
  std::string pkg, label, mode = "hsin", render = "default";
  int fps = 60, res = 100, cpu = 100;
  bool dex = false;
};
struct AppEntry { std::string pkg, label; };
struct HistEntry { std::string name; int avg = 0, low = 0, jank = 0, temp = 0; std::string dur; };
struct VidEntry { std::string id, name, info; };

struct Model {
  // language 0 = Indonesia, 1 = English
  int lang = 0;
  std::map<std::string, std::string> kv;
  std::vector<GameInfo> games;
  std::vector<AppEntry> apps, frozenApps;
  std::vector<HistEntry> hist;
  std::vector<VidEntry> vids;
  std::vector<int> fpsLive;
  std::vector<std::string> logLines;
  std::string toastMsg; bool toastNew = false, toastBad = false;
  std::vector<std::string> out;  // commands waiting for Kotlin

  const std::string& str(const std::string& k, const std::string& d = empty_) const {
    auto it = kv.find(k); return it == kv.end() ? d : it->second;
  }
  int num(const std::string& k, int d = 0) const {
    auto it = kv.find(k); if (it == kv.end() || it->second.empty()) return d;
    return std::atoi(it->second.c_str());
  }
  bool flag(const std::string& k, bool d = false) const {
    auto it = kv.find(k); if (it == kv.end() || it->second.empty()) return d;
    return it->second == "1" || it->second == "true";
  }
  // capability: key "cap.<name>"; unknown -> d
  bool cap(const std::string& name, bool d) const { return flag("cap." + name, d); }

  GameInfo* game(const std::string& pkg) { for (auto& g : games) if (g.pkg == pkg) return &g; return nullptr; }

  void push(const std::string& text);                       // parse lines from Kotlin
  void cmd(const std::string& c) { out.push_back(c); }
  void cmd(const std::string& c, const std::string& a) { out.push_back(c + "\t" + a); }
  void cmd(const std::string& c, const std::string& a, const std::string& b) { out.push_back(c + "\t" + a + "\t" + b); }
  void cmd(const std::string& c, const std::string& a, const std::string& b, const std::string& d) { out.push_back(c + "\t" + a + "\t" + b + "\t" + d); }
  void set(const std::string& k, const std::string& v) { kv[k] = v; }
  void toast(const std::string& m, bool bad = false) { toastMsg = m; toastNew = true; toastBad = bad; }

 private:
  static const std::string empty_;
};

// "id text" / "english text" selection helper.
inline const char* L(const Model& m, const char* id, const char* en) { return m.lang == 1 ? en : id; }

}  // namespace hs
