#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "startup_diagnostics.h"
#include "utils.h"

namespace {
bool RegisterKhanBabaPosStartup() {
  wchar_t executable_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return false;

  const std::wstring command =
      L"\"" + std::wstring(executable_path, length) + L"\"";
  HKEY startup_key = nullptr;
  const LONG open_result = RegCreateKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
      0, nullptr, 0, KEY_SET_VALUE, nullptr, &startup_key, nullptr);
  if (open_result != ERROR_SUCCESS) return false;

  const LONG write_result = RegSetValueExW(
      startup_key, L"KhanBabaPOS", 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()),
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(startup_key);
  return write_result == ERROR_SUCCESS;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  LogWindowsStartup("Process entry reached.");
  LogWindowsStartup(RegisterKhanBabaPosStartup()
                        ? "Khan Baba POS registered to start at Windows sign-in."
                        : "Could not register Khan Baba POS for Windows sign-in.");

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  LogWindowsStartup(SUCCEEDED(com_result)
                        ? "COM initialized."
                        : "COM initialization returned a failure status.");

  flutter::DartProject project(L"data");
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  LogWindowsStartup("Dart project configured.");

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  LogWindowsStartup("Creating Flutter host window.");
  if (!window.Create(L"Khan Baba General Store POS", origin, size)) {
    LogWindowsStartup("Flutter host window creation failed.");
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  LogWindowsStartup("Flutter host window created.");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  LogWindowsStartup("Windows message loop ended.");
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
