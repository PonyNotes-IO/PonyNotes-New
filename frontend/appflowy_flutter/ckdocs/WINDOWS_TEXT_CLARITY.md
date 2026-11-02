# Windows 中文文字显示

本次调整针对中文界面和文档正文，保持用户选择的字号、字重与字体。

## 调整

- Windows 的“默认字体”在渲染时解析为 `Microsoft YaHei UI`，依次回退到 `Microsoft YaHei`、`Segoe UI`、`Segoe UI Emoji`。持久化的默认值仍为空字符串，避免把 Windows 字体名同步成其他平台的默认设置。
- Windows 的 Material、AppFlowy UI 和文档编辑器使用一致的默认字体与中文回退。显式选择的宋体、微软雅黑、Google 字体及代码等宽字体保持原字体；Google 字体保留原有回退，再追加 Windows 回退。
- Windows 设置菜单移除强制 `SimHei`，遵循工作区字体；其他平台保留原有菜单字体策略。
- 字体选择器继续以空字符串标识“默认字体”，避免选择默认项后把 Windows 字体名写入用户设置。字体解析函数保留此约定，平台字体仅在渲染入口解析。
- Windows 不再根据窗口宽度额外乘以 1.02 / 1.04 的字体缩放。布局缩放、系统 DPI 和用户设置的 Display Size 继续生效。
- 文档外观读取保存的基础字号，不再预先乘以 Display Size。编辑器负责应用一次缩放。例如基础字号 16、Display Size 90% 时，重启后应仍为 14.4，而不是再次缩小到 12.96。

Windows runner 已配置 PerMonitorV2；本次没有改动 DPI manifest、Flutter SDK 或引擎，也没有添加描边、阴影或强制加粗。

## 验证

在 Flutter 项目目录运行：

```powershell
flutter test --no-pub test/unit_test/theme/windows_typography_test.dart test/bloc_test/app_setting_test/document_appearance_test.dart --reporter expanded
flutter test --no-pub test/unit_test/theme/theme_test.dart test/unit_test/settings/theme_missing_keys_test.dart test/unit_test/workspace/mobile_pdf_chinese_font_test.dart --reporter expanded
flutter build windows --release --no-pub
```

上述 30 项测试全部通过。字体与字号回归测试覆盖默认字体选择、Google 字体回退、菜单跳转与禁用、显式字体与字重、其他平台、窗口尺寸与 DPR 组合，以及 90% / 100% / 130% 下的文档字号重载和重启。扩展测试覆盖主题配置及中英文 PDF 导出。2026-10-23 使用 Flutter 3.35.1 验证，Windows Release 构建成功。相关代码静态检查没有错误或警告，现有主题文件的两处废弃 API 提示仍保留。

Review 时还检查了现有 `test/unit_test/editor/editor_style_test.dart`：其未知字体 `Garbage` 期望为 `null`，但现有解析函数会保留该字体名。使用 HEAD 中的原始编辑器、字体解析函数和测试在忽略的构建目录中复测，得到相同失败，确认该项为修改前已存在的问题。本次没有改变未知字体处理，也没有修改该测试来掩盖失败。

构建位于 `build/windows/x64/runner/Release/`。运行或分发时需要整个目录，不能仅复制 `PonyNotes.exe`。本次未替换已安装的客户端。

## 字体对比图

`tool/windows_text_preview.dart` 使用当前 Windows 的真实系统字体，输出 100%、125%、150% DPR 的 PNG。左右两栏使用相同的字号、常规字重、内容和颜色，仅比较字体选择及回退。

```powershell
flutter build bundle --debug --no-pub --target-platform windows-x64 --target tool/windows_text_preview.dart --asset-dir build/font_clarity/bundle
$flutterRoot = Split-Path (Split-Path (Get-Command flutter).Source -Parent) -Parent
$engineDir = Join-Path $flutterRoot 'bin/cache/artifacts/engine/windows-x64'
& "$engineDir/flutter_tester.exe" --disable-vm-service --enable-software-rendering --run-forever "--icu-data-file-path=$engineDir/icudtl.dat" --flutter-assets-dir=build/font_clarity/bundle build/font_clarity/bundle/kernel_blob.bin
```

输出：`build/font_clarity/text-100.png`、`text-125.png`、`text-150.png`。请以图片 100% 缩放查看。不要添加 `--use-test-fonts`，否则无法代表系统中文字体；`--run-forever` 用于让图片异步渲染完成，工具完成后会主动退出。

在本机对比中，已显式使用微软雅黑的正文差异很小。字体策略不能保证提升相同字体、字号下的栅格化锐度；重复缩放修复则能避免正文被额外缩小。上述离屏图没有模拟屏幕 ClearType、GPU 合成或跨显示器移动，最终仍需用 Release 客户端实屏检查设置菜单、中文正文、粗体、代码、Display Size 和跨 DPI 显示器行为。
