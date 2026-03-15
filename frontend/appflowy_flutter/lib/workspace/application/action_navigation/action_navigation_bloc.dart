import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:bloc/bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'action_navigation_bloc.freezed.dart';

class ActionNavigationBloc
    extends Bloc<ActionNavigationEvent, ActionNavigationState> {
  ActionNavigationBloc() : super(const ActionNavigationState.initial()) {
    on<ActionNavigationEvent>((event, emit) async {
      await event.when(
        performAction: (action, showErrorToast, nextActions) async {
          NavigationAction currentAction = action;
          if (currentAction.arguments?[ActionArgumentKeys.view] == null &&
              action.type == ActionType.openView) {
            // 若 objectId 是分享链接（含 viewId=），则解析出真正的 viewId
            final viewId = _resolveViewId(action.objectId);
            final result = await ViewBackendService.getView(viewId);
            final view = result.toNullable();
            if (view != null) {
              if (currentAction.arguments == null) {
                currentAction = currentAction.copyWith(arguments: {});
              }
              currentAction.arguments?.addAll({ActionArgumentKeys.view: view});

            } else {
              Log.error('Open view failed: $viewId (original objectId: ${action.objectId})');
              if (showErrorToast) {
                showToastNotification(
                  message: LocaleKeys.search_pageNotExist.tr(),
                  type: ToastificationType.error,
                );
              }
            }
          }

          emit(state.copyWith(action: currentAction, nextActions: nextActions));

          if (nextActions.isNotEmpty) {
            final newActions = [...nextActions];
            final next = newActions.removeAt(0);

            add(
              ActionNavigationEvent.performAction(
                action: next,
                nextActions: newActions,
              ),
            );
          } else {
            emit(state.setNoAction());
          }
        },
      );
    });
  }

  /// 若 [objectId] 为分享链接（含 viewId=），解析出真正的 viewId；否则返回原值
  static String _resolveViewId(String objectId) {
    debugPrint('[ActionNavigationBloc] _resolveViewId called with objectId: $objectId');
    
    // 首先尝试直接用正则表达式提取 viewId，避免 URI 解析的问题
    if (objectId.contains('viewId=')) {
      debugPrint('[ActionNavigationBloc] objectId contains viewId=, trying regex extraction');
      
      // 直接用正则表达式提取 viewId
      final match = RegExp(r'[?&]viewId=([^&]+)').firstMatch(objectId);
      if (match != null) {
        final extractedViewId = match.group(1);
        debugPrint('[ActionNavigationBloc] Directly extracted viewId: $extractedViewId');
        if (extractedViewId != null && extractedViewId.isNotEmpty) {
          return extractedViewId;
        }
      }
      
      // 如果直接提取失败，尝试 URI 解析
      try {
        final String urlToParse;
        if (objectId.startsWith('http')) {
          urlToParse = objectId;
        } else {
          // 处理不以 http 开头的 objectId，如 "share?viewId=xxx&type=share"
          // 添加协议和域名以便正确解析查询参数
          urlToParse = 'https://www.xiaomabiji.com/$objectId';
        }
        
        debugPrint('[ActionNavigationBloc] Parsing URL: $urlToParse');
        final uri = Uri.parse(urlToParse);
        debugPrint('[ActionNavigationBloc] URI parsed - host: ${uri.host}, path: ${uri.path}, query: ${uri.query}');
        var viewId = uri.queryParameters['viewId'];
        
        debugPrint('[ActionNavigationBloc] Initial parsed viewId: $viewId');
        
        // 兼容处理：若 viewId 包含 & 或其他无效字符，说明 query string 解析有问题
        if (viewId != null && (viewId.contains('&') || viewId.contains('?') || viewId.contains('/'))) {
          debugPrint('[ActionNavigationBloc] viewId contains invalid chars, trying regex extraction');
          final regexMatch = RegExp(r'[?&]viewId=([^&]+)').firstMatch(objectId);
          if (regexMatch != null) {
            viewId = regexMatch.group(1);
            debugPrint('[ActionNavigationBloc] After regex fix - extracted viewId: $viewId');
          }
        }
        
        if (viewId != null && viewId.isNotEmpty) {
          debugPrint('[ActionNavigationBloc] Resolved viewId: $viewId from objectId: $objectId');
          return viewId;
        }
      } catch (e) {
        debugPrint('[ActionNavigationBloc] Failed to parse viewId from: $objectId, error: $e');
      }
    }
    return objectId;
  }
}

@freezed
class ActionNavigationEvent with _$ActionNavigationEvent {
  const factory ActionNavigationEvent.performAction({
    required NavigationAction action,
    @Default(false) bool showErrorToast,
    @Default([]) List<NavigationAction> nextActions,
  }) = _PerformAction;
}

class ActionNavigationState {
  const ActionNavigationState.initial()
      : action = null,
        nextActions = const [];

  const ActionNavigationState({
    required this.action,
    this.nextActions = const [],
  });

  final NavigationAction? action;
  final List<NavigationAction> nextActions;

  ActionNavigationState copyWith({
    NavigationAction? action,
    List<NavigationAction>? nextActions,
  }) =>
      ActionNavigationState(
        action: action ?? this.action,
        nextActions: nextActions ?? this.nextActions,
      );

  ActionNavigationState setNoAction() =>
      const ActionNavigationState(action: null);
}
