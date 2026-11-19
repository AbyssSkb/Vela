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

  g_autoptr(GKeyFile) entry = g_key_file_new();
  const auto original = VelaDesktopExec("/home/a/My Apps/Vela.AppImage");
  const auto moved = VelaDesktopExec("/home/a/Downloads/Vela.AppImage");
  g_key_file_set_string(entry, G_KEY_FILE_DESKTOP_GROUP,
                        G_KEY_FILE_DESKTOP_KEY_EXEC, original.c_str());
  assert(VelaDesktopLoginEnabled(entry, original));
  assert(!VelaDesktopLoginEnabled(entry, moved));
  assert(!VelaDesktopLoginEnabled(entry, ""));
  g_key_file_set_boolean(entry, G_KEY_FILE_DESKTOP_GROUP,
                         "X-GNOME-Autostart-enabled", FALSE);
  assert(!VelaDesktopLoginEnabled(entry, original));
  g_key_file_set_boolean(entry, G_KEY_FILE_DESKTOP_GROUP,
                         "X-GNOME-Autostart-enabled", TRUE);
  g_key_file_set_boolean(entry, G_KEY_FILE_DESKTOP_GROUP,
                         G_KEY_FILE_DESKTOP_KEY_HIDDEN, TRUE);
  assert(!VelaDesktopLoginEnabled(entry, original));
}
