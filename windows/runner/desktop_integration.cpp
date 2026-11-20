#include <winsock2.h>
#include <ws2tcpip.h>

#include "desktop_integration.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <winhttp.h>

#include <cassert>
#include <cstdint>
#include <filesystem>
#include <vector>

#include "resource.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
constexpr UINT kTrayMessage = WM_APP + 21;
constexpr UINT kNetworkMessage = WM_APP + 22;
constexpr UINT kShutdownFinished = WM_APP + 23;
constexpr UINT kShowCommand = 1;
constexpr UINT kQuitCommand = 2;
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

std::wstring Wide(const std::string& text) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                                      static_cast<int>(text.size()), nullptr, 0);
  std::wstring value(size, L'\0');
  if (size != 0) {
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                        static_cast<int>(text.size()), value.data(), size);
  }
  return value;
}

std::string StringArgument(const EncodableValue* arguments, const char* key) {
  const auto* map = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
  if (!map) return {};
  const auto item = map->find(EncodableValue(key));
  if (item == map->end()) return {};
  const auto* value = std::get_if<std::string>(&item->second);
  return value ? *value : std::string();
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> path(32768);
  const DWORD size = GetModuleFileNameW(nullptr, path.data(),
                                        static_cast<DWORD>(path.size()));
  return size != 0 && size < path.size() ? std::wstring(path.data(), size)
                                       : std::wstring();
}

std::wstring StartupCommand(const std::wstring& path) {
  if (path.empty() || path.size() + 2 > 260) return {};
  return L"\"" + path + L"\"";
}

bool ValidWebUrl(const std::wstring& url) {
  if (url.empty() || url.find(L'\0') != std::wstring::npos) return false;
  URL_COMPONENTS parts{};
  parts.dwStructSize = sizeof(parts);
  parts.dwSchemeLength = static_cast<DWORD>(-1);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  return WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &parts) &&
         (parts.nScheme == INTERNET_SCHEME_HTTP ||
          parts.nScheme == INTERNET_SCHEME_HTTPS) &&
         parts.dwHostNameLength != 0;
}

NOTIFYICONDATAW TrayData(HWND window) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = 1;
  return data;
}

void CALLBACK InterfaceChanged(void* context, PMIB_IPINTERFACE_ROW,
                                MIB_NOTIFICATION_TYPE) {
  PostMessageW(static_cast<HWND>(context), kNetworkMessage, 0, 0);
}

void CALLBACK AddressChanged(void* context, PMIB_UNICASTIPADDRESS_ROW,
                              MIB_NOTIFICATION_TYPE) {
  PostMessageW(static_cast<HWND>(context), kNetworkMessage, 0, 0);
}
}  // namespace

DesktopIntegration::DesktopIntegration(HWND window,
                                       flutter::BinaryMessenger* messenger)
    : window_(window),
      taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")) {
  assert(ValidWebUrl(L"https://example.com/path"));
  assert(!ValidWebUrl(L"file:///C:/secret"));
  assert(!ValidWebUrl(L"https:///"));
  assert(StartupCommand(L"C:\\Program Files\\Vela\\vela.exe") ==
         L"\"C:\\Program Files\\Vela\\vela.exe\"");
  assert(StartupCommand(std::wstring(258, L'a')).size() == 260);
  assert(StartupCommand(std::wstring(259, L'a')).empty());
  background_ =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "vela/background",
          &flutter::StandardMethodCodec::GetInstance());
  files_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "vela/files", &flutter::StandardMethodCodec::GetInstance());
  background_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleBackground(call, std::move(result));
  });
  files_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleFiles(call, std::move(result));
  });
  AddTray();
  NotifyIpInterfaceChange(AF_UNSPEC, InterfaceChanged, window_, FALSE,
                          &network_change_);
  NotifyUnicastIpAddressChange(AF_UNSPEC, AddressChanged, window_, FALSE,
                               &address_change_);
}

DesktopIntegration::~DesktopIntegration() {
  background_->SetMethodCallHandler(nullptr);
  files_->SetMethodCallHandler(nullptr);
  if (network_change_) CancelMibChangeNotify2(network_change_);
  if (address_change_) CancelMibChangeNotify2(address_change_);
  auto data = TrayData(window_);
  Shell_NotifyIconW(NIM_DELETE, &data);
}

void DesktopIntegration::AddTray() {
  auto data = TrayData(window_);
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"Vela");
  tray_available_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (tray_available_) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
    UpdateTray();
  } else if (!IsWindowVisible(window_)) {
    ShowWindow();
  }
}

