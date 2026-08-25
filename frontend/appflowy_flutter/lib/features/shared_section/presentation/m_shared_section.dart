import 'package:appflowy/features/shared_section/data/repositories/http_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_bloc.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/m_shared_page_list.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/m_shared_section_header.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/refresh_button.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/shared_section_error.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/shared_section_loading.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MSharedSection extends StatelessWidget {
  const MSharedSection({
    super.key,
    required this.workspaceId,
  });

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final repository = HttpSharedPagesRepositoryImpl();

    return BlocProvider(
      create: (_) => SharedSectionBloc(
        workspaceId: workspaceId,
        repository: repository,
        enablePolling: true,
      )..add(const SharedSectionInitEvent()),
      child: BlocBuilder<SharedSectionBloc, SharedSectionState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MSharedSectionHeader(
                isExpanded: state.isExpanded,
                onTap: () {
                  context.read<SharedSectionBloc>().add(
                        const SharedSectionToggleExpandedEvent(),
                      );
                },
              ),
              if (state.isLoading)
                const SharedSectionLoading()
              else if (state.errorMessage.isNotEmpty)
                const SharedSectionError(
                  errorMessage: '共享文档暂时无法加载，请检查网络后重试',
                )
              else if (state.sharedPages.isNotEmpty && state.isExpanded)
                Padding(
                  padding: const EdgeInsets.only(
                    left: HomeSpaceViewSizes.mHorizontalPadding,
                  ),
                  child: MSharedPageList(
                    sharedPages: state.sharedPages,
                    onSelected: (view) async {
                      await context.pushView(
                        view,
                        tabs: [
                          PickerTabType.emoji,
                          PickerTabType.icon,
                          PickerTabType.custom,
                        ].map((e) => e.name).toList(),
                      );
                    },
                  ),
                ),
              if (kDebugMode)
                RefreshSharedSectionButton(
                  onTap: () {
                    context.read<SharedSectionBloc>().add(
                          const SharedSectionEvent.refresh(),
                        );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
