#ifndef VELA_DESKTOP_ENTRY_H_
#define VELA_DESKTOP_ENTRY_H_

#include <glib.h>

#include <stdexcept>
#include <string>

inline std::string VelaDesktopExec(const std::string& path) {
  if (path.empty() || path.front() != '/') {
    throw std::invalid_argument("Autostart requires an absolute executable path");
  }
  std::string command = "\"";
  for (unsigned char character : path) {
    if (character < 32 || character == 127) {
      throw std::invalid_argument("Executable path contains control characters");
    }
    if (character == '%') command += '%';
    if (character == '\\' || character == '"' || character == '$' ||
        character == '`') {
      command += '\\';
    }
    command += static_cast<char>(character);
  }
  return command + '"';
}

inline bool VelaDesktopLoginEnabled(GKeyFile* entry,
                                    const std::string& expected_command) {
  const auto* group = G_KEY_FILE_DESKTOP_GROUP;
  const auto* gnome_enabled = "X-GNOME-Autostart-enabled";
  if (expected_command.empty() ||
      g_key_file_get_boolean(entry, group, G_KEY_FILE_DESKTOP_KEY_HIDDEN,
                             nullptr) ||
      (g_key_file_has_key(entry, group, gnome_enabled, nullptr) &&
       !g_key_file_get_boolean(entry, group, gnome_enabled, nullptr))) {
    return false;
  }
  g_autofree gchar* command =
      g_key_file_get_string(entry, group, G_KEY_FILE_DESKTOP_KEY_EXEC, nullptr);
  return command != nullptr && expected_command == command;
}

#endif  // VELA_DESKTOP_ENTRY_H_
