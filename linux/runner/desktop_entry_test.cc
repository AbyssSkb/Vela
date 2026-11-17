#include "desktop_entry.h"

#include <cassert>

int main() {
  assert(VelaDesktopExec("/opt/Vela.AppImage") == "\"/opt/Vela.AppImage\"");
  assert(VelaDesktopExec("/home/a/My Apps/Vela.AppImage") ==
         "\"/home/a/My Apps/Vela.AppImage\"");
  assert(VelaDesktopExec("/tmp/100% Vela") == "\"/tmp/100%% Vela\"");
  assert(VelaDesktopExec("/tmp/$HOME`id`\"\\Vela") ==
         "\"/tmp/\\$HOME\\`id\\`\\\"\\\\Vela\"");
  for (const auto& path : {"", "relative", "/tmp/line\nbreak", "/tmp/tab\t"}) {
    bool rejected = false;
    try {
      VelaDesktopExec(path);
    } catch (const std::invalid_argument&) {
      rejected = true;
    }
    assert(rejected);
  }
}
