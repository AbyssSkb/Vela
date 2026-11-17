#ifndef RUNNER_UPDATER_H_
#define RUNNER_UPDATER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <memory>

class VelaUpdater {
 public:
  static constexpr UINT kShutdownMessage = WM_APP + 0x564;

  VelaUpdater(flutter::BinaryMessenger* messenger, HWND window);
  ~VelaUpdater();

 private:
  struct State {
    std::atomic<bool> busy{true};
    std::atomic<bool> installing{false};
    std::atomic<bool> alive{true};
  };

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<State> state_ = std::make_shared<State>();
};

#endif  // RUNNER_UPDATER_H_
