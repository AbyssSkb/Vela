#include "desktop_integration.h"

#include <libayatana-appindicator/app-indicator.h>
#include <libnotify/notify.h>
#include <glib/gstdio.h>

#include <cerrno>
#include <cstring>
#include <string>

#include "desktop_entry.h"

namespace {

class DesktopIntegration {
 public:
  DesktopIntegration(FlBinaryMessenger* messenger, GtkApplication* application,
                     GtkWindow* window)
      : application_(application), window_(window) {
    g_object_add_weak_pointer(G_OBJECT(window_),
                              reinterpret_cast<gpointer*>(&window_));
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    background_ = fl_method_channel_new(messenger, "vela/background",
                                        FL_METHOD_CODEC(codec));
    files_ = fl_method_channel_new(messenger, "vela/files", FL_METHOD_CODEC(codec));
    clipboard_ = fl_method_channel_new(messenger, "vela/clipboard",
                                       FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(background_, HandleBackground,
                                              this, nullptr);
    fl_method_channel_set_method_call_handler(files_, HandleFiles, this, nullptr);
    fl_method_channel_set_method_call_handler(clipboard_, HandleClipboard,
                                              this, nullptr);

    indicator_ = app_indicator_new(APPLICATION_ID, APPLICATION_ID,
                                   APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
    app_indicator_set_title(indicator_, "Vela");
    auto* menu = gtk_menu_new();
    show_item_ = gtk_menu_item_new_with_label("Open Vela");
    quit_item_ = gtk_menu_item_new_with_label("Quit");
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), show_item_);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item_);
    g_signal_connect_swapped(show_item_, "activate", G_CALLBACK(Show), this);
    g_signal_connect_swapped(quit_item_, "activate", G_CALLBACK(Quit), this);
    gtk_widget_show_all(menu);
    app_indicator_set_menu(indicator_, GTK_MENU(menu));
    app_indicator_set_status(indicator_, APP_INDICATOR_STATUS_ACTIVE);
    g_signal_connect(indicator_, "connection-changed",
                     G_CALLBACK(IndicatorConnectionChanged), this);

    g_signal_connect(window_, "delete-event", G_CALLBACK(DeleteWindow), this);
    g_signal_connect(window_, "map-event", G_CALLBACK(WindowMapped), this);
    g_signal_connect(window_, "unmap-event", G_CALLBACK(WindowUnmapped), this);
    network_ = G_NETWORK_MONITOR(g_object_ref(g_network_monitor_get_default()));
    g_signal_connect(network_, "network-changed", G_CALLBACK(NetworkChanged),
                     this);
    system_bus_ = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
    if (system_bus_ != nullptr) {
      sleep_subscription_ = g_dbus_connection_signal_subscribe(
          system_bus_, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
          "PrepareForSleep", "/org/freedesktop/login1", nullptr,
          G_DBUS_SIGNAL_FLAGS_NONE, PrepareForSleep, this, nullptr);
    }
    notify_init("Vela");
  }

  ~DesktopIntegration() {
    fl_method_channel_set_method_call_handler(background_, nullptr, nullptr,
                                              nullptr);
    fl_method_channel_set_method_call_handler(files_, nullptr, nullptr, nullptr);
    fl_method_channel_set_method_call_handler(clipboard_, nullptr, nullptr,
                                              nullptr);
    if (sleep_subscription_ != 0) {
      g_dbus_connection_signal_unsubscribe(system_bus_, sleep_subscription_);
    }
    if (window_ != nullptr) {
      g_signal_handlers_disconnect_by_data(window_, this);
      g_object_remove_weak_pointer(G_OBJECT(window_),
                                   reinterpret_cast<gpointer*>(&window_));
    }
    g_signal_handlers_disconnect_by_data(network_, this);
    g_signal_handlers_disconnect_by_data(indicator_, this);
    ClearOffer();
    g_clear_object(&system_bus_);
    g_clear_object(&network_);
    g_clear_object(&indicator_);
    g_clear_object(&background_);
    g_clear_object(&files_);
    g_clear_object(&clipboard_);
  }

 private:
  GtkApplication* application_;
  GtkWindow* window_;
  FlMethodChannel* background_ = nullptr;
  FlMethodChannel* files_ = nullptr;
  FlMethodChannel* clipboard_ = nullptr;
  AppIndicator* indicator_ = nullptr;
  GtkWidget* show_item_ = nullptr;
  GtkWidget* quit_item_ = nullptr;
  NotifyNotification* offer_ = nullptr;
  GNetworkMonitor* network_ = nullptr;
  GDBusConnection* system_bus_ = nullptr;
  guint sleep_subscription_ = 0;
  bool background_enabled_ = true;
  bool quitting_ = false;

