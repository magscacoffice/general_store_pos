#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

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

  // Receive input notifications from external USB HID keyboards while this
  // host window is in the background. The dedicated barcode scanner is
  // identified by its USB VID/PID device path; barcode data itself is not
  // captured here.
  RAWINPUTDEVICE scanner_input{};
  scanner_input.usUsagePage = 0x01;
  scanner_input.usUsage = 0x06;
  scanner_input.dwFlags = RIDEV_INPUTSINK;
  scanner_input.hwndTarget = GetHandle();
  if (RegisterRawInputDevices(&scanner_input, 1, sizeof(scanner_input))) {
    LogWindowsStartup("Background USB keyboard input notification registered.");
  } else {
    LogWindowsStartup("Background USB keyboard input registration failed.");
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
  if (message == WM_INPUT) {
    const UINT input_code = GET_RAWINPUT_CODE_WPARAM(wparam);
    if (input_code != RIM_INPUT && input_code != RIM_INPUTSINK) {
      return DefWindowProc(hwnd, message, wparam, lparam);
    }
    UINT raw_size = 0;
    if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                        nullptr, &raw_size, sizeof(RAWINPUTHEADER)) == 0 &&
        raw_size >= sizeof(RAWINPUT)) {
      std::vector<BYTE> raw_buffer(raw_size);
      if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                          raw_buffer.data(), &raw_size,
                          sizeof(RAWINPUTHEADER)) == raw_size) {
        const RAWINPUT* raw =
            reinterpret_cast<const RAWINPUT*>(raw_buffer.data());
        if (raw->header.dwType == RIM_TYPEKEYBOARD &&
            (raw->data.keyboard.Message == WM_KEYDOWN ||
             raw->data.keyboard.Message == WM_SYSKEYDOWN)) {
          UINT name_length = 0;
          GetRawInputDeviceInfoW(raw->header.hDevice, RIDI_DEVICENAME,
                                 nullptr, &name_length);
          if (name_length > 0 && name_length < 4096) {
            std::wstring device_name(name_length, L'\0');
            if (GetRawInputDeviceInfoW(raw->header.hDevice, RIDI_DEVICENAME,
                                       device_name.data(), &name_length) !=
                static_cast<UINT>(-1)) {
              const bool usb_hid_keyboard =
                  device_name.find(L"VID_") != std::wstring::npos &&
                  device_name.find(L"PID_") != std::wstring::npos &&
                  device_name.find(L"HID#") != std::wstring::npos;
              if (usb_hid_keyboard) {
                HWND sale_window =
                    FindWindowW(nullptr, L"Khan Baba POS - New Sale");
                if (sale_window != nullptr && sale_window != hwnd) {
                  ShowWindow(sale_window, SW_RESTORE);
                  BringWindowToTop(sale_window);
                  SetForegroundWindow(sale_window);
                  SetFocus(sale_window);
                }
              }
            }
          }
        }
      }
    }
    // WM_INPUT requires DefWindowProc cleanup, including for sink input.
    DefWindowProc(hwnd, message, wparam, lparam);
    return 0;
  }

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
