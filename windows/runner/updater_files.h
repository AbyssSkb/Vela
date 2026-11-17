#ifndef RUNNER_UPDATER_FILES_H_
#define RUNNER_UPDATER_FILES_H_

#include <windows.h>

#include <filesystem>
#include <memory>
#include <optional>
#include <string>

namespace vela_update {
using Handle = std::shared_ptr<void>;

std::optional<std::wstring> ToWide(const std::string& value);
std::optional<std::string> ToUtf8(const std::wstring& value);
std::optional<std::filesystem::path> UpdateDirectory();
std::optional<std::wstring> FinalPath(HANDLE handle);
Handle OpenInstaller(const std::wstring& path);
bool MatchesHash(HANDLE file, const std::string& expected);
}  // namespace vela_update

#endif  // RUNNER_UPDATER_FILES_H_
