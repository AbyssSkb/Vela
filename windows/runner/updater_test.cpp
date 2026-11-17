#include "updater_files.h"

#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
}  // namespace

int main() {
  std::vector<std::filesystem::path> created;
  auto clean = [&] {
    for (const auto& path : created) {
      std::error_code ignored;
      std::filesystem::remove(path, ignored);
    }
  };
  try {
    const auto directory = vela_update::UpdateDirectory();
    Require(directory.has_value(), "update directory");
    const auto name = L"vela-update-test-" + std::to_wstring(GetCurrentProcessId()) +
                      L"-" + std::to_wstring(GetTickCount64());
    const auto installer = *directory / (name + L".exe");
    const auto wrong_type = *directory / (name + L".zip");
    const auto outside = std::filesystem::temp_directory_path() / (name + L".exe");
    for (const auto& path : {installer, wrong_type, outside}) {
      Require(!std::filesystem::exists(path), "unique fixture path");
      created.push_back(path);
      std::ofstream stream(path, std::ios::binary);
      stream << "abc";
      Require(stream.good(), "write fixture");
    }
    Require(!vela_update::ToWide(std::string("a\0b", 3)), "reject embedded NUL");
    Require(!vela_update::ToWide(std::string("\xff", 1)), "reject invalid UTF-8");
    Require(!vela_update::OpenInstaller(wrong_type.wstring()), "reject non-EXE");
    Require(!vela_update::OpenInstaller(outside.wstring()), "reject outside cache");
    Require(!vela_update::OpenInstaller(directory->wstring()), "reject directory");
    auto file = vela_update::OpenInstaller(installer.wstring());
    Require(static_cast<bool>(file), "open cached installer");
    Require(!vela_update::MatchesHash(file.get(), std::string(64, '0')),
            "reject modified installer");
    Require(vela_update::MatchesHash(
                file.get(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            "SHA-256 covers the complete file");
    const HANDLE writable = CreateFileW(
        installer.c_str(), GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, 0, nullptr);
    if (writable != INVALID_HANDLE_VALUE) CloseHandle(writable);
    Require(writable == INVALID_HANDLE_VALUE, "installer locked against mutation");
    file.reset();
    const auto link = *directory / (name + L"-link.exe");
    if (CreateSymbolicLinkW(link.c_str(), outside.c_str(),
                           SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)) {
      created.push_back(link);
      Require(!vela_update::OpenInstaller(link.wstring()), "reject reparse point");
    } else {
      std::cout << "Symlink case skipped: this runner cannot create symlinks.\n";
    }
    const auto directory_link = *directory / (name + L"-directory");
    if (CreateSymbolicLinkW(directory_link.c_str(), outside.parent_path().c_str(),
                           SYMBOLIC_LINK_FLAG_DIRECTORY |
                               SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE)) {
      created.push_back(directory_link);
      Require(!vela_update::OpenInstaller(
                  (directory_link / outside.filename()).wstring()),
              "reject parent-directory reparse escape");
    } else {
      std::cout << "Directory-symlink case skipped: this runner cannot create symlinks.\n";
    }
    clean();
    std::cout << "Windows updater file validation passed.\n";
    return 0;
  } catch (const std::exception& error) {
    clean();
    std::cerr << error.what() << '\n';
    return 1;
  }
}
