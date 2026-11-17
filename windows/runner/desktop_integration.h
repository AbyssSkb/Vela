#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

class DesktopIntegration {
 public:
  DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopIntegration();

  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);
  void RequestQuit();

 private:
  void AddTray();
  void UpdateTray();
  void ShowWindow();
  void ShowMenu();
  void Emit(const char* event);
  bool SetLaunchAtLogin(bool enabled);
  std::string LoginStatus() const;
  void HandleBackground(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleFiles(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_;
  UINT taskbar_created_;
  HANDLE network_change_ = nullptr;
  HANDLE address_change_ = nullptr;
  bool tray_available_ = false;
  bool background_enabled_ = true;
  bool transferring_ = false;
  bool incoming_ = false;
  bool quitting_ = false;
  bool shutdown_complete_ = false;
  std::wstring node_status_ = L"Starting";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> background_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> files_;
};

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
