#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// DWMWINDOWATTRIBUTE values, spelled out because older SDKs lack them.
constexpr DWORD kDwmUseImmersiveDarkMode = 20;
// Windows 11 and later; older versions ignore them and keep the plain
// dark/light frame.
constexpr DWORD kDwmCaptionColor = 35;
constexpr DWORD kDwmTextColor = 36;

// Reads an ARGB colour sent as a Dart int into a COLORREF.
bool ReadColor(const flutter::EncodableMap& args, const char* key,
               COLORREF* color) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return false;
  }
  const flutter::EncodableValue& value = it->second;
  if (!std::holds_alternative<int32_t>(value) &&
      !std::holds_alternative<int64_t>(value)) {
    return false;
  }
  const int64_t argb = value.LongValue();
  *color = RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
  return true;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "musify/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleWindowCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (start_maximized_) {
      ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  const LRESULT result =
      Win32Window::MessageHandler(hwnd, message, wparam, lparam);

  // The base class resets the frame to the system theme on this message; put
  // the app's colours back on top.
  if (message == WM_DWMCOLORIZATIONCOLORCHANGED && has_title_bar_theme_) {
    ApplyTitleBarTheme();
  }

  return result;
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "maximize") {
    HWND hwnd = GetHandle();
    if (hwnd != nullptr && IsWindowVisible(hwnd)) {
      ShowWindow(hwnd, SW_MAXIMIZE);
    } else {
      start_maximized_ = true;
    }
    result->Success();
    return;
  }

  if (method == "setTitleBarTheme") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "Expected a map");
      return;
    }
    auto dark = args->find(flutter::EncodableValue("dark"));
    COLORREF background = 0;
    COLORREF foreground = 0;
    if (dark == args->end() || !std::holds_alternative<bool>(dark->second) ||
        !ReadColor(*args, "background", &background) ||
        !ReadColor(*args, "foreground", &foreground)) {
      result->Error("bad_args", "Expected dark, background and foreground");
      return;
    }
    title_bar_dark_ = std::get<bool>(dark->second);
    title_bar_background_ = background;
    title_bar_foreground_ = foreground;
    has_title_bar_theme_ = true;
    ApplyTitleBarTheme();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::ApplyTitleBarTheme() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  BOOL dark = title_bar_dark_ ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, kDwmUseImmersiveDarkMode, &dark, sizeof(dark));
  DwmSetWindowAttribute(hwnd, kDwmCaptionColor, &title_bar_background_,
                        sizeof(title_bar_background_));
  DwmSetWindowAttribute(hwnd, kDwmTextColor, &title_bar_foreground_,
                        sizeof(title_bar_foreground_));
}
