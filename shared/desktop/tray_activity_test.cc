#include "tray_activity.h"

using vela::TrayActivity;
using Status = TrayActivity::Status;

constexpr bool RequestTakesPriorityAndRestoresTransfer() {
  TrayActivity tray;
  tray.SetTransferring(true);
  if (!tray.SetIncoming(true) || tray.status() != Status::kIncoming) return false;
  if (tray.SetIncoming(true)) return false;
  return tray.SetIncoming(false) && tray.status() == Status::kTransferring;
}

constexpr bool CompletionLastsUntilFocusOrAnotherTransfer() {
  TrayActivity tray;
  tray.SetTransferring(true);
  tray.FinishTransfer(false);
  if (tray.status() != Status::kNode) return false;
  tray.FinishTransfer(true);
  if (tray.status() != Status::kCompleted) return false;
  tray.SetIncoming(true);
  if (tray.status() != Status::kIncoming) return false;
  tray.SetIncoming(false);
  if (tray.status() != Status::kCompleted || !tray.ClearCompletion() ||
      tray.ClearCompletion() || tray.status() != Status::kNode) return false;
  tray.FinishTransfer(true);
  tray.SetTransferring(true);
  tray.SetTransferring(false);
  return tray.status() == Status::kNode;
}

static_assert(RequestTakesPriorityAndRestoresTransfer(), "Incoming request priority");
static_assert(CompletionLastsUntilFocusOrAnotherTransfer(), "Completion lifecycle");
