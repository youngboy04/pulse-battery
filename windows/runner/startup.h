#pragma once
#include <windows.h>
#include <string>

namespace suite {
inline constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
inline std::wstring StartupCommand() {
  wchar_t path[32768]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, 32768);
  return L"\"" + std::wstring(path, length) + L"\" --startup";
}
inline bool StartupEnabled(const wchar_t* name) {
  wchar_t value[32768]{}; DWORD bytes = sizeof(value);
  return RegGetValueW(HKEY_CURRENT_USER, kRunKey, name, RRF_RT_REG_SZ,
    nullptr, value, &bytes) == ERROR_SUCCESS && std::wstring(value) == StartupCommand();
}
inline LONG SetStartup(const wchar_t* name, bool enabled) {
  HKEY key{};
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0,
    KEY_SET_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) return status;
  if (enabled) {
    const auto command = StartupCommand();
    status = RegSetValueExW(key, name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, name);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return status;
}
}  // namespace suite
