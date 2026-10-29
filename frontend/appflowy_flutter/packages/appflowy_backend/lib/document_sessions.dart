/// Counts editor owners in the main engine, including editors in other windows.
class DocumentSessions {
  static final _owners = <String, Map<String, int>>{};
  static Future<void> Function(String)? remoteRetain;
  static Future<bool> Function(String)? remoteRelease;

  static Future<void> retain(String documentId, {String owner = 'main'}) async {
    final remote = remoteRetain;
    if (remote != null) return remote(documentId);
    final owners = _owners.putIfAbsent(documentId, () => {});
    owners[owner] = (owners[owner] ?? 0) + 1;
  }

  static Future<bool> release(String documentId,
      {String owner = 'main'}) async {
    final remote = remoteRelease;
    if (remote != null) return remote(documentId);
    final owners = _owners[documentId];
    if (owners == null) return true;
    final count = (owners[owner] ?? 0) - 1;
    if (count > 0) {
      owners[owner] = count;
    } else {
      owners.remove(owner);
    }
    if (owners.isNotEmpty) return false;
    _owners.remove(documentId);
    return true;
  }

  static List<String> releaseOwner(String owner) {
    final closed = <String>[];
    for (final id in _owners.keys.toList()) {
      final owners = _owners[id]!;
      if (owners.remove(owner) != null && owners.isEmpty) {
        _owners.remove(id);
        closed.add(id);
      }
    }
    return closed;
  }
}
