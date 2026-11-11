#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "startup_diagnostics.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  LogWindowsStartup("FlutterWindow::OnCreate entered.");
  if (!Win32Window::OnCreate()) {
    LogWindowsStartup("Base Win32Window::OnCreate failed.");
    return false;
  }

  RECT frame = GetClientArea();
  LogWindowsStartup("Constructing FlutterViewController.");
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    LogWindowsStartup("Flutter engine or view initialization failed.");
    return false;
  }
  LogWindowsStartup("Flutter engine and view initialized.");

  LogWindowsStartup("Registering Windows plugins.");
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    if (view_controller && view_controller->engine()) {
      RegisterPlugins(view_controller->engine());
    }
  });
  LogWindowsStartup("Windows plugins registered for the main and secondary windows.");

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  LogWindowsStartup("Flutter child view attached to host window.");

  // Show immediately so an early first-frame stall cannot leave the native
  // application window hidden with no visible indication that it launched.
  Show();
  LogWindowsStartup("Native host window shown; waiting for first Flutter frame.");

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    LogWindowsStartup("First Flutter frame callback received.");
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  LogWindowsStartup("Flutter ForceRedraw requested.");
  return true;
}

void FlutterWindow::OnDestroy() {
  LogWindowsStartup("FlutterWindow::OnDestroy entered.");
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
