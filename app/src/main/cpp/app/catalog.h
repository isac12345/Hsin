// Feature catalogue for the Setting tab (phone-level only; per-game options live in the Game tab).
#pragma once
#include <vector>

namespace hs {

enum FKind { FK_SW, FK_CHIPS, FK_INFO, FK_ACT, FK_SLIDER };
struct FOpt { const char* v; const char* id; const char* en; };  // label null -> value + unit
struct Feat {
  int tier;               // 0 = basic (Hsin + Suhsin), 1 = Suhsin only, 2 = other pages
  const char* grp;        // group key
  const char* id;         // value key "f.<id>"
  FKind kind;
  const char* nId; const char* nEn;
  const char* dId; const char* dEn;
  const char* tag; const char* tagEn;  // "Eksperimen"/"Hati-hati" or null
  bool warn;
  const char* def;        // default value
  const char* rec;        // suggested value for this phone, or null
  const char* whyId; const char* whyEn;
  const char* cmd;        // command name, "feat" if null
  const char* key;        // backend key (defaults to id)
  const char* cap; bool capDef;   // capability gate
  std::vector<FOpt> opts;
  int lo, hi, step; const char* unit;
};

const std::vector<Feat>& catalog();
const Feat* findFeat(const char* id);

}  // namespace hs
