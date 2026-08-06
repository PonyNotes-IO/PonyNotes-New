#include "flutter_window.h"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowSurfaceChannel[] = "ponynotes/window_surface";
constexpr char kSynchronizeSurfaceMethod[] = "synchronizeSurface";

// Posted to ourselves to run the surface resync nudge outside of the method
// channel handler. The nudge makes the engine re-negotiate its render surface,
// and that handshake waits for the raster thread to present a frame - which
// cannot happen while the Dart isolate is blocked awaiting our channel reply.
// The offset is arbitrary but distinctive, to avoid colliding with a plugin
// that also posts private messages to the top-level window.
constexpr UINT kResyncSurfaceMessage = WM_APP + 0x4D2;

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

  window_surface_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowSurfaceChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_surface_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        SynchronizeSurface(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // https://pub.dev/packages/window_manager#windows
    // this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_surface_channel_) {
    window_surface_channel_->SetMethodCallHandler(nullptr);
  }
  window_surface_channel_ = nullptr;
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
    case kResyncSurfaceMessage:
      SynchronizeChildContent(true);
      if (flutter_controller_) {
        flutter_controller_->ForceRedraw();
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SynchronizeSurface(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != kSynchronizeSurfaceMethod) {
    result->NotImplemented();
    return;
  }

  // Measure and re-align the child synchronously so the reply carries the
  // current geometry, then run the actual resync nudge from the message loop
  // (see kResyncSurfaceMessage) to keep this handler non-blocking.
  const SurfaceMetrics metrics = SynchronizeChildContent(false);
  PostMessage(GetHandle(), kResyncSurfaceMessage, 0, 0);

  flutter::EncodableList events;
  for (const std::string& event : TakeGeometryEvents()) {
    events.push_back(flutter::EncodableValue(event));
  }

  flutter::EncodableMap dimensions = {
      {flutter::EncodableValue("clientWidth"),
       flutter::EncodableValue(static_cast<int32_t>(metrics.client_width))},
      {flutter::EncodableValue("clientHeight"),
       flutter::EncodableValue(static_cast<int32_t>(metrics.client_height))},
      {flutter::EncodableValue("childWidth"),
       flutter::EncodableValue(static_cast<int32_t>(metrics.child_width))},
      {flutter::EncodableValue("childHeight"),
       flutter::EncodableValue(static_cast<int32_t>(metrics.child_height))},
      {flutter::EncodableValue("events"), flutter::EncodableValue(events)},
  };
  result->Success(flutter::EncodableValue(dimensions));
}
