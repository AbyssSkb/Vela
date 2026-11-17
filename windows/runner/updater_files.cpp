#include "updater_files.h"

#include <bcrypt.h>
#include <shlobj.h>

#include <array>
#include <vector>

namespace vela_update {
std::optional<std::wstring> ToWide(const std::string& value) {
  if (value.empty() || value.size() > 32767 ||
      value.find('\0') != std::string::npos) {
    return std::nullopt;
  }
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                     value.data(), static_cast<int>(value.size()),
                                     nullptr, 0);
  if (!size) return std::nullopt;
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::optional<std::string> ToUtf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                     static_cast<int>(value.size()), nullptr, 0,
                                     nullptr, nullptr);
  if (!size) return std::nullopt;
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::optional<std::filesystem::path> UpdateDirectory() {
  PWSTR local_data = nullptr;
  const HRESULT status = SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                             &local_data);
  if (FAILED(status)) return std::nullopt;
  const auto path = std::filesystem::path(local_data) / L"Vela" / L"Updates";
  CoTaskMemFree(local_data);
  std::error_code error;
  std::filesystem::create_directories(path, error);
  if (error) return std::nullopt;
  return path;
}

std::optional<std::wstring> FinalPath(HANDLE handle) {
  const DWORD length = GetFinalPathNameByHandleW(handle, nullptr, 0, 0);
  if (!length || length > 32767) return std::nullopt;
  std::wstring path(length, L'\0');
  const DWORD written = GetFinalPathNameByHandleW(handle, path.data(), length, 0);
  if (!written || written >= length) return std::nullopt;
  path.resize(written);
  return path;
}

Handle OpenInstaller(const std::wstring& path) {
  const auto directory = UpdateDirectory();
  if (!directory) return {};
  const HANDLE raw_directory = CreateFileW(
      directory->c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr);
  if (raw_directory == INVALID_HANDLE_VALUE) return {};
  const Handle directory_handle(raw_directory, CloseHandle);
  FILE_ATTRIBUTE_TAG_INFO directory_info{};
  if (!GetFileInformationByHandleEx(raw_directory, FileAttributeTagInfo,
                                    &directory_info, sizeof(directory_info)) ||
      (directory_info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
    return {};
  }
  const auto directory_path = FinalPath(raw_directory);
  if (!directory_path) return {};

  const HANDLE raw_file = CreateFileW(
      path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
  if (raw_file == INVALID_HANDLE_VALUE) return {};
  const Handle file(raw_file, CloseHandle);
  FILE_ATTRIBUTE_TAG_INFO file_info{};
  if (!GetFileInformationByHandleEx(raw_file, FileAttributeTagInfo, &file_info,
                                    sizeof(file_info)) ||
      (file_info.FileAttributes &
          (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
    return {};
  }
  const auto final_path = FinalPath(raw_file);
  const auto prefix = *directory_path + L"\\";
  if (!final_path || final_path->size() <= prefix.size() ||
      CompareStringOrdinal(final_path->data(), static_cast<int>(prefix.size()),
                           prefix.data(), static_cast<int>(prefix.size()),
                           TRUE) != CSTR_EQUAL) {
    return {};
  }
  if (final_path->find_first_of(L"\\/", prefix.size()) != std::wstring::npos) {
    return {};
  }
  const auto extension = std::filesystem::path(*final_path).extension().wstring();
  if (CompareStringOrdinal(extension.c_str(), -1, L".exe", -1, TRUE) !=
      CSTR_EQUAL) {
    return {};
  }
  return file;
}

bool MatchesHash(HANDLE file, const std::string& expected) {
  if (expected.size() != 64 || expected.find_first_not_of("0123456789abcdef") !=
                                   std::string::npos) {
    return false;
  }
  LARGE_INTEGER start{};
  if (!SetFilePointerEx(file, start, nullptr, FILE_BEGIN)) return false;
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  0) < 0) {
    return false;
  }
  const std::shared_ptr<void> algorithm_handle(algorithm, [](void* value) {
    BCryptCloseAlgorithmProvider(value, 0);
  });
  DWORD object_size = 0;
  DWORD returned = 0;
  if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                        reinterpret_cast<PUCHAR>(&object_size),
                        sizeof(object_size), &returned, 0) < 0) {
    return false;
  }
  std::vector<UCHAR> object(object_size);
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptCreateHash(algorithm, &hash, object.data(), object_size, nullptr, 0,
                       0) < 0) {
    return false;
  }
  const std::shared_ptr<void> hash_handle(hash, [](void* value) {
    BCryptDestroyHash(value);
  });
  std::array<UCHAR, 64 * 1024> buffer;
  for (;;) {
    DWORD read = 0;
    if (!ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()), &read,
                   nullptr)) {
      return false;
    }
    if (!read) break;
    if (BCryptHashData(hash, buffer.data(), read, 0) < 0) return false;
  }
  std::array<UCHAR, 32> digest;
  if (BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()),
                       0) < 0) {
    return false;
  }
  constexpr char hex[] = "0123456789abcdef";
  unsigned difference = 0;
  for (size_t i = 0; i < digest.size(); ++i) {
    difference |= expected[2 * i] ^ hex[digest[i] >> 4];
    difference |= expected[2 * i + 1] ^ hex[digest[i] & 15];
  }
  return difference == 0;
}

}  // namespace vela_update
