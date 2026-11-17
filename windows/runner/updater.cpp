#include "updater.h"

#include "updater_files.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using namespace vela_update;

const EncodableValue* Field(const EncodableValue* arguments, const char* key) {
  if (!arguments) return nullptr;
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (!map) return nullptr;
  const auto value = map->find(EncodableValue(key));
  return value == map->end() ? nullptr : &value->second;
}

bool LaunchHelper(const Handle& installer, const std::wstring& path,
                  const std::string& hash) {
  std::wstring executable(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, executable.data(),
                                      static_cast<DWORD>(executable.size()));
  if (!size || size >= executable.size()) return false;
  executable.resize(size);
  const auto source = std::filesystem::path(executable).parent_path() /
                      L"vela_updater_helper.exe";
  const auto directory = UpdateDirectory();
  if (!directory) return false;
  const auto helper = *directory /
      (L"vela-updater-helper-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
       std::to_wstring(GetTickCount64()) + L".exe");
  if (!CopyFileW(source.c_str(), helper.c_str(), TRUE)) return false;

  HANDLE parent_raw = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(),
                       GetCurrentProcess(), &parent_raw, SYNCHRONIZE, TRUE, 0)) {
    DeleteFileW(helper.c_str());
    return false;
  }
  const Handle parent(parent_raw, CloseHandle);
  HANDLE installer_raw = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), installer.get(), GetCurrentProcess(),
                       &installer_raw, 0, TRUE, DUPLICATE_SAME_ACCESS)) {
    DeleteFileW(helper.c_str());
    return false;
  }
  const Handle installer_lock(installer_raw, CloseHandle);
  HANDLE inherited[] = {parent.get(), installer_lock.get()};
  SIZE_T attribute_size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_size);
  std::vector<BYTE> storage(attribute_size);
  auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
  if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_size)) {
    DeleteFileW(helper.c_str());
    return false;
  }
  const std::shared_ptr<void> attribute_cleanup(attributes, [](void* value) {
    DeleteProcThreadAttributeList(
        static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(value));
  });
  if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                 inherited, sizeof(inherited), nullptr, nullptr)) {
    DeleteFileW(helper.c_str());
    return false;
  }
  const std::wstring wide_hash(hash.begin(), hash.end());
  auto command = L"\"" + helper.wstring() + L"\" " +
      std::to_wstring(reinterpret_cast<uintptr_t>(parent.get())) + L" " +
      std::to_wstring(reinterpret_cast<uintptr_t>(installer_lock.get())) +
      L" \"" + path + L"\" " + wide_hash;
  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.lpAttributeList = attributes;
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, TRUE,
                       EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr,
                       directory->c_str(), &startup.StartupInfo, &process)) {
    DeleteFileW(helper.c_str());
    return false;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}
}  // namespace

VelaUpdater::VelaUpdater(flutter::BinaryMessenger* messenger, HWND window)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "vela/update", &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this, window](const auto& call, auto result) {
        if (call.method_name() == "info") {
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("platform"), EncodableValue("windows")},
              {EncodableValue("arch"), EncodableValue("x64")},
              {EncodableValue("version"), EncodableValue(FLUTTER_VERSION)},
              {EncodableValue("build"),
               EncodableValue(std::to_string(FLUTTER_VERSION_BUILD))},
          }));
          return;
        }
        if (call.method_name() == "getUpdateDirectory") {
          const auto directory = UpdateDirectory();
          const auto path = directory ? ToUtf8(directory->wstring()) : std::nullopt;
          if (!path) {
            result->Error("update_directory", "Cannot access the update cache.");
          } else {
            result->Success(EncodableValue(*path));
          }
          return;
        }
        if (call.method_name() == "setBusy") {
          const auto* value = Field(call.arguments(), "busy");
          const auto* busy = value ? std::get_if<bool>(value) : nullptr;
          if (!busy) {
            result->Error("invalid_arguments", "Expected a busy flag.");
          } else {
            state_->busy = *busy;
            result->Success();
          }
          return;
        }
        if (call.method_name() != "installDownloaded") {
          result->NotImplemented();
          return;
        }
        const auto* path_value = Field(call.arguments(), "path");
        const auto* hash_value = Field(call.arguments(), "sha256");
        const auto* path = path_value ? std::get_if<std::string>(path_value) : nullptr;
        const auto* hash = hash_value ? std::get_if<std::string>(hash_value) : nullptr;
        const auto wide_path = path ? ToWide(*path) : std::nullopt;
        if (!wide_path || !hash) {
          result->Error("invalid_arguments", "Expected an installer path and SHA-256.");
          return;
        }
        if (state_->busy || state_->installing.exchange(true)) {
          result->Error("update_busy", "Wait for pairing and transfers to finish.");
          return;
        }
        // Lock the verified bytes until Windows has opened the installer.
        const auto installer = OpenInstaller(*wide_path);
        if (!installer || !MatchesHash(installer.get(), *hash)) {
          state_->installing = false;
          result->Error("invalid_update", "The cached installer failed validation.");
          return;
        }
        const auto final_path = FinalPath(installer.get());
        if (!final_path) {
          state_->installing = false;
          result->Error("invalid_update", "Cannot resolve the cached installer.");
          return;
        }
        const auto reply = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
            std::move(result));
        const auto state = state_;
        channel_->InvokeMethod(
            "prepareInstall", nullptr,
            std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
                [state, reply, installer, final_path, hash = *hash, window](const auto* value) {
                  const auto* ready = value ? std::get_if<bool>(value) : nullptr;
                  if (!state->alive || state->busy || !ready || !*ready ||
                      !IsWindow(window)) {
                    state->installing = false;
                    reply->Error("update_busy", "Vela is not ready to restart.");
                    return;
                  }
                  if (!LaunchHelper(installer, *final_path, hash)) {
                    state->installing = false;
                    reply->Error("install_failed", "Cannot launch the update installer.");
                    return;
                  }
                  reply->Success();
                  PostMessageW(window, kShutdownMessage, 0, 0);
                },
                [state, reply](const auto&, const auto&, const auto*) {
                  state->installing = false;
                  reply->Error("update_busy", "Vela could not prepare to restart.");
                },
                [state, reply] {
                  state->installing = false;
                  reply->Error("update_busy", "Restart coordination is unavailable.");
                }));
      });
}

VelaUpdater::~VelaUpdater() {
  state_->alive = false;
  channel_->SetMethodCallHandler(nullptr);
}
