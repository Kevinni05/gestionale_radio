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
}
