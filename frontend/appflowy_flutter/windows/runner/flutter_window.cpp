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

// Posted to ourselves to run the surface resync outside of the method channel
// handler. The resync makes the engine re-negotiate its render surface, and
// that handshake waits for the raster thread to present a frame - which cannot
// happen while the Dart isolate is blocked awaiting our channel reply.
//
// A registered message is used rather than WM_APP+n: the WM_APP range is
// per-window private and a plugin window proc delegate could legitimately claim
// the same value, silently swallowing the resync (which is what happened with
// WM_APP + 0x4D2 in 1.1.13).
UINT ResyncSurfaceMessage() {
  static const UINT message =
      RegisterWindowMessageW(L"PonyNotesResyncWindowSurface");
  return message;
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

  window_surface_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowSurfaceChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_surface_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        SynchronizeSurface(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    // Safety net only. main.cpp deliberately does not show the window, and
    // window_manager shows it from Dart once the geometry is final. If the Dart
    // side never got there (early failure), show it here so the app is not
    // invisible. Showing an already visible window is a no-op.
    if (!IsWindowVisible(GetHandle())) {
      RecordEvent("first frame: showing window as fallback");
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
  if (window_surface_channel_) {
    window_surface_channel_->SetMethodCallHandler(nullptr);
  }
  if (pending_surface_result_) {
    pending_surface_result_->Error(
        "WINDOW_SURFACE_DESTROYED",
        "The window was destroyed before surface synchronization completed.");
    pending_surface_result_.reset();
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
  // Handled before the plugins get a chance, so nothing can swallow it.
  if (message == ResyncSurfaceMessage()) {
    RecordEvent("resync handler ran");
    const bool resync_succeeded = ResyncTopLevelSurface();
    if (flutter_controller_) {
      flutter_controller_->ForceRedraw();
    }

    if (pending_surface_result_) {
      auto result = std::move(pending_surface_result_);
      if (!resync_succeeded) {
        result->Error("WINDOW_SURFACE_RESYNC_FAILED",
                      "The native window surface could not be resynchronized.");
        return 0;
      }

      const SurfaceMetrics metrics = SynchronizeChildContent(false);
      const std::string geometry = DescribeGeometry();

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
          {flutter::EncodableValue("geometry"),
           flutter::EncodableValue(geometry)},
      };
      result->Success(flutter::EncodableValue(dimensions));
    }
    return 0;
  }

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

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SynchronizeSurface(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != kSynchronizeSurfaceMethod) {
    result->NotImplemented();
    return;
  }

  if (pending_surface_result_) {
    result->Error("WINDOW_SURFACE_BUSY",
                  "Another Windows surface synchronization is still pending.");
    return;
  }

  // Align the child immediately, but hold the Dart result until the posted
  // top-level resync has run. The platform thread must return to its message
  // loop before the resync, otherwise the Flutter raster thread cannot present
  // the frame that the resize handshake waits for.
  SynchronizeChildContent(false);
  pending_surface_result_ = std::move(result);

  const UINT message = ResyncSurfaceMessage();
  if (message == 0 || !PostMessage(GetHandle(), message, 0, 0)) {
    auto pending_result = std::move(pending_surface_result_);
    pending_result->Error(
        "WINDOW_SURFACE_POST_FAILED",
        "The native surface resync message could not be posted.");
  }
}
