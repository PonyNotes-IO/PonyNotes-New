import 'package:appflowy/features/shared_section/data/repositories/rust_shared_pages_repository_impl.dart';
import 'package:appflowy/features/shared_section/logic/shared_section_bloc.dart';
import 'package:appflowy/features/shared_section/presentation/widgets/shared_page_list.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarShareButton extends StatefulWidget {
  const SidebarShareButton({super.key});

  @override
  State<SidebarShareButton> createState() => _SidebarShareButtonState();
}

class _SidebarShareButtonState extends State<SidebarShareButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return BlocProvider(
      create: (_) => SharedSectionBloc(
        workspaceId: '', // bloc 内部不强依赖此值用于拉取列表
        repository: RustSharePagesRepositoryImpl(),
        enablePolling: true,
      )..add(const SharedSectionInitEvent()),
      child: BlocBuilder<SharedSectionBloc, SharedSectionState>(
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(theme.borderRadius.s),
                  onTap: () {
                    setState(() => _isExpanded = !_isExpanded);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      children: [
                        FlowySvg(
                          FlowySvgs.shared_section_icon_m,
                          size: const Size.square(16.0),
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FlowyText.medium(
                            '共享',
                            fontSize: 14.0,
                            figmaLineHeight: 17.0,
                            color: AppFlowyTheme.of(context).textColorScheme.primary,
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                          size: 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isExpanded)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 4.0),
                  child: _buildSharedList(context, state),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSharedList(BuildContext context, SharedSectionState state) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (state.sharedPages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 8.0, top: 6.0, bottom: 6.0),
        child: FlowyText.small(
          '暂无共享',
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return SharedPageList(
      sharedPages: state.sharedPages,
      onSetEditing: (context, value) {
        context.read<ViewBloc>().add(ViewEvent.setIsEditing(value));
      },
      onAction: (_, __, ___) {},
      onSelected: (ctx, view) => ctx.read<TabsBloc>().openPlugin(view),
      onTertiarySelected: (ctx, view) => ctx.read<TabsBloc>().openTab(view),
    );
  }
}
