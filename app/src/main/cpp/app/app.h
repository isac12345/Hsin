// HSIN app UI: three tabs (Mode, Game, Setting) drawn entirely by the engine.
#pragma once
#include "../engine/ui.h"
#include "model.h"
#include <memory>
#include <functional>
#include <cstring>

namespace hs {

struct Img { int tex = 0, w = 0, h = 0; };
enum { IMG_BG_MODE, IMG_BG_GAME, IMG_BG_SET, IMG_AV0, IMG_AV1, IMG_AV2, IMG_AV3, IMG_AVS, IMG_COUNT };

struct PickItem { std::string key, label; bool on = false; };

class App {
 public:
  App(Canvas* cv, Fonts* fn);
  Model m;
  Ui ui;

  void setImage(int slot, int w, int h, const uint8_t* rgba);
  void setInsets(float l, float t, float r, float b) { insL_ = l; insT_ = t; insR_ = r; insB_ = b; }  // physical px
  void setSystemDark(bool d) { sysDark_ = d; }
  void frame(double t, int pw, int ph);
  void touch(int type, float x, float y, double t);  // physical px
  int wantFrame() const;                             // 0 idle, 1 ambient (30fps), 2 animating (60fps)
  bool back();                                       // true if consumed
  std::vector<std::string> takeCmds() { auto o = std::move(m.out); m.out.clear(); return o; }
  void gotoTab(int tab, int sub = -1);
  void gotoSub(int sub);

  // ---- layout (stage units) ----
  float SW = 800, SH = 360, L0 = 76, CL = 98, CR = 784;
  int tab = 0;
  std::string curTitle_;

 private:
  friend struct ScreenAccess;
  Canvas* cv_;
  Fonts* fn_;
  Img img_[IMG_COUNT];
  int grainTex_ = 0;
  float insL_ = 0, insT_ = 0, insR_ = 0, insB_ = 0, scale_ = 1;
  bool sysDark_ = false;
  bool wantAmbient_ = false, wantAnim_ = false;
  int tabTarget_ = 0; double sweepT0_ = -10; bool sweepSwapped_ = true;
  bool animOn() const { return m.flag("pref.anim", true); }

  // chrome
  void drawBg(int slot, Rect area);
  void drawRail();
  void drawHeader(const char* title, float* titleW = nullptr);
  void drawToast();
  void applyTheme();

  // screens
  void drawMode();
  void drawGame();
  void drawSetting();
  float modeCardW_ = 0;
  // mode screen state
  double modeWashT_[2] = {-10, -10}; float modeWashX_[2] = {0, 0}, modeWashY_[2] = {0, 0};
  std::string prevMode_;
  double toastT0_ = -10; std::string toastShow_; bool toastBad_ = false;

  // game screen state
  Scroll gameScroll_;
  void gameCard(int i, Rect r);
  void gameArt(const GameInfo& g, Rect r, bool su);
  struct Launch { bool on = false; double t0 = 0; float cx = 0, cy = 0; std::string name, pkg; bool sent = false; } launch_;
  void drawLaunch();
  void startLaunch(const GameInfo& g, float cx, float cy);

  // sheets
  enum { SH_NONE, SH_GAME, SH_PICK };
  int sheetKind_ = SH_NONE; bool sheetClosing_ = false; double sheetT0_ = -10;
  std::string sheetPkg_;
  Scroll sheetScroll_;
  void openSheet(int kind);
  void closeSheet();
  float sheetOpen() ;
  void drawSheet();
  void drawGameSheet(Rect body);
  // picker
  std::string pickTitle_, pickAction_, pickId_, pickDexMode_ = "speed-profile";
  std::vector<PickItem> pick_;
  bool pickModes_ = false; bool pickBusy_ = false; int pickSrc_ = -1; bool confirmDel_ = false, cpuDirty_ = false; long frameNo_ = 0, sheetFrame_ = -1;
  void openPicker(const std::string& id, const std::string& title, const std::string& action, std::vector<PickItem> items, bool modes);
  void drawPicker(Rect body);

  // setting
  int sub_ = 0, subShown_ = 0; double subT0_ = -10;
  Scroll setScroll_;
  std::map<std::string, bool> groupOpen_;
  std::map<std::string, std::vector<std::string>> wrapCache_;
  Scroll histScroll_;
  std::map<int, bool> histOpen_;
  float drawFeature(const void* f, float x, float y, float w, bool draw, bool first);
  float groupBox(const std::string& key, const std::string& name, const std::string& desc, float x, float y, float w, bool openDef, const std::function<float(float, float, float)>& content);
  float pageFitur(int tier, float x, float y, float w);
  float pageRekam(float x, float y, float w);
  float pageAlat(float x, float y, float w);
  float pageUmum(float x, float y, float w);
  float pageInfo(float x, float y, float w);
  float lockBox(float x, float y, float w);
  float note(const std::string& t, float x, float y, float w);
  float actRow(const char* key, const char* nameId, const char* nameEn, const char* dId, const char* dEn, const char* btnId, const char* btnEn,
               float x, float y, float w, bool first, bool* clicked);
  const std::vector<std::string>& wrap(int font, const std::string& s, float size, float w);
  float para(const std::string& s, float x, float y, float w, float size, Col c, int font = F_BODY, bool draw = true);
  void featSet(const std::string& id, const std::string& v, const std::string& cmd);
  float visTop_ = 0, visBot_ = 1e9f, rowH_ = 0;
  std::map<std::string, float> groupH_;
  std::string sliderDirty_;
  float dexBusy_ = 0;
};

}  // namespace hs
