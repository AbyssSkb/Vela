#include <glib.h>

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <string>

static bool regular_owned_file(const char* path, struct stat* info) {
  return lstat(path, info) == 0 && S_ISREG(info->st_mode) &&
         info->st_uid == getuid();
}

static bool matches_hash(const char* path, const char* expected) {
  int fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return false;
  GChecksum* checksum = g_checksum_new(G_CHECKSUM_SHA256);
  unsigned char buffer[64 * 1024];
  ssize_t size;
  do {
    size = read(fd, buffer, sizeof(buffer));
    if (size > 0) g_checksum_update(checksum, buffer, size);
  } while (size > 0 || (size < 0 && errno == EINTR));
  bool valid = size == 0 && strcmp(g_checksum_get_string(checksum), expected) == 0;
  g_checksum_free(checksum);
  close(fd);
  return valid;
}

static void sync_directory(const char* path) {
  gchar* parent = g_path_get_dirname(path);
  int fd = open(parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (fd >= 0) {
    fsync(fd);
    close(fd);
  }
  g_free(parent);
}

static void clean_environment() {
  // AppImage's inherited mount paths belong to the old application.
  for (const char* key : {"APPIMAGE", "APPDIR", "ARGV0", "LD_LIBRARY_PATH"}) {
    unsetenv(key);
  }
}

static bool launch(const char* path) {
  int errors[2];
  if (pipe2(errors, O_CLOEXEC) != 0) return false;
  pid_t child = fork();
  if (child == 0) {
    close(errors[0]);
    clean_environment();
    execl(path, path, static_cast<char*>(nullptr));
    int error = errno;
    ssize_t ignored = write(errors[1], &error, sizeof(error));
    (void)ignored;
    _exit(127);
  }
  close(errors[1]);
  if (child < 0) {
    close(errors[0]);
    return false;
  }
  int error = 0;
  ssize_t count;
  do {
    count = read(errors[0], &error, sizeof(error));
  } while (count < 0 && errno == EINTR);
  close(errors[0]);
  return count == 0;
}

int main(int argc, char** argv) {
  if (argc != 8) return 2;
  const char* target = argv[1];
  const char* staged = argv[2];
  const char* backup = argv[3];
  const char* checksum = argv[4];
  const pid_t parent = static_cast<pid_t>(g_ascii_strtoll(argv[5], nullptr, 10));
  const guint64 device = g_ascii_strtoull(argv[6], nullptr, 10);
  const guint64 inode = g_ascii_strtoull(argv[7], nullptr, 10);
  if (parent <= 1 || strlen(checksum) != 64) return 2;

  unlink(argv[0]);
  // Wait for the application to exit deliberately; never terminate it here.
  bool exited = false;
  for (int attempt = 0; attempt < 1200; ++attempt) {
    if (kill(parent, 0) < 0 && errno == ESRCH) {
      exited = true;
      break;
    }
    g_usleep(50 * 1000);
  }
  if (!exited) {
    unlink(staged);
    return 3;
  }

  struct stat current;
  struct stat replacement;
  if (!regular_owned_file(target, &current) ||
      !regular_owned_file(staged, &replacement) ||
      static_cast<guint64>(current.st_dev) != device ||
      static_cast<guint64>(current.st_ino) != inode ||
      !matches_hash(staged, checksum)) {
    unlink(staged);
    launch(target);
    return 4;
  }

  // A hard link retains the old executable without a gap in the target path.
  if (link(target, backup) != 0) {
    unlink(staged);
    launch(target);
    return 5;
  }
  if (rename(staged, target) != 0) {
    unlink(staged);
    unlink(backup);
    launch(target);
    return 6;
  }
  sync_directory(target);
  if (!launch(target)) {
    if (rename(backup, target) == 0) sync_directory(target);
    launch(target);
    return 7;
  }
  // shortcut: rollback covers exec failure; add a startup acknowledgement before health-based rollback.
  unlink(backup);
  sync_directory(target);
  return 0;
}
