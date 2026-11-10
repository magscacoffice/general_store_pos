#ifndef RUNNER_STARTUP_DIAGNOSTICS_H_
#define RUNNER_STARTUP_DIAGNOSTICS_H_

#include <windows.h>

#include <cstdio>
#include <string>

inline void LogWindowsStartup(const char* message) {
  if (message == nullptr) return;
  OutputDebugStringA("[KhanBabaPOS] ");
  OutputDebugStringA(message);
  OutputDebugStringA("\n");

  wchar_t base[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    length = GetTempPathW(MAX_PATH, base);
  }
  if (length == 0 || length >= MAX_PATH) return;

  std::wstring app_dir(base);
  while (!app_dir.empty() &&
         (app_dir.back() == L'\\' || app_dir.back() == L'/')) {
    app_dir.pop_back();
  }
  app_dir += L"\\KhanBabaPOS";
  CreateDirectoryW(app_dir.c_str(), nullptr);

  const std::wstring log_dir = app_dir + L"\\Logs";
  CreateDirectoryW(log_dir.c_str(), nullptr);
  const std::wstring log_path = log_dir + L"\\native-startup.log";

  HANDLE file = CreateFileW(log_path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;

  SYSTEMTIME now = {};
  GetLocalTime(&now);
  char line[1200] = {};
  const int count = sprintf_s(
      line, sizeof(line), "[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s\r\n",
      now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
      now.wMilliseconds, message);
  if (count > 0) {
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(count), &written, nullptr);
  }
  CloseHandle(file);
}

#endif  // RUNNER_STARTUP_DIAGNOSTICS_H_
