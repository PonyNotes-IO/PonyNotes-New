import 'package:flutter/material.dart';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/rounded_button.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';

/// 工作区加载失败时的兜底页面（桌面与移动端共用）。
///
/// 「上报问题」指向本项目自己的 issues 列表，不再是上游 AppFlowy 仓库；
/// 上游的「在 Discord 联系我们」按钮已移除 —— 那是 AppFlowy 官方社区，
/// 我们的用户点进去只会看到一个陌生的加入服务器页面。
class WorkspaceFailedScreen extends StatelessWidget {
  const WorkspaceFailedScreen({super.key});

  /// 本项目的 issues 列表。
  ///
  /// 原实现用的是上游的 new-issue 模板链接，并往 query 里塞了 version/os，
  /// 那套模板在本仓库不存在；这里直接指向 issues 列表，因此也不再需要
  /// 采集版本号与系统名（原 State 中的 version/os 字段随之删除）。
  static const _issuesUrl = 'https://github.com/PonyNotes-IO/PonyNotes-New/issues';

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(LocaleKeys.workspace_failedToLoad.tr()),
                const VSpace(20),
                // 只剩一个按钮，用固定宽度居中，避免它撑满 400 的容器宽度。
                SizedBox(
                  width: 200,
                  child: RoundedTextButton(
                    title: LocaleKeys.workspace_errorActions_reportIssue.tr(),
                    height: 40,
                    onPressed: () => afLaunchUrlString(_issuesUrl),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
