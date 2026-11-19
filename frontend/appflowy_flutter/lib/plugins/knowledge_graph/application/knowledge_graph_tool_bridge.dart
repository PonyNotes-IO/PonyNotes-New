class KnowledgeGraphToolBridge {
  static final _views =
      <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>{};
  static void register(
          String key,
          Future<Map<String, dynamic>> Function(Map<String, dynamic>)
              callback,) =>
      _views[key] = callback;
  static void unregister(String key) => _views.remove(key);
  static Future<Map<String, dynamic>> update(
      String key, Map<String, dynamic> settings,) async {
    final update = _views[key];
    if (update == null) throw StateError('请先打开对应的知识图谱');
    return update(settings);
  }
}
