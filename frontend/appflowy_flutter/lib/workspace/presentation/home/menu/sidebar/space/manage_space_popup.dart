import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/buttons/primary_button.dart';
import 'package:flowy_infra_ui/widget/buttons/secondary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_request_service.dart';

class ManageSpacePopup extends StatefulWidget {
  const ManageSpacePopup({
    super.key,
    this.space,
  });

  final ViewPB? space;

  @override
  State<ManageSpacePopup> createState() => _ManageSpacePopupState();
}

class _ManageSpacePopupState extends State<ManageSpacePopup> {
  String? spaceName;
  String? spaceIcon;
  String? spaceIconColor;
  SpacePermission? spacePermission;
  bool _isOwner = false;
  final Set<String> _loadingRequests = {};
  late SpaceRequestService _spaceRequestService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetSpace = widget.space ?? context.read<SpaceBloc>().state.currentSpace;
      final userRole = context.read<UserWorkspaceBloc>().state.currentWorkspace?.role;
      // owner check: if current workspace role is Owner treat as owner for now
      setState(() {
        _isOwner = userRole == AFRolePB.Owner;
      });
      if (_isOwner && targetSpace != null) {
        _spaceRequestService = SpaceRequestService(workspaceId: context.read<UserWorkspaceBloc>().state.currentWorkspace!.workspaceId, userId: context.read<UserWorkspaceBloc>().state.userProfile.id);
        // ask SpaceBloc to load join requests (bloc will call the service)
        context.read<SpaceBloc>().add(SpaceEvent.loadJoinRequests(spaceId: targetSpace.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 使用传入的 space，如果没有则使用 currentSpace
    final targetSpace = widget.space ?? context.read<SpaceBloc>().state.currentSpace;
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowyText(
            LocaleKeys.space_manage.tr(),
            fontSize: 18.0,
          ),
          const VSpace(16.0),
          _SpaceNameTextField(
            space: targetSpace,
            onNameChanged: (name) => spaceName = name,
            onIconChanged: (icon, color) {
              spaceIcon = icon;
              spaceIconColor = color;
            },
          ),
          const VSpace(16.0),
          SpacePermissionSwitch(
            spacePermission: targetSpace?.spacePermission,
            onPermissionChanged: (value) => spacePermission = value,
          ),
          const VSpace(16.0),
          SpaceCancelOrConfirmButton(
            confirmButtonName: LocaleKeys.button_save.tr(),
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () {
              context.read<SpaceBloc>().add(
                    SpaceEvent.update(
                      space: targetSpace,
                      name: spaceName,
                      icon: spaceIcon,
                      iconColor: spaceIconColor,
                      permission: spacePermission,
                    ),
                  );

              Navigator.of(context).pop();
            },
          ),
          if (_isOwner) ...[
            const VSpace(16.0),
            FlowyText.regular('加入请求', fontSize: 14.0),
            const VSpace(8.0),
            SizedBox(
              height: 200,
              child: BlocBuilder<SpaceBloc, SpaceState>(
                builder: (context, state) {
                  final sid = targetSpace?.id;
                  if (sid == null) return const SizedBox.shrink();
                  final requests = state.joinRequests[sid] ?? [];
                  if (requests.isEmpty) {
                    return Center(
                      child: FlowyText.regular('暂无加入请求', color: Theme.of(context).hintColor),
                    );
                  }
                  return ListView.separated(
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const VSpace(8.0),
                    itemBuilder: (ctx, idx) {
                      final r = requests[idx];
                      final requesterName = r['requester_name'] ?? r['requester_id'].toString();
                      final reason = r['reason'] ?? '';
                      final reqId = r['request_id'] ?? r['id'] ?? '';
                      final isLoading = _loadingRequests.contains(reqId);
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FlowyText.regular(requesterName, fontSize: 14.0),
                                const VSpace(4.0),
                                FlowyText.regular(reason, fontSize: 12.0, color: Theme.of(context).hintColor),
                              ],
                            ),
                          ),
                          const HSpace(8.0),
                          SecondaryTextButton(
                            '拒绝',
                            onPressed: isLoading
                                ? null
                                : () async {
                                    setState(() => _loadingRequests.add(reqId));
                                    final svc = SpaceRequestService(
                                      workspaceId: context.read<UserWorkspaceBloc>().state.currentWorkspace!.workspaceId,
                                      userId: context.read<UserWorkspaceBloc>().state.userProfile.id,
                                    );
                                    final ok = await svc.handleJoinRequest(spaceId: targetSpace!.id, requestId: reqId, approve: false);
                                    if (ok) {
                                      context.read<SpaceBloc>().add(SpaceEvent.handleJoinRequest(requestId: reqId, approve: false));
                                    } else {
                                      showToastNotification(message: '操作失败');
                                    }
                                    setState(() => _loadingRequests.remove(reqId));
                                  },
                          ),
                          const HSpace(8.0),
                          isLoading
                              ? const SizedBox(width: 76, height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                              : PrimaryTextButton(
                                  '通过',
                                  onPressed: () async {
                                    setState(() => _loadingRequests.add(reqId));
                                    final svc = SpaceRequestService(
                                      workspaceId: context.read<UserWorkspaceBloc>().state.currentWorkspace!.workspaceId,
                                      userId: context.read<UserWorkspaceBloc>().state.userProfile.id,
                                    );
                                    final ok = await svc.handleJoinRequest(spaceId: targetSpace!.id, requestId: reqId, approve: true);
                                    if (ok) {
                                      context.read<SpaceBloc>().add(SpaceEvent.handleJoinRequest(requestId: reqId, approve: true));
                                    } else {
                                      showToastNotification(message: '操作失败');
                                    }
                                    setState(() => _loadingRequests.remove(reqId));
                                  },
                                ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpaceNameTextField extends StatelessWidget {
  const _SpaceNameTextField({
    required this.space,
    required this.onNameChanged,
    required this.onIconChanged,
  });

  final ViewPB? space;
  final void Function(String name) onNameChanged;
  final void Function(String? icon, String? color) onIconChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowyText.regular(
          LocaleKeys.space_spaceName.tr(),
          fontSize: 14.0,
          color: Theme.of(context).hintColor,
        ),
        const VSpace(8.0),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: SpaceIconPopup(
                  space: space,
                  cornerRadius: 12,
                  icon: space?.spaceIcon,
                  iconColor: space?.spaceIconColor,
                  onIconChanged: onIconChanged,
                ),
              ),
              const HSpace(12),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FlowyTextField(
                    text: space?.name,
                    onChanged: onNameChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
