# 远端修改后备份说明

时间戳：20260516-070454

项目内容：PonyNotes 设置页与侧栏唤醒布局优化

备份原因：设置弹窗黄金比例响应式布局、文字防压缩、侧栏全局唤醒按钮已经完成并通过 Windows Release 构建。按 AGENTS 规则推送到 beifenstore 作为改后可回滚点。

修改文件：

- frontend/appflowy_flutter/lib/workspace/application/home/home_setting_bloc.dart
- frontend/appflowy_flutter/lib/workspace/presentation/home/desktop_home_screen.dart
- frontend/appflowy_flutter/lib/workspace/presentation/home/home_layout.dart
- frontend/appflowy_flutter/lib/workspace/presentation/home/menu/sidebar/slider_menu_hover_trigger.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/pages/settings_account_view.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/settings_dialog.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/shared/settings_body.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/shared/settings_header.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/widgets/settings_menu.dart
- frontend/appflowy_flutter/lib/workspace/presentation/settings/widgets/settings_menu_element.dart

验证结果：

- flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings：通过，仓库仍有既有 lint/info。
- 首次长路径构建失败：MSBuild 260 字符路径限制。
- 短路径 Y:\appflowy_flutter 构建首次失败：运行中的 PonyNotes.exe 占用产物。
- 关闭旧 PonyNotes 进程后短路径构建成功。

产物：

- EXE：G:\pony\PonyNotes-New-work-20260512-whiteboard-second\frontend\appflowy_flutter\build\windows\x64\runner\Release\PonyNotes.exe
- ZIP：G:\pony\PonyNotes-New-work-20260512-whiteboard-second\dist\PonyNotes-Windows-Release-settings-sidebar-20260516-070454.zip
- EXE SHA256：4EFEC12FDE00FC807D42C51A889241135FD26C5286A97761DC4AA8A57F29A95E
- ZIP SHA256：C1E5746B1E1C3A76367BD6FD96D2770F531EE1220515F4D9CC1EB390B7D37AF2
