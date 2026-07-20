import 'package:flutter/widgets.dart';

/// 标注当前子树所属的标签页（IndexedStack 子项）是否为激活标签。
///
/// 背景（2026-07-20 白板 D3D 资源累积根因修复）：
/// HomeStack 用 IndexedStack + wantKeepAlive 保活所有标签页，文档类页面保活成本
/// 很低；但白板页承载 WebView2（flutter_inappwebview），每个实例在宿主进程内
/// 持有一个独立的 D3D11 设备。崩溃转储（PonyNotes.exe.28208.dmp）实测：十几个
/// 后台白板累积出 108 条显卡驱动工作线程（全进程 244 线程），既拖慢整机又扩大
/// ExternalTextureD3d::PopulateTexture 的销毁竞态窗口（0xC0000409 闪退点）。
///
/// 重量级页面（白板）可依赖此标记在自己变为后台标签时主动释放原生资源，
/// 而无需改动 IndexedStack/keepAlive 的通用保活语义——文档类页面完全不受影响。
///
/// 不在此子树下（如移动端、独立路由）时 [of] 返回 true，视为始终可见。
class PageStackVisibility extends InheritedWidget {
  const PageStackVisibility({
    super.key,
    required this.isActive,
    required super.child,
  });

  /// 当前标签页是否为 IndexedStack 的激活项。
  final bool isActive;

  static bool of(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<PageStackVisibility>();
    return widget?.isActive ?? true;
  }

  @override
  bool updateShouldNotify(PageStackVisibility oldWidget) =>
      oldWidget.isActive != isActive;
}
