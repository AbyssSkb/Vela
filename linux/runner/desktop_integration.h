#ifndef VELA_DESKTOP_INTEGRATION_H_
#define VELA_DESKTOP_INTEGRATION_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

void vela_desktop_register(FlBinaryMessenger* messenger,
                           GtkApplication* application,
                           GtkWindow* window);

#endif  // VELA_DESKTOP_INTEGRATION_H_
