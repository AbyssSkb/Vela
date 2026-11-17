#include "updater.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

namespace {

struct UpdateState {
  FlMethodChannel* channel;
  GApplication* application;
  bool busy = true;
  bool installing = false;
};

struct PendingInstall {
  std::shared_ptr<UpdateState> state;
  FlMethodCall* call;
  std::string source;
  std::string checksum;
  std::string target;
  std::string staged;
  std::string helper;
  std::string backup;
  struct stat original;

  ~PendingInstall() {
    if (!staged.empty()) unlink(staged.c_str());
    if (!helper.empty()) unlink(helper.c_str());
    g_object_unref(call);
  }
};

static FlValue* argument(FlMethodCall* call, const char* name) {
  FlValue* args = fl_method_call_get_args(call);
  return fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, name)
             : nullptr;
}

static const char* string_argument(FlMethodCall* call, const char* name) {
  FlValue* value = argument(call, name);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

static void error(FlMethodCall* call, const char* code, const char* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

static std::string update_directory() {
  g_autofree gchar* path =
      g_build_filename(g_get_user_cache_dir(), "vela", "vela-updates", nullptr);
  if (g_mkdir_with_parents(path, 0700) != 0) return {};
  g_autofree gchar* canonical = realpath(path, nullptr);
  return canonical ? canonical : "";
}

static bool same_parent(const char* path, const std::string& directory) {
  g_autofree gchar* parent = g_path_get_dirname(path);
  return directory == parent;
}

static bool appimage_header(int fd) {
  unsigned char header[11];
  return pread(fd, header, sizeof(header), 0) == static_cast<ssize_t>(sizeof(header)) &&
         memcmp(header, "\x7f" "ELF", 4) == 0 && header[8] == 'A' &&
         header[9] == 'I' && header[10] == 2;
}

static std::string stage_file(const char* source, const std::string& target,
                              const char* kind, const char* checksum,
                              bool require_appimage, GError** error_out) {
  int input = open(source, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  struct stat metadata;
  if (input < 0 || fstat(input, &metadata) != 0 ||
      !S_ISREG(metadata.st_mode) ||
      (require_appimage && metadata.st_uid != getuid()) ||
      (require_appimage && !appimage_header(input))) {
    if (input >= 0) close(input);
    g_set_error_literal(error_out, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                        "Update is not a regular AppImage owned by this user");
    return {};
  }
  g_autofree gchar* directory = g_path_get_dirname(target.c_str());
  g_autofree gchar* name = g_strdup_printf("%s/.vela-%s-XXXXXX", directory, kind);
  int output = g_mkstemp_full(name, O_RDWR | O_CLOEXEC, 0700);
  if (output < 0) {
    close(input);
    g_set_error_literal(error_out, G_IO_ERROR, G_IO_ERROR_PERMISSION_DENIED,
                        "Cannot write next to this AppImage; move it to a writable folder");
    return {};
  }
  GChecksum* digest = g_checksum_new(G_CHECKSUM_SHA256);
  bool copied = true;
  unsigned char buffer[64 * 1024];
  while (copied) {
    ssize_t count = read(input, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      copied = count == 0;
      break;
    }
    g_checksum_update(digest, buffer, count);
    ssize_t written = 0;
    while (written < count) {
      ssize_t size = write(output, buffer + written, count - written);
      if (size < 0 && errno == EINTR) continue;
      if (size <= 0) {
        copied = false;
        break;
      }
      written += size;
    }
  }
  bool verified = !checksum || strcmp(checksum, g_checksum_get_string(digest)) == 0;
  bool synced = fsync(output) == 0;
  g_checksum_free(digest);
  close(input);
  close(output);
  if (!copied || !verified || !synced) {
    unlink(name);
    g_set_error_literal(error_out, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                        "Cannot stage or verify the downloaded update");
    return {};
  }
  return name;
}

static void stage_install(GTask* task, gpointer, gpointer task_data,
                          GCancellable*) {
  auto* pending = static_cast<PendingInstall*>(task_data);
  g_autoptr(GError) failure = nullptr;
  pending->staged = stage_file(pending->source.c_str(), pending->target,
                              "update", pending->checksum.c_str(), true, &failure);
  if (!pending->staged.empty()) {
    g_autofree gchar* executable = g_file_read_link("/proc/self/exe", &failure);
    if (executable) {
      g_autofree gchar* directory = g_path_get_dirname(executable);
      g_autofree gchar* helper =
          g_build_filename(directory, "vela_update_helper", nullptr);
      pending->helper = stage_file(helper, pending->target, "updater", nullptr,
                                  false, &failure);
    }
  }
  if (failure) g_task_return_error(task, static_cast<GError*>(g_steal_pointer(&failure)));
  else g_task_return_boolean(task, !pending->staged.empty() && !pending->helper.empty());
}

static void prepared(GObject* source, GAsyncResult* result, gpointer user_data) {
  std::unique_ptr<PendingInstall> pending(static_cast<PendingInstall*>(user_data));
  pending->state->installing = false;
  g_autoptr(GError) failure = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source), result, &failure);
  FlValue* approved = response ? fl_method_response_get_result(response, &failure) : nullptr;
  if (!approved || fl_value_get_type(approved) != FL_VALUE_TYPE_BOOL ||
      !fl_value_get_bool(approved)) {
    error(pending->call, "busy", "Update installation was not approved");
    return;
  }
  std::string pid = std::to_string(getpid());
  std::string device = std::to_string(pending->original.st_dev);
  std::string inode = std::to_string(pending->original.st_ino);
  const gchar* arguments[] = {
      pending->helper.c_str(), pending->target.c_str(), pending->staged.c_str(),
      pending->backup.c_str(), pending->checksum.c_str(), pid.c_str(),
      device.c_str(), inode.c_str(), nullptr};
  g_autofree gchar* directory = g_path_get_dirname(pending->target.c_str());
  if (!g_spawn_async(directory, const_cast<gchar**>(arguments), nullptr,
                     G_SPAWN_DEFAULT, nullptr, nullptr, nullptr, &failure)) {
    error(pending->call, "install_failed", failure->message);
    return;
  }
  pending->staged.clear();
  pending->helper.clear();
  fl_method_call_respond_success(pending->call, nullptr, nullptr);
  g_application_quit(pending->state->application);
}

static void staged(GObject*, GAsyncResult* result, gpointer user_data) {
  auto* pending = static_cast<PendingInstall*>(user_data);
  g_autoptr(GError) failure = nullptr;
  bool ok = g_task_propagate_boolean(G_TASK(result), &failure);
  if (!ok || pending->state->busy) {
    pending->state->installing = false;
    error(pending->call, failure && failure->code == G_IO_ERROR_PERMISSION_DENIED
                             ? "read_only" : "invalid_update",
          failure ? failure->message : "Finish transfers before installing the update");
    delete pending;
    return;
  }
  fl_method_channel_invoke_method(pending->state->channel, "prepareInstall", nullptr,
                                  nullptr, prepared, pending);
}

static void handle(FlMethodChannel*, FlMethodCall* call, gpointer user_data) {
  auto state = *static_cast<std::shared_ptr<UpdateState>*>(user_data);
  const char* method = fl_method_call_get_name(call);
  if (strcmp(method, "setBusy") == 0) {
    FlValue* value = argument(call, "busy");
    state->busy = !value || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL ||
                  fl_value_get_bool(value);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "info") == 0) {
    struct utsname system;
    uname(&system);
    const char* arch = strcmp(system.machine, "x86_64") == 0 ? "x64" :
                       strcmp(system.machine, "aarch64") == 0 ? "arm64" : system.machine;
    g_autoptr(FlValue) info = fl_value_new_map();
    fl_value_set_string_take(info, "arch", fl_value_new_string(arch));
    fl_method_call_respond_success(call, info, nullptr);
  } else if (strcmp(method, "configure") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (strcmp(method, "getUpdateDirectory") == 0) {
    std::string directory = update_directory();
    if (directory.empty()) error(call, "read_only", "Cannot create Vela's update cache");
    else {
      g_autoptr(FlValue) value = fl_value_new_string(directory.c_str());
      fl_method_call_respond_success(call, value, nullptr);
    }
  } else if (strcmp(method, "canInstall") == 0) {
    g_autoptr(FlValue) value = fl_value_new_bool(g_getenv("APPIMAGE") != nullptr);
    fl_method_call_respond_success(call, value, nullptr);
  } else if (strcmp(method, "installDownloaded") == 0) {
    if (state->busy || state->installing) {
      error(call, "busy", "Finish transfers and pairing before installing an update");
      return;
    }
    const char* source = string_argument(call, "path");
    const char* checksum = string_argument(call, "sha256");
    const char* appimage = g_getenv("APPIMAGE");
    g_autofree gchar* target = appimage ? realpath(appimage, nullptr) : nullptr;
    struct stat original;
    if (!source || !checksum || strlen(checksum) != 64 ||
        strspn(checksum, "0123456789abcdef") != 64 || !target ||
        !g_str_has_suffix(source, ".AppImage") ||
        !same_parent(source, update_directory()) ||
        lstat(target, &original) != 0 || !S_ISREG(original.st_mode)) {
      error(call, "invalid_update", "Run the installed AppImage and use Vela's verified update cache");
      return;
    }
    if (original.st_uid != getuid()) {
      error(call, "read_only", "Move Vela's AppImage to a folder owned by your user before updating");
      return;
    }
    auto* pending = new PendingInstall{state, FL_METHOD_CALL(g_object_ref(call)),
        source, checksum, target, "", "", "", original};
    pending->backup = pending->target + ".vela-previous-" + std::to_string(g_random_int());
    state->installing = true;
    g_autoptr(GTask) task = g_task_new(nullptr, nullptr, staged, pending);
    g_task_set_task_data(task, pending, nullptr);
    g_task_run_in_thread(task, stage_install);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
  }
}

}  // namespace

void vela_update_register(FlBinaryMessenger* messenger, GApplication* application) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "vela/update", FL_METHOD_CODEC(codec));
  auto state = std::make_shared<UpdateState>();
  state->channel = channel;
  state->application = application;
  fl_method_channel_set_method_call_handler(channel, handle,
      new std::shared_ptr<UpdateState>(state), [](gpointer pointer) {
        delete static_cast<std::shared_ptr<UpdateState>*>(pointer);
      });
}
