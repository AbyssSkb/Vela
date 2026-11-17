#ifndef RUNNER_UPDATER_H_
#define RUNNER_UPDATER_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

void vela_update_register(FlBinaryMessenger* messenger, GApplication* application);

#endif  // RUNNER_UPDATER_H_
