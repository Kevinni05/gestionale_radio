import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/local_report_attachment_store.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'radiotech-report-store-',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'staged report attachments survive store recreation and can be removed',
    () async {
      final source = File(
        '${supportDirectory.path}${Platform.pathSeparator}photo.jpg',
      );
      await source.writeAsBytes([1, 2, 3]);
      final store = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => supportDirectory,
      );

      final staged = await store.stage(
        requestKey: 'report-task-a',
        files: [source],
        bytes: {
          'report.pdf': Uint8List.fromList([4, 5, 6]),
        },
      );
      final restartedStore = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => supportDirectory,
      );

      expect(staged, hasLength(2));
      expect(await (await restartedStore.resolve(staged.first)).readAsBytes(), [
        1,
        2,
        3,
      ]);
      expect(await (await restartedStore.resolve(staged.last)).readAsBytes(), [
        4,
        5,
        6,
      ]);

      await expectLater(
        restartedStore.stage(
          requestKey: 'report-task-a',
          bytes: {
            'replacement.pdf': Uint8List.fromList([7, 8, 9]),
          },
        ),
        throwsStateError,
      );
      expect(await (await restartedStore.resolve(staged.last)).readAsBytes(), [
        4,
        5,
        6,
      ]);

      await restartedStore.remove(staged);
      expect(await File(staged.first['path']!).exists(), isFalse);
      expect(await File(staged.last['path']!).exists(), isFalse);
    },
  );

  test('rejects oversized staged attachments before copying them', () async {
    final source = File(
      '${supportDirectory.path}${Platform.pathSeparator}too-large.bin',
    );
    await source.writeAsBytes(
      List<int>.filled(LocalReportAttachmentStore.maxAttachmentBytes + 1, 0),
      flush: true,
    );
    final store = LocalReportAttachmentStore(
      supportDirectoryProvider: () async => supportDirectory,
    );

    await expectLater(
      store.stage(requestKey: 'oversized', files: [source]),
      throwsStateError,
    );

    final stagedRoot = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}radiotech_pending_reports',
    );
    expect(await stagedRoot.exists(), isFalse);
  });

  test(
    'rejects too many staged attachments without touching storage',
    () async {
      final store = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => supportDirectory,
      );
      final bytes = <String, Uint8List>{
        for (
          var i = 0;
          i < LocalReportAttachmentStore.maxAttachmentCount + 1;
          i++
        )
          'item-$i.bin': Uint8List.fromList([i % 255]),
      };

      await expectLater(
        store.stage(requestKey: 'too-many', bytes: bytes),
        throwsStateError,
      );
    },
  );

  test('rejects attachment paths outside the app support store', () async {
    final store = LocalReportAttachmentStore(
      supportDirectoryProvider: () async => supportDirectory,
    );

    expect(
      () =>
          store.resolve({'name': 'outside.jpg', 'path': supportDirectory.path}),
      throwsStateError,
    );
    await store.remove([
      {'name': 'outside.jpg', 'path': supportDirectory.path},
    ]);
    expect(await supportDirectory.exists(), isTrue);
  });

  test(
    'refuses linked staging directories and preserves unrelated files during cleanup',
    () async {
      final root = Directory(
        '${supportDirectory.path}/radiotech_pending_reports',
      );
      await root.create();
      final outside = Directory('${supportDirectory.path}/outside');
      await outside.create();
      final linked = Link('${root.path}/linked');
      await linked.create(outside.path);
      final store = LocalReportAttachmentStore(
        supportDirectoryProvider: () async => supportDirectory,
      );
      await expectLater(
        store.stage(
          requestKey: 'linked',
          bytes: {
            'photo.jpg': Uint8List.fromList([1]),
          },
        ),
        throwsStateError,
      );
      expect(await outside.list().isEmpty, isTrue);
      await linked.delete();
      final staged = await store.stage(
        requestKey: 'real',
        bytes: {
          'photo.jpg': Uint8List.fromList([1]),
        },
      );
      final unrelated = File(
        '${File(staged.first['path']!).parent.path}/unrelated.jpg',
      );
      await unrelated.writeAsBytes([2]);
      await store.remove(staged);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
