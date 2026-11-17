#include "updater_files.h"

#include <objbase.h>
#include <shellapi.h>

#include <cstdint>

namespace {
int Fail(DWORD error) {
  MessageBoxW(nullptr, L"The update could not be installed. Open Vela to retry.",
              L"Vela update", MB_OK | MB_ICONERROR);
  return static_cast<int>(error);
}

HANDLE ReadHandle(const wchar_t* value) {
  wchar_t* end = nullptr;
  const auto number = _wcstoui64(value, &end, 10);
  if (!number || !end || *end || number > UINTPTR_MAX) return nullptr;
  return reinterpret_cast<HANDLE>(static_cast<uintptr_t>(number));
}
}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  if (!arguments || count != 5) {
    if (arguments) LocalFree(arguments);
    return ERROR_INVALID_PARAMETER;
  }
  const vela_update::Handle parent(ReadHandle(arguments[1]), CloseHandle);
  const vela_update::Handle file_lock(ReadHandle(arguments[2]), CloseHandle);
  const std::wstring path(arguments[3]);
  const auto hash = vela_update::ToUtf8(arguments[4]);
  LocalFree(arguments);
  if (!parent || !file_lock || !hash) return ERROR_INVALID_PARAMETER;

  if (WaitForSingleObject(parent.get(), 120000) != WAIT_OBJECT_0) {
    return Fail(ERROR_TIMEOUT);
  }
  const auto installer = vela_update::OpenInstaller(path);
  if (!installer || !vela_update::MatchesHash(installer.get(), *hash)) {
    return Fail(ERROR_INVALID_DATA);
  }
  auto final_path = vela_update::FinalPath(installer.get());
  if (!final_path) return Fail(ERROR_INVALID_NAME);
  if (final_path->rfind(L"\\\\?\\UNC\\", 0) == 0) {
    *final_path = L"\\\\" + final_path->substr(8);
  } else if (final_path->rfind(L"\\\\?\\", 0) == 0) {
    *final_path = final_path->substr(4);
  }

  SHELLEXECUTEINFOW execute{};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_NOCLOSEPROCESS;
  execute.lpVerb = L"open";
  execute.lpFile = final_path->c_str();
  execute.lpParameters = L"/SILENT /SP- /NOICONS /NORESTART";
  execute.nShow = SW_SHOWNORMAL;
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED |
                                        COINIT_DISABLE_OLE1DDE))) {
    return Fail(ERROR_INSTALL_FAILURE);
  }
  DWORD exit_code = ERROR_INSTALL_FAILURE;
  if (ShellExecuteExW(&execute) && execute.hProcess) {
    const vela_update::Handle process(execute.hProcess, CloseHandle);
    if (WaitForSingleObject(process.get(), INFINITE) == WAIT_OBJECT_0) {
      if (!GetExitCodeProcess(process.get(), &exit_code)) {
        exit_code = ERROR_INSTALL_FAILURE;
      }
    }
  }
  CoUninitialize();
  if (exit_code != 0) return Fail(ERROR_INSTALL_FAILURE);
  return 0;
}
