/// Helpers for keeping Excalidraw image elements and their file records
/// together while whiteboard data is being synchronized.
class WhiteboardImageSyncGuard {
  const WhiteboardImageSyncGuard._();

  /// Returns file ids referenced by live image elements.
  static Set<String> collectReferencedImageFileIds(dynamic elements) {
    final ids = <String>{};
    if (elements is! List) return ids;

    for (final element in elements) {
      if (element is! Map || element['isDeleted'] == true) continue;
      if (element['type'] != 'image') continue;
      final fileId = element['fileId'];
      if (fileId is String && fileId.isNotEmpty) {
        ids.add(fileId);
      }
    }
    return ids;
  }

  /// Returns referenced image file ids that are not present in the files map.
  static Set<String> unresolvedFileIds({
    dynamic elements,
    dynamic files,
  }) {
    final referenced = collectReferencedImageFileIds(elements);
    if (referenced.isEmpty) return <String>{};
    if (files is! Map) return referenced;
    return referenced.where((id) => !files.containsKey(id)).toSet();
  }

  static bool hasUnresolvedImageFiles({
    dynamic elements,
    dynamic files,
  }) {
    return unresolvedFileIds(elements: elements, files: files).isNotEmpty;
  }
}
