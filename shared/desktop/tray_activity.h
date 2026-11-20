#ifndef VELA_SHARED_DESKTOP_TRAY_ACTIVITY_H_
#define VELA_SHARED_DESKTOP_TRAY_ACTIVITY_H_

namespace vela {

class TrayActivity {
 public:
  enum class Status { kNode, kIncoming, kTransferring, kCompleted };

  constexpr Status status() const {
    if (incoming_) return Status::kIncoming;
    if (transferring_) return Status::kTransferring;
    if (completed_) return Status::kCompleted;
    return Status::kNode;
  }

  constexpr bool SetIncoming(bool incoming) {
    const bool changed = incoming_ != incoming;
    incoming_ = incoming;
    return changed;
  }

  constexpr void SetTransferring(bool transferring) {
    transferring_ = transferring;
    if (transferring) ClearCompletion();
  }

  constexpr void FinishTransfer(bool in_background) {
    transferring_ = false;
    completed_ = in_background;
  }

  constexpr bool ClearCompletion() {
    const bool was_completed = completed_;
    completed_ = false;
    return was_completed;
  }

 private:
  bool incoming_ = false;
  bool transferring_ = false;
  bool completed_ = false;
};

}  // namespace vela

#endif  // VELA_SHARED_DESKTOP_TRAY_ACTIVITY_H_
