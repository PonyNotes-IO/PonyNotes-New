import 'package:appflowy/workspace/application/view/ai_chat_view_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/material.dart';
import 'package:flowy_infra/platform_extension.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/page_stack_visibility.dart';
import '../application/agent_artifacts.dart';
import '../application/agent_service.dart';
import '../application/agent_controller.dart';
import 'agent_artifact_panel.dart';
import 'ai_mode_button.dart';

class AllAgentArtifactsButton extends StatelessWidget {
  const AllAgentArtifactsButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () {
          if (PlatformInfo.isDesktopOrTablet) {
            getIt<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(pluginType: PluginType.agentArtifacts),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AgentArtifactLibrary(),
            ),
          );
        },
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: const Text('全部产物'),
      );
}

Future<List<AgentArtifact>> loadLocalAgentArtifacts() async {
  final workspace = await AIChatViewService.getCurrentWorkspaceId();
  if (workspace == null) throw StateError('请先打开工作区');
  final service = AgentService();
  final identity = await service.identity(workspace);
  final entries = await AgentArtifacts().list(identity);
  if (await service.identity(workspace) != identity ||
      await AIChatViewService.getCurrentWorkspaceId() != workspace) {
    throw StateError('账号或工作区已切换，请重新打开全部产物');
  }
  return entries;
}

class AgentArtifactLibrary extends StatefulWidget {
  const AgentArtifactLibrary({super.key, this.load, this.embedded = false});
  final Future<List<AgentArtifact>> Function()? load;
  final bool embedded;
  @override
  State<AgentArtifactLibrary> createState() => _AgentArtifactLibraryState();
}

class _AgentArtifactLibraryState extends State<AgentArtifactLibrary> {
  final clearance = AgentController.accountClearance.value;
  late Future<List<AgentArtifact>> entries =
      (widget.load ?? loadLocalAgentArtifacts)();
  bool? _wasActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageStackVisibility.of(context);
    if (_wasActive == false && active) {
      entries = (widget.load ?? loadLocalAgentArtifacts)();
    }
    _wasActive = active;
  }

  void _refresh() {
    setState(() {
      entries = (widget.load ?? loadLocalAgentArtifacts)();
    });
  }

  Future<void> _source(AgentArtifact artifact) async {
    if (artifact.independent) {
      if (!widget.embedded) Navigator.of(context).pop();
      openIndependentAiConversation(context, artifact.document);
      return;
    }
    final result = await ViewBackendService.getView(artifact.document);
    final view =
        result.fold((view) => view, (error) => throw StateError(error.msg));
    if (!mounted || clearance != AgentController.accountClearance.value) return;
    if (PlatformInfo.isMobile && !PlatformInfo.isTablet) {
      openCreatedAiDocument(context, view.id, view.name);
    } else {
      if (!widget.embedded) Navigator.of(context).pop();
      getIt<TabsBloc>().openTab(view);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: AgentController.accountClearance,
            builder: (context, value, _) {
              if (value != clearance) {
                return Column(
                  children: [
                    if (!widget.embedded) const BackButton(),
                    const Expanded(
                      child: Center(child: Text('账号已切换，请重新打开全部产物')),
                    ),
                  ],
                );
              }
              return FutureBuilder<List<AgentArtifact>>(
                future: entries,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return AgentArtifactPanel(
                      artifacts: snapshot.data!,
                      library: true,
                      onClose: widget.embedded
                          ? null
                          : () => Navigator.of(context).pop(),
                      onRefresh: _refresh,
                      onSource: _source,
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          if (!widget.embedded)
                            BackButton(
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          const Text(
                            '全部产物',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: snapshot.hasError
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('无法加载本地产物'),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _refresh,
                                      child: const Text('重试'),
                                    ),
                                  ],
                                )
                              : const CircularProgressIndicator(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );
}