  bool TrayAvailable() const {
    gboolean connected = FALSE;
    g_object_get(indicator_, "connected", &connected, nullptr);
    return connected;
  }

  void Event(const char* name) {
    fl_method_channel_invoke_method(background_, name, nullptr, nullptr, nullptr,
                                    nullptr);
  }

  static void Show(DesktopIntegration* self) {
    if (self->window_ == nullptr) return;
    gtk_widget_show(GTK_WIDGET(self->window_));
    gtk_window_present(self->window_);
    self->Event("visible");
  }

  static void Quit(DesktopIntegration* self) {
    if (self->quitting_) return;
    self->quitting_ = true;
    fl_method_channel_invoke_method(
        self->background_, "shutdown", nullptr, nullptr,
        [](GObject* object, GAsyncResult* result, gpointer data) {
          auto* self = static_cast<DesktopIntegration*>(data);
          g_autoptr(GError) error = nullptr;
          g_autoptr(FlMethodResponse) response =
              fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(object),
                                                     result, &error);
          if (response != nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
            g_application_quit(G_APPLICATION(self->application_));
          } else {
            self->quitting_ = false;
            Show(self);
            g_warning("Vela could not finish shutdown");
          }
        },
        self);
  }

  static gboolean DeleteWindow(GtkWidget*, GdkEvent*, gpointer data) {
    auto* self = static_cast<DesktopIntegration*>(data);
    if (self->background_enabled_ && self->TrayAvailable()) {
      gtk_widget_hide(GTK_WIDGET(self->window_));
    } else {
      Quit(self);
    }
    return TRUE;
  }

  static gboolean WindowMapped(GtkWidget*, GdkEvent*, gpointer data) {
    static_cast<DesktopIntegration*>(data)->Event("visible");
    return FALSE;
  }

  static gboolean WindowUnmapped(GtkWidget*, GdkEvent*, gpointer data) {
    static_cast<DesktopIntegration*>(data)->Event("hidden");
    return FALSE;
  }

  static void IndicatorConnectionChanged(AppIndicator*, gboolean connected,
                                         gpointer data) {
    if (!connected) Show(static_cast<DesktopIntegration*>(data));
  }

  static void NetworkChanged(GNetworkMonitor*, gboolean, gpointer data) {
    static_cast<DesktopIntegration*>(data)->Event("networkChanged");
  }

  static void PrepareForSleep(GDBusConnection*, const gchar*, const gchar*,
                              const gchar*, const gchar*, GVariant* parameters,
                              gpointer data) {
    gboolean sleeping = FALSE;
    g_variant_get(parameters, "(b)", &sleeping);
    if (!sleeping) static_cast<DesktopIntegration*>(data)->Event("systemWake");
  }

  static std::string AutostartPath() {
    return std::string(g_get_user_config_dir()) + "/autostart/" +
           APPLICATION_ID + ".desktop";
  }

  static bool LoginEnabled() {
    g_autoptr(GKeyFile) entry = g_key_file_new();
    return g_key_file_load_from_file(entry, AutostartPath().c_str(),
                                     G_KEY_FILE_NONE, nullptr) &&
           !g_key_file_get_boolean(entry, "Desktop Entry", "Hidden", nullptr);
  }

  static bool SetLogin(bool enabled, GError** error) {
    const auto path = AutostartPath();
    if (!enabled) {
      if (g_remove(path.c_str()) == 0 || errno == ENOENT) return true;
      g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                   "Cannot remove login item: %s", g_strerror(errno));
      return false;
    }
    const gchar* appimage = g_getenv("APPIMAGE");
    g_autofree gchar* executable =
        appimage != nullptr && g_path_is_absolute(appimage)
            ? g_strdup(appimage)
            : g_file_read_link("/proc/self/exe", error);
    if (executable == nullptr) return false;
    std::string command;
    try {
      command = VelaDesktopExec(executable);
    } catch (const std::invalid_argument& exception) {
      g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_INVAL,
                            exception.what());
      return false;
    }
    g_autofree gchar* directory = g_path_get_dirname(path.c_str());
    if (g_mkdir_with_parents(directory, 0700) != 0) {
      g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                   "Cannot create login item directory: %s", g_strerror(errno));
      return false;
    }
    g_autoptr(GKeyFile) entry = g_key_file_new();
    g_key_file_set_string(entry, "Desktop Entry", "Type", "Application");
    g_key_file_set_string(entry, "Desktop Entry", "Name", "Vela");
    g_key_file_set_string(entry, "Desktop Entry", "Exec", command.c_str());
    g_key_file_set_string(entry, "Desktop Entry", "Icon", APPLICATION_ID);
    g_key_file_set_boolean(entry, "Desktop Entry", "Terminal", FALSE);
    return g_key_file_save_to_file(entry, path.c_str(), error);
  }

  void ClearOffer() {
    if (offer_ == nullptr) return;
    notify_notification_clear_actions(offer_);
    notify_notification_close(offer_, nullptr);
    g_clear_object(&offer_);
  }

  void Offer(const char* title, const char* message) {
    ClearOffer();
    g_autofree gchar* escaped = g_markup_escape_text(message, -1);
    offer_ = notify_notification_new(title, escaped, APPLICATION_ID);
    notify_notification_add_action(
        offer_, "default", "Open Vela",
        [](NotifyNotification*, char*, gpointer data) {
          Show(static_cast<DesktopIntegration*>(data));
        },
        this, nullptr);
    if (!notify_notification_show(offer_, nullptr)) Show(this);
  }

  static const char* StringArgument(FlValue* arguments, const char* key) {
    if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
      return nullptr;
    }
    auto* value = fl_value_lookup_string(arguments, key);
    return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
               ? fl_value_get_string(value)
               : nullptr;
  }

  static void HandleBackground(FlMethodChannel*, FlMethodCall* call,
                                gpointer data) {
    auto* self = static_cast<DesktopIntegration*>(data);
    const auto* method = fl_method_call_get_name(call);
    auto* arguments = fl_method_call_get_args(call);
    g_autoptr(FlValue) result = nullptr;
    if (strcmp(method, "desktopStatus") == 0) {
      result = fl_value_new_map();
      fl_value_set_string_take(result, "running",
                                fl_value_new_bool(self->background_enabled_));
      fl_value_set_string_take(result, "trayAvailable",
                                fl_value_new_bool(self->TrayAvailable()));
      fl_value_set_string_take(result, "loginSupported", fl_value_new_bool(TRUE));
      fl_value_set_string_take(result, "loginStatus", fl_value_new_string(
          LoginEnabled() ? "enabled" : "notRegistered"));
    } else if (strcmp(method, "setDesktopBackground") == 0 ||
               strcmp(method, "setLaunchAtLogin") == 0) {
      if (arguments == nullptr ||
          fl_value_get_type(arguments) != FL_VALUE_TYPE_BOOL) {
        fl_method_call_respond_error(call, "arguments", "Expected a boolean",
                                     nullptr, nullptr);
        return;
      }
      const auto enabled = fl_value_get_bool(arguments);
      if (strcmp(method, "setDesktopBackground") == 0) {
        self->background_enabled_ = enabled;
        if (!enabled) Show(self);
      } else {
        g_autoptr(GError) error = nullptr;
        if (!SetLogin(enabled, &error)) {
          fl_method_call_respond_error(call, "login", error->message, nullptr,
                                       nullptr);
          return;
        }
        result = fl_value_new_string(enabled ? "enabled" : "notRegistered");
      }
    } else if (strcmp(method, "isVisible") == 0) {
      result = fl_value_new_bool(self->window_ != nullptr &&
                                 gtk_widget_get_visible(GTK_WIDGET(self->window_))
                                 && gtk_window_is_active(self->window_));
    } else if (strcmp(method, "getWindowVisible") == 0) {
      result = fl_value_new_bool(self->window_ != nullptr &&
                                 gtk_widget_get_visible(GTK_WIDGET(self->window_)));
    } else if (strcmp(method, "offer") == 0) {
      auto* title = StringArgument(arguments, "title");
      auto* message = StringArgument(arguments, "message");
      self->Offer(title == nullptr ? "Vela" : title,
                   message == nullptr ? "Incoming transfer" : message);
    } else if (strcmp(method, "clearOffer") == 0) {
      self->ClearOffer();
    } else if (strcmp(method, "setTrayLabels") == 0) {
      const auto* open = StringArgument(arguments, "open");
      const auto* quit = StringArgument(arguments, "quit");
      if (open == nullptr || *open == '\0' || quit == nullptr || *quit == '\0') {
        fl_method_call_respond_error(call, "arguments",
                                     "Expected Open and Quit labels", nullptr,
                                     nullptr);
        return;
      }
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_item_), open);
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->quit_item_), quit);
    } else if (strcmp(method, "setNodeStatus") == 0) {
      if (arguments != nullptr &&
          fl_value_get_type(arguments) == FL_VALUE_TYPE_STRING) {
        const auto title = std::string("Vela · ") +
                           fl_value_get_string(arguments);
        app_indicator_set_title(self->indicator_, title.c_str());
      }
    } else if (strcmp(method, "setTransferring") != 0) {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    fl_method_call_respond_success(call, result, nullptr);
  }

  static void HandleFiles(FlMethodChannel*, FlMethodCall* call, gpointer) {
    const auto* method = fl_method_call_get_name(call);
    auto* arguments = fl_method_call_get_args(call);
    g_autofree gchar* uri = nullptr;
    if (strcmp(method, "openUrl") == 0) {
      const auto* value = StringArgument(arguments, "url");
      g_autoptr(GUri) parsed = value == nullptr
                                 ? nullptr
                                 : g_uri_parse(value, G_URI_FLAGS_NONE, nullptr);
      const auto* scheme = parsed == nullptr ? nullptr : g_uri_get_scheme(parsed);
      if (scheme == nullptr || g_uri_get_host(parsed) == nullptr ||
          (g_ascii_strcasecmp(scheme, "https") != 0 &&
           g_ascii_strcasecmp(scheme, "http") != 0)) {
        fl_method_call_respond_error(call, "url", "Expected an HTTP(S) URL",
                                     nullptr, nullptr);
        return;
      }
      uri = g_strdup(value);
    } else if (strcmp(method, "reveal") == 0) {
      const auto* path = StringArgument(arguments, "path");
      if (path == nullptr || !g_path_is_absolute(path)) {
        fl_method_call_respond_error(call, "path", "Expected an absolute path",
                                     nullptr, nullptr);
        return;
      }
      g_autoptr(GFile) file = g_file_new_for_path(path);
      g_autoptr(GFile) parent = g_file_get_parent(file);
      const auto is_directory =
          g_file_query_file_type(file, G_FILE_QUERY_INFO_NONE, nullptr) ==
          G_FILE_TYPE_DIRECTORY;
      uri = g_file_get_uri(is_directory || parent == nullptr ? file : parent);
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    g_autoptr(GError) error = nullptr;
    if (g_app_info_launch_default_for_uri(uri, nullptr, &error)) {
      fl_method_call_respond_success(call, nullptr, nullptr);
    } else {
      fl_method_call_respond_error(call, "open", error->message, nullptr, nullptr);
    }
  }

  static void HandleClipboard(FlMethodChannel*, FlMethodCall* call, gpointer) {
    if (strcmp(fl_method_call_get_name(call), "writeImage") != 0) {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    auto* arguments = fl_method_call_get_args(call);
    auto* bytes = arguments != nullptr &&
                          fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
                      ? fl_value_lookup_string(arguments, "bytes")
                      : nullptr;
    if (bytes == nullptr || fl_value_get_type(bytes) != FL_VALUE_TYPE_UINT8_LIST ||
        fl_value_get_length(bytes) == 0) {
      fl_method_call_respond_error(call, "clipboard", "Expected image bytes",
                                   nullptr, nullptr);
      return;
    }
    g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
    g_autoptr(GError) error = nullptr;
    auto loaded = gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(bytes),
                                          fl_value_get_length(bytes), &error);
    if (loaded) {
      loaded = gdk_pixbuf_loader_close(loader, &error);
    } else {
      gdk_pixbuf_loader_close(loader, nullptr);
    }
    auto* image = gdk_pixbuf_loader_get_pixbuf(loader);
    if (!loaded || image == nullptr) {
      fl_method_call_respond_error(
          call, "clipboard", error == nullptr ? "Cannot decode image" : error->message,
          nullptr, nullptr);
      return;
    }
    auto* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_image(clipboard, image);
    gtk_clipboard_set_can_store(clipboard, nullptr, 0);
    gtk_clipboard_store(clipboard);
    fl_method_call_respond_success(call, nullptr, nullptr);
  }
};

}  // namespace

void vela_desktop_register(FlBinaryMessenger* messenger,
                           GtkApplication* application, GtkWindow* window) {
  auto* integration = new DesktopIntegration(messenger, application, window);
  g_object_set_data_full(G_OBJECT(application), "vela-desktop", integration,
                        [](gpointer data) {
                          delete static_cast<DesktopIntegration*>(data);
                        });
}
