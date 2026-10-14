import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

typedef SupportDirectoryProvider = Future<Directory> Function();

class LocalReportAttachmentStore {
  static const int maxAttachmentBytes = 10000000;
  static const int maxAttachmentCount = 50;
  static const int maxStagedBytes = 100 * 1024 * 1024;
  static const _channel = MethodChannel('radiotech/operational-store');

  LocalReportAttachmentStore({
    SupportDirectoryProvider? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  final SupportDirectoryProvider _supportDirectoryProvider;

  Future<List<Map<String, String>>> stage({
    required String requestKey,
    Iterable<File> files = const <File>[],
    Map<String, Uint8List> bytes = const <String, Uint8List>{},
  }) async {
    final fileList = files.toList(growable: false);
    final itemCount = fileList.length + bytes.length;
    if (itemCount > maxAttachmentCount) {
      throw StateError(
        'Troppi allegati: massimo $maxAttachmentCount elementi per report.',
      );
    }

    var totalBytes = 0;
    for (final source in fileList) {
      if (!await source.exists()) {
        throw StateError('File allegato non disponibile.');
      }
      final length = await source.length();
      if (length > maxAttachmentBytes) {
        throw StateError('Allegato troppo grande: limite 10 MB.');
      }
      totalBytes += length;
    }
    for (final data in bytes.values) {
      if (data.length > maxAttachmentBytes) {
        throw StateError('Allegato troppo grande: limite 10 MB.');
      }
      totalBytes += data.length;
    }
    if (totalBytes > maxStagedBytes) {
      throw StateError(
        'Dimensione complessiva allegati eccessiva: limite 100 MB.',
      );
    }

    final supportDirectory = await _supportDirectoryProvider();
    final storageRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}radiotech_pending_reports',
    );
    final requestDirectory = Directory(
      '${storageRoot.path}${Platform.pathSeparator}${_safeSegment(requestKey)}',
    );
    if (await FileSystemEntity.isLink(storageRoot.path) ||
        await FileSystemEntity.isLink(requestDirectory.path)) {
      throw StateError('Directory allegati locale non valida.');
    }
    if (await requestDirectory.exists()) {
      if (!await requestDirectory.list().isEmpty) {
        throw StateError('Esiste già un report in attesa con questa chiave.');
      }
    }
    await requestDirectory.create(recursive: true);

    final staged = <Map<String, String>>[];
    var index = 0;
    try {
      for (final source in fileList) {
        final sourceName = source.uri.pathSegments.isEmpty
            ? 'attachment.bin'
            : source.uri.pathSegments.last;
        staged.add(
          await _copyFile(source, requestDirectory, index++, sourceName),
        );
      }
      for (final entry in bytes.entries) {
        staged.add(
          await _writeBytes(entry.value, requestDirectory, index++, entry.key),
        );
      }
      return staged;
    } catch (_) {
      if (await requestDirectory.exists()) {
        await requestDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<File> resolve(Map<String, dynamic> attachment) async {
    final file = File(attachment['path']?.toString() ?? '');
    final root = await _storageRoot();
    final rootPath = await root.exists()
        ? await root.resolveSymbolicLinks()
        : root.absolute.path;
    final filePath = await file.exists()
        ? await file.resolveSymbolicLinks()
        : file.absolute.path;
    if (!_isStoredPath(filePath, rootPath)) {
      throw StateError('Percorso allegato locale non valido.');
    }
    if (!await file.exists()) {
      throw StateError(
        'Allegato locale non disponibile: ${attachment['name']}.',
      );
    }
    if (await file.length() >
        maxAttachmentBytes + (Platform.isAndroid ? 36 : 0)) {
      throw StateError('Allegato locale oltre il limite di 10 MB.');
    }
    return File(filePath);
  }

  Future<Uint8List> readBytes(Map<String, dynamic> attachment) async {
    final file = await resolve(attachment);
    if (!Platform.isAndroid) return file.readAsBytes();
    final bytes = await _channel.invokeMethod<Uint8List>('readAttachment', {
      'path': file.path,
    });
    if (bytes == null || bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw StateError('Allegato locale non leggibile.');
    }
    return bytes;
  }

  Future<void> _protect(File file) async {
    if (Platform.isAndroid &&
        await _channel.invokeMethod<bool>('protectAttachment', {
              'path': file.path,
            }) !=
            true) {
      throw StateError('Protezione allegato non riuscita. Invio sospeso.');
    }
  }

  Future<void> remove(List<Map<String, dynamic>> attachments) async {
    for (final attachment in attachments) {
      try {
        final file = await resolve(attachment);
        await file.delete();
      } on StateError {
        continue;
      }
    }
    if (attachments.isEmpty) return;

    final firstPath = attachments.first['path']?.toString();
    if (firstPath == null || firstPath.isEmpty) return;
    final storageRoot = await _storageRoot();
    final rootPath = await storageRoot.exists()
        ? await storageRoot.resolveSymbolicLinks()
        : storageRoot.absolute.path;
    final requestDirectory = File(firstPath).absolute.parent;
    if (await FileSystemEntity.isLink(requestDirectory.path)) return;
    final directoryPath = await requestDirectory.exists()
        ? await requestDirectory.resolveSymbolicLinks()
        : requestDirectory.path;
    if (_isStoredPath(directoryPath, rootPath) &&
        Directory(directoryPath).parent.path == rootPath &&
        await requestDirectory.exists() &&
        await requestDirectory.list().isEmpty) {
      await requestDirectory.delete();
    }
  }

  Future<Map<String, String>> _copyFile(
    File source,
    Directory destination,
    int index,
    String name,
  ) async {
    if (!await source.exists()) {
      throw StateError('File allegato non disponibile: $name.');
    }
    final target = File(_targetPath(destination, index, name));
    final root = await _storageRoot();
    final storedSource =
        Platform.isAndroid &&
        _isStoredPath(
          await source.resolveSymbolicLinks(),
          await root.resolveSymbolicLinks(),
        );
    if (storedSource) {
      if (await _channel.invokeMethod<bool>('restageAttachment', {
            'source': source.path,
            'target': target.path,
          }) !=
          true) {
        throw StateError('Protezione allegato non riuscita. Invio sospeso.');
      }
    } else {
      await source.copy(target.path);
      await _protect(target);
    }
    return {'name': _safeSegment(name), 'path': target.path};
  }

  Future<Map<String, String>> _writeBytes(
    Uint8List bytes,
    Directory destination,
    int index,
    String name,
  ) async {
    final target = File(_targetPath(destination, index, name));
    await target.writeAsBytes(bytes, flush: true);
    await _protect(target);
    return {'name': _safeSegment(name), 'path': target.path};
  }

  String _targetPath(Directory destination, int index, String name) =>
      '${destination.path}${Platform.pathSeparator}${index}_${_safeSegment(name)}';

  Future<Directory> _storageRoot() async {
    final supportDirectory = await _supportDirectoryProvider();
    return Directory(
      '${supportDirectory.path}${Platform.pathSeparator}radiotech_pending_reports',
    );
  }

  bool _isStoredPath(String path, String rootPath) =>
      path.startsWith('$rootPath${Platform.pathSeparator}');

  String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty || safe == '.' || safe == '..' ? 'attachment' : safe;
  }
}
