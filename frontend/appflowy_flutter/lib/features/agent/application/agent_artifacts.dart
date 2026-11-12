import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AgentArtifact {
  const AgentArtifact({
    required this.document,
    required this.message,
    required this.index,
    required this.name,
    required this.size,
    required this.file,
    required this.createdAt,
    this.documentName = '',
    this.cloudUrl,
    this.independent = false,
  });
  final String document;
  final String message;
  final int index;
  final String name;
  final int size;
  final File file;
  final DateTime createdAt;
  final String documentName;
  final String? cloudUrl;
  final bool independent;
  String get key => '$document/$message/$index';
}

/// Account-scoped durable copies; generated names never become filesystem paths.
class AgentArtifacts {
  AgentArtifacts({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;

  Future<Directory> folder(String identity, String document) async {
    final root = await _directory();
    final folder = Directory(
      p.join(
        root.path,
        'agent_artifacts',
        const Uuid().v5(Namespace.url.value, identity),
        const Uuid().v5(Namespace.url.value, document),
      ),
    );
    await folder.create(recursive: true);
    return folder;
  }

  Future<File> save({
    required String identity,
    required String document,
    required String message,
    required Map<String, dynamic> artifact,
    required Future<void> Function(File destination) download,
    String documentName = '',
    bool independent = false,
  }) async {
    if (artifact['index'] is! int ||
        (artifact['index'] as int) < 0 ||
        artifact['file_size'] is! int ||
        (artifact['file_size'] as int) < 0 ||
        artifact['file_name'] is! String) {
      throw const FormatException('文件产物记录无效');
    }
    final root = await folder(identity, document);
    final id =
        const Uuid().v5(Namespace.url.value, '$message/${artifact['index']}');
    final extension = p.extension('${artifact['file_name']}').toLowerCase();
    final safeExtension =
        RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension) ? extension : '';
    final file = File(p.join(root.path, '$id$safeExtension'));
    if (!await file.exists() || await file.length() != artifact['file_size']) {
      final pending = File('${file.path}.part');
      try {
        await download(pending);
        if (await pending.length() != artifact['file_size']) {
          throw StateError('文件下载不完整，请重试');
        }
        await pending.rename(file.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    }
    final metadata = File(p.join(root.path, '$id.artifact.json'));
    final pendingMetadata = File('${metadata.path}.part');
    await pendingMetadata.writeAsString(
      jsonEncode({
        'document': document,
        'message': message,
        'index': artifact['index'],
        'name': artifact['file_name'],
        'size': artifact['file_size'],
        'file': p.basename(file.path),
        'created_at': (await file.lastModified()).toUtc().toIso8601String(),
        'document_name': documentName,
        'cloud_url': artifact['cloud_url'],
        'independent': independent,
      }),
      flush: true,
    );
    await pendingMetadata.rename(metadata.path);
    return file;
  }

  /// Enumerate only this server/account/workspace, never other account folders.
  Future<List<AgentArtifact>> list(String identity) async {
    final root = await _directory();
    final scope = Directory(
      p.join(
        root.path,
        'agent_artifacts',
        const Uuid().v5(Namespace.url.value, identity),
      ),
    );
    if (!await scope.exists()) return [];
    final result = <AgentArtifact>[];
    await for (final document in scope.list(followLinks: false)) {
      if (document is! Directory) continue;
      await for (final metadata in document.list(followLinks: false)) {
        if (metadata is! File || !metadata.path.endsWith('.artifact.json')) {
          continue;
        }
        try {
          final data =
              jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
          final filename = data['file'] as String;
          if (p.basename(filename) != filename ||
              filename.contains('\\') ||
              filename.contains('/')) {
            continue;
          }
          final file = File(p.join(document.path, filename));
          if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          if (await file.length() != data['size']) continue;
          result.add(
            AgentArtifact(
              document: data['document'] as String,
              message: data['message'] as String,
              index: data['index'] as int,
              name: data['name'] as String,
              size: data['size'] as int,
              file: file,
              createdAt: DateTime.parse(data['created_at'] as String),
              documentName: data['document_name'] as String? ?? '',
              cloudUrl: data['cloud_url'] as String?,
              independent: data['independent'] == true,
            ),
          );
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }
}
