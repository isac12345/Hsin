#pragma once
#include "../app/app.h"
using namespace hs;
inline void seed(App& a) {
  a.m.push(
    "set mode hsin\nset beban 1\nset fps 58\nset temp 41\nset ram.free 1860\nset lastgame.label Monster Hunter Outlanders\nset lastgame.pkg com.mho\n"
    "set dev.line itel P65 \xC2\xB7 Unisoc T606 \xC2\xB7 8 GB \xC2\xB7 720x1600, 60-144 Hz\nset module.state Hidup\nset ver 6.0 beta\n"
    "set cap.vulkan 1\nset cap.thermaloff 1\nset cap.mglru 0\nset cap.vm 1\nset cap.ra 1\nset cap.cpucap 1\nset cap.bypass 1\n"
    "set f.refresh off\nset f.memclean 1\nset f.charge 100\nset f.rec_res 720\nset f.rec_fps 30\nset f.rec_audio 2\n"
    "games.clear\ngame com.mho|Monster Hunter Outlanders|suhsin|60|100|90|default|0\ngame com.mhgu|MHGU|hsin|60|100|100|default|0\ngame com.ww|Wuthering Waves|hsin|60|85|100|default|0\n"
    "apps.clear\napp com.a1|Chrome\napp com.a2|YouTube\napp com.a3|TikTok\napp com.mho|Monster Hunter Outlanders\n"
    "hist.clear\nhist Monster Hunter Outlanders|58|44|42 mnt|3|41\nhist MHGU|60|55|31 mnt|0|38\n"
    "vid.clear\nvid v1|Rekaman 26 Nov 21:14|1080p 02:14 38 MB\nvid v2|Rekaman 25 Nov 20:02|1080p 00:48 14 MB\n"
    "log.clear\nlog 23:41:07 adapt beban 1, gpu 0.55\nlog 23:41:09 fpsd ok\n");
  for (int i = 0; i < 60; i++) a.m.push("fps " + std::to_string(54 + (i * 7) % 9 - (i % 17 == 0 ? 14 : 0)) + "\n");
}