void DesktopIntegration::UpdateTray() {
  if (!tray_available_) return;
  auto data = TrayData(window_);
  data.uFlags = NIF_TIP | NIF_SHOWTIP;
  int icon = IDI_APP_ICON;
  const std::wstring* label = &node_status_;
  switch (activity_.status()) {
    case vela::TrayActivity::Status::kIncoming:
      icon = IDI_TRAY_INCOMING;
      label = &incoming_label_;
      break;
    case vela::TrayActivity::Status::kTransferring:
      icon = IDI_TRAY_TRANSFERRING;
      label = &transferring_label_;
      break;
    case vela::TrayActivity::Status::kCompleted:
      icon = IDI_TRAY_COMPLETED;
      label = &completed_label_;
      break;
    case vela::TrayActivity::Status::kNode:
      break;
  }
  const auto text = L"Vela - " + *label;
  data.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(icon), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
  if (data.hIcon) data.uFlags |= NIF_ICON;
  wcsncpy_s(data.szTip, text.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void DesktopIntegration::Emit(const char* event) {
  background_->InvokeMethod(event, nullptr);
}

void DesktopIntegration::ShowWindow() {
  ::ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
  Emit("visible");
}

void DesktopIntegration::RequestQuit() {
  if (quitting_) return;
  quitting_ = true;
  const HWND window = window_;
  const auto finished = [window]() {
    PostMessageW(window, kShutdownFinished, 0, 0);
  };
  background_->InvokeMethod(
      "shutdown", nullptr,
      std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
          [finished](const EncodableValue*) { finished(); },
          [this](const std::string&, const std::string&, const EncodableValue*) {
            quitting_ = false;
            ShowWindow();
          },
          finished));
}

void DesktopIntegration::ShowMenu() {
  const HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kShowCommand, open_label_.c_str());
  AppendMenuW(menu, MF_STRING | (quitting_ ? MF_GRAYED : 0), kQuitCommand,
              quit_label_.c_str());
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(window_);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, point.x, point.y, 0,
      window_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_, WM_NULL, 0, 0);
  if (command == kShowCommand) ShowWindow();
  if (command == kQuitCommand) RequestQuit();
}

std::optional<LRESULT> DesktopIntegration::HandleMessage(UINT message,
                                                         WPARAM wparam,
                                                         LPARAM lparam) {
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    AddTray();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      if (shutdown_complete_) return std::nullopt;
      if (background_enabled_ && tray_available_ && !quitting_) {
        ::ShowWindow(window_, SW_HIDE);
        Emit("hidden");
      } else {
        RequestQuit();
      }
      return 0;
    case kShutdownFinished:
      shutdown_complete_ = true;
      PostMessageW(window_, WM_CLOSE, 0, 0);
      return 0;
    case kTrayMessage:
      if (LOWORD(lparam) == NIN_SELECT || LOWORD(lparam) == NIN_KEYSELECT ||
          LOWORD(lparam) == NIN_BALLOONUSERCLICK) {
        ShowWindow();
      } else if (LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowMenu();
      }
      return 0;
    case kNetworkMessage:
      Emit("networkChanged");
      return 0;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMRESUMEAUTOMATIC) Emit("systemWake");
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE) {
        if (activity_.ClearCompletion()) {
          UpdateTray();
        }
        Emit("visible");
      }
      break;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) Emit("hidden");
      break;
    case WM_SHOWWINDOW:
      Emit(wparam ? "visible" : "hidden");
      break;
  }
  return std::nullopt;
}

std::string DesktopIntegration::LoginStatus() const {
  DWORD bytes = 0;
  const auto size_result = RegGetValueW(HKEY_CURRENT_USER, kRunKey, L"Vela",
                                        RRF_RT_REG_SZ, nullptr, nullptr, &bytes);
  if (size_result == ERROR_FILE_NOT_FOUND) return "notRegistered";
  if (size_result != ERROR_SUCCESS) return "unknown";
  std::vector<wchar_t> value(bytes / sizeof(wchar_t) + 1);
  const auto result = RegGetValueW(HKEY_CURRENT_USER, kRunKey, L"Vela",
                                  RRF_RT_REG_SZ, nullptr, value.data(), &bytes);
  const auto expected = StartupCommand(ExecutablePath());
  return result == ERROR_SUCCESS && !expected.empty() && expected == value.data()
             ? "enabled"
             : "notRegistered";
}

bool DesktopIntegration::SetLaunchAtLogin(bool enabled) {
  const auto command = enabled ? StartupCommand(ExecutablePath()) : std::wstring();
  if (enabled && command.empty()) return false;
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE,
                       nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS result;
  if (enabled) {
    result = RegSetValueExW(key, L"Vela", 0, REG_SZ,
                            reinterpret_cast<const BYTE*>(command.c_str()),
                            static_cast<DWORD>((command.size() + 1) *
                                               sizeof(wchar_t)));
  } else {
    result = RegDeleteValueW(key, L"Vela");
  }
  RegCloseKey(key);
  return result == ERROR_SUCCESS || (!enabled && result == ERROR_FILE_NOT_FOUND);
}

