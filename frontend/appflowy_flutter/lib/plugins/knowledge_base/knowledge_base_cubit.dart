import 'package:appflowy/plugins/knowledge_base/knowledge_base_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KnowledgeBaseCubit extends Cubit<AsyncSnapshot<List<KnowledgeBase>>> {
  KnowledgeBaseCubit(this.service) : super(const AsyncSnapshot.nothing());

  final KnowledgeBaseService service;
  final dataSourceBaseId = ValueNotifier<String?>(null);
  int _request = 0;

  Future<void> load({String? action, Map<String, dynamic>? payload}) async {
    final request = ++_request;
    emit(const AsyncSnapshot.waiting());
    try {
      if (action != null) await service.post(action, payload!);
      final bases = await service.bases();
      if (!isClosed && request == _request) {
        emit(AsyncSnapshot.withData(ConnectionState.done, bases));
      }
    } catch (error, stack) {
      if (!isClosed && request == _request) {
        emit(AsyncSnapshot.withError(ConnectionState.done, error, stack));
      }
    }
  }

  @override
  Future<void> close() {
    dataSourceBaseId.dispose();
    service.close();
    return super.close();
  }
}
