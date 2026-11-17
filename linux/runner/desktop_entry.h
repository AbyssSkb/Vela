#ifndef VELA_DESKTOP_ENTRY_H_
#define VELA_DESKTOP_ENTRY_H_

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

#endif  // VELA_DESKTOP_ENTRY_H_
