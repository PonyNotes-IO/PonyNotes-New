#include "my_application.h"

#include <glib.h>

// 强制使用原生 Wayland 后端。
//
// 桌面处于 Wayland 会话时，GTK3 默认就会连 wayland；但只要进程从上层
// （IDE、tmux、某些启动器、CI 包装脚本）继承了 GDK_BACKEND=x11，应用就会被
// 按到 XWayland 上跑 —— 在 NVIDIA 驱动下这通常会得到一个全黑的窗口。
//
// 这里在 GTK 初始化（g_application_run 打开 display）之前显式锁定后端，
// 让 `fvm flutter run -d linux` 不再受继承环境的影响。
//
// 临时回退：APPFLOWY_GDK_BACKEND=x11 fvm flutter run -d linux
static void enforce_gdk_backend() {
  const gchar* override = g_getenv("APPFLOWY_GDK_BACKEND");
  if (override != nullptr && override[0] != '\0') {
    g_setenv("GDK_BACKEND", override, TRUE);
    return;
  }

  const gchar* session_type = g_getenv("XDG_SESSION_TYPE");
  const gchar* wayland_display = g_getenv("WAYLAND_DISPLAY");
  const gboolean is_wayland_session =
      (session_type != nullptr && g_strcmp0(session_type, "wayland") == 0) ||
      (wayland_display != nullptr && wayland_display[0] != '\0');

  if (is_wayland_session) {
    g_setenv("GDK_BACKEND", "wayland", TRUE);
  }
}

int main(int argc, char** argv) {
  enforce_gdk_backend();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
