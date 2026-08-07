#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

#include "app_links/app_links_plugin_c_api.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  if (SendAppLinkToInstance(title))
  {
    return false;
  }

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      RecordEvent("WM_DPICHANGED dpi=" + std::to_string(LOWORD(wparam)) +
                  " window=" + std::to_string(newWidth) + "x" +
                  std::to_string(newHeight));

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      const SurfaceMetrics metrics = SynchronizeChildContent();
      RecordEvent("WM_SIZE wparam=" + std::to_string(wparam) + " client=" +
                  std::to_string(metrics.client_width) + "x" +
                  std::to_string(metrics.client_height) + " child=" +
                  std::to_string(metrics.child_width) + "x" +
                  std::to_string(metrics.child_height));
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  const SurfaceMetrics metrics = SynchronizeChildContent();
  RecordEvent("SetChildContent client=" + std::to_string(metrics.client_width) +
              "x" + std::to_string(metrics.client_height) + " child=" +
              std::to_string(metrics.child_width) + "x" +
              std::to_string(metrics.child_height));

  SetFocus(child_content_);
}

Win32Window::SurfaceMetrics Win32Window::SynchronizeChildContent(
    bool force_resync) {
  const RECT client_area = GetClientArea();
  const LONG client_width = client_area.right - client_area.left;
  const LONG client_height = client_area.bottom - client_area.top;

  LONG child_width = 0;
  LONG child_height = 0;
  if (child_content_ != nullptr) {
    if (force_resync && client_width > 0 && client_height > 0) {
      // See the comment on the declaration: a same-size MoveWindow produces no
      // WM_SIZE, so the engine would never re-negotiate its render surface.
      // The extra pixel is clipped by the parent and never reaches the screen.
      MoveWindow(child_content_, client_area.left, client_area.top,
                 client_width, client_height + 1, FALSE);
      RecordEvent("resync nudge client=" + std::to_string(client_width) + "x" +
                  std::to_string(client_height));
    }

    MoveWindow(child_content_, client_area.left, client_area.top, client_width,
               client_height, TRUE);
    if (force_resync) {
      InvalidateRect(child_content_, nullptr, TRUE);
      RedrawWindow(child_content_, nullptr, nullptr,
                   RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
    }

    RECT child_area{};
    if (GetClientRect(child_content_, &child_area)) {
      child_width = child_area.right - child_area.left;
      child_height = child_area.bottom - child_area.top;
    }
  }

  return {client_width, client_height, child_width, child_height};
}

void Win32Window::ResyncTopLevelSurface() {
  if (window_handle_ == nullptr) {
    return;
  }

  RECT window_rect{};
  if (!GetWindowRect(window_handle_, &window_rect)) {
    return;
  }

  const LONG width = window_rect.right - window_rect.left;
  const LONG height = window_rect.bottom - window_rect.top;
  if (width <= 0 || height <= 0) {
    return;
  }

  RecordEvent("resync toplevel begin " + DescribeGeometry());

  constexpr UINT kFlags = SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE |
                          SWP_NOACTIVATE | SWP_FRAMECHANGED;
  SetWindowPos(window_handle_, nullptr, window_rect.left, window_rect.top,
               width, height + 1, kFlags);
  SetWindowPos(window_handle_, nullptr, window_rect.left, window_rect.top,
               width, height, kFlags);

  RecordEvent("resync toplevel end " + DescribeGeometry());
}

std::string Win32Window::DescribeGeometry() {
  auto rect_to_string = [](const RECT& rect) {
    return std::to_string(rect.right - rect.left) + "x" +
           std::to_string(rect.bottom - rect.top) + "@(" +
           std::to_string(rect.left) + "," + std::to_string(rect.top) + ")";
  };

  std::string description;
  RECT rect{};
  if (window_handle_ != nullptr) {
    if (GetWindowRect(window_handle_, &rect)) {
      description += "win=" + rect_to_string(rect);
    }
    if (GetClientRect(window_handle_, &rect)) {
      description += " winClient=" + rect_to_string(rect);
    }
    description += " visible=" + std::to_string(IsWindowVisible(window_handle_));
    description += " dpi=" + std::to_string(FlutterDesktopGetDpiForHWND(window_handle_));
  }
  if (child_content_ != nullptr) {
    if (GetWindowRect(child_content_, &rect)) {
      // Map to the parent's client space so an offset child is obvious.
      POINT top_left{rect.left, rect.top};
      ScreenToClient(window_handle_, &top_left);
      description += " child=" + std::to_string(rect.right - rect.left) + "x" +
                     std::to_string(rect.bottom - rect.top) + "@(" +
                     std::to_string(top_left.x) + "," +
                     std::to_string(top_left.y) + ")";
    }
    if (GetClientRect(child_content_, &rect)) {
      description += " childClient=" + rect_to_string(rect);
    }
    description +=
        " childDpi=" + std::to_string(FlutterDesktopGetDpiForHWND(child_content_));
  }
  return description;
}

void Win32Window::RecordEvent(const std::string& event) {
  // Bounded buffer: the interesting window is startup, and the Dart side
  // drains it after the first frame.
  constexpr size_t kMaxGeometryEvents = 32;
  if (geometry_events_.size() >= kMaxGeometryEvents) {
    geometry_events_.erase(geometry_events_.begin());
  }
  geometry_events_.push_back(event);
}

std::vector<std::string> Win32Window::TakeGeometryEvents() {
  std::vector<std::string> events;
  events.swap(geometry_events_);
  return events;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}

bool Win32Window::SendAppLinkToInstance(const std::wstring &title)
{
  // Find our exact window
  HWND hwnd = ::FindWindow(kWindowClassName, title.c_str());

  if (hwnd)
  {
    // Dispatch new link to current window
    SendAppLink(hwnd);

    // (Optional) Restore our window to front in same state
    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &place);

    switch (place.showCmd)
    {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
    }

    SetWindowPos(0, HWND_TOP, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hwnd);

    // Window has been found, don't create another one.
    return true;
  }

  return false;
}
