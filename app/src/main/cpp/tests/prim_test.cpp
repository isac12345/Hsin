#include "../engine/soft_canvas.h"
#include "../engine/font.h"
#include "../engine/ink.h"
#include <fstream>
#include <cstdio>
using namespace hs;
static std::vector<uint8_t> rd(const char* p){std::ifstream f(p,std::ios::binary);return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)),{});}
int main(int, char** argv){
  std::string root=argv[1];
  SoftCanvas cv; Fonts fn(&cv);
  auto d=rd((root+"/fonts/disp.ttf").c_str()), b=rd((root+"/fonts/body.ttf").c_str());
  int fd=fn.add(d.data(),d.size()), fb=fn.add(b.data(),b.size());
  cv.begin(1600,720,Col(.93f,.91f,.86f));
  cv.setBase(0,0,2.f);
  int gt=makeGrainTile(cv,128); grain(cv,gt,128,Rect(0,0,800,360),Col(.1f,.1f,.1f,.06f));
  Col ink(.07f,.07f,.08f);
  roughBox(cv,Rect(20,20,200,80),3,1.6f,ink);
  roughBox(cv,Rect(240,20,200,80),5,1.6f,ink,true);
  fn.draw(cv,fd,"Mode Hsin 58",30,30,30,ink);
  fn.draw(cv,fb,"Beban diatur otomatis. Åñ 90°",30,70,13,ink);
  for(int i=0;i<IC_COUNT;i++) icon(cv,(Icon)i,20+i*34,120,26,ink);
  brush(cv,20,180,300,190,20,ink,9);
  enso(cv,400,200,40,6,ink,0,.88f,3);
  cv.pushClip(Rect(0,250,400,100)); inkSweep(cv,Rect(0,250,400,100),.3f,ink,4); cv.popClip();
  cv.rrect(450,150,100,50,10,ink);
  cv.rrect(450,220,100,50,10,ink,1.6f);
  cv.savePng("/tmp/claude-0/-home-claude/1c96c6ae-59de-518f-af5a-282d76ea9d17/scratchpad/prim.png");
  printf("calls %d\n",cv.drawCalls);
}
