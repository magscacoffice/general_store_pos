#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "startup_diagnostics.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  LogWindowsStartup("Process entry reached.");

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