void DesktopIntegration::HandleBackground(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "desktopStatus") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("running"), EncodableValue(background_enabled_ && tray_available_)},
        {EncodableValue("trayAvailable"), EncodableValue(tray_available_)},
        {EncodableValue("loginSupported"), EncodableValue(true)},
        {EncodableValue("loginStatus"), EncodableValue(LoginStatus())},
    }));
  } else if (method == "isVisible" || method == "getWindowVisible") {
    const bool visible = IsWindowVisible(window_) && !IsIconic(window_);
    result->Success(EncodableValue(
        visible && (method == "getWindowVisible" || GetForegroundWindow() == window_)));
  } else if (method == "setDesktopBackground" || method == "setTransferring" ||
             method == "setLaunchAtLogin") {
    const auto* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!value) {
      result->Error("arguments", "Expected a boolean");
      return;
    }
    if (method == "setLaunchAtLogin") {
      if (SetLaunchAtLogin(*value)) {
        result->Success(EncodableValue(LoginStatus()));
      } else {
        result->Error("login", "Could not update launch at login");
      }
      return;
    }
    if (method == "setDesktopBackground") {
      if (*value && !tray_available_) {
        result->Error("background", "The system tray is unavailable");
        return;
      }
      background_enabled_ = *value;
      if (!*value && !IsWindowVisible(window_)) ShowWindow();
    } else {
      activity_.SetTransferring(*value);
      UpdateTray();
    }
    result->Success();
  } else if (method == "transferCompleted") {
    const auto* show = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!show) {
      result->Error("arguments", "Expected a boolean");
      return;
    }
    const bool in_background = GetForegroundWindow() != window_ || IsIconic(window_);
    activity_.FinishTransfer(in_background);
    UpdateTray();
    if (in_background && *show) ShowWindow();
    result->Success();
  } else if (method == "setTrayLabels") {
    const auto open = Wide(StringArgument(call.arguments(), "open"));
    const auto quit = Wide(StringArgument(call.arguments(), "quit"));
    const auto incoming = Wide(StringArgument(call.arguments(), "incoming"));
    const auto transferring = Wide(StringArgument(call.arguments(), "transferring"));
    const auto completed = Wide(StringArgument(call.arguments(), "completed"));
    if (open.empty() || quit.empty() || incoming.empty() ||
        transferring.empty() || completed.empty()) {
      result->Error("arguments", "Expected tray labels");
      return;
    }
    open_label_ = open;
    quit_label_ = quit;
    incoming_label_ = incoming;
    transferring_label_ = transferring;
    completed_label_ = completed;
    UpdateTray();
    result->Success();
  } else if (method == "setNodeStatus") {
    const auto* status = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!status) {
      result->Error("arguments", "Expected a status string");
      return;
    }
    node_status_ = Wide(*status);
    UpdateTray();
    result->Success();
  } else if (method == "offer" || method == "clearOffer") {
    const bool incoming = method == "offer";
    activity_.SetIncoming(incoming);
    auto data = TrayData(window_);
    data.uFlags = NIF_INFO;
    if (incoming) {
      const auto title = Wide(StringArgument(call.arguments(), "title"));
      const auto message = Wide(StringArgument(call.arguments(), "message"));
      wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
      wcsncpy_s(data.szInfo, message.c_str(), _TRUNCATE);
      data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
    }
    const bool delivered = Shell_NotifyIconW(NIM_MODIFY, &data) != FALSE;
    UpdateTray();
    if (incoming && !delivered) {
      result->Error("notification", "Could not show the notification");
    } else {
      result->Success();
    }
  } else if (method == "show") {
    ShowWindow();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void DesktopIntegration::HandleFiles(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == "openUrl") {
    const auto url = Wide(StringArgument(call.arguments(), "url"));
    if (!ValidWebUrl(url)) {
      result->Error("url", "Expected an HTTP or HTTPS URL");
      return;
    }
    if (reinterpret_cast<intptr_t>(ShellExecuteW(window_, L"open", url.c_str(),
                                                nullptr, nullptr, SW_SHOWNORMAL)) <= 32) {
      result->Error("url", "Could not open URL");
    } else {
      result->Success();
    }
  } else if (call.method_name() == "openPath") {
    const auto path = Wide(StringArgument(call.arguments(), "path"));
    if (path.empty() || path.find(L'\0') != std::wstring::npos ||
        !std::filesystem::path(path).is_absolute()) {
      result->Error("arguments", "Expected an absolute path");
      return;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      result->Error("open", "The path is unavailable");
      return;
    }
    const auto opened = reinterpret_cast<intptr_t>(ShellExecuteW(
        window_, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
    if (opened <= 32) {
      result->Error(opened == SE_ERR_NOASSOC ? "no_app" : "open",
                    "Could not open path");
    } else {
      result->Success();
    }
  } else if (call.method_name() == "reveal") {
    const auto path = Wide(StringArgument(call.arguments(), "path"));
    if (path.empty() || path.find(L'\0') != std::wstring::npos) {
      result->Error("arguments", "Expected a file path");
      return;
    }
    PIDLIST_ABSOLUTE item = nullptr;
    const auto parsed = SHParseDisplayName(path.c_str(), nullptr, &item, 0, nullptr);
    const auto opened = SUCCEEDED(parsed)
                            ? SHOpenFolderAndSelectItems(item, 0, nullptr, 0)
                            : parsed;
    CoTaskMemFree(item);
    if (FAILED(opened)) {
      result->Error("open", "Could not reveal file");
    } else {
      result->Success();
    }
  } else {
    result->NotImplemented();
  }
}
