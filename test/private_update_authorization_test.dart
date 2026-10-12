import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/android_update_service.dart';

void main() {
  test(
    'private updater never loads credentials for another origin or an unrelated API',
    () async {
      var loads = 0;
      Future<String?> token() async {
        loads++;
        return 'synthetic-token';
      }

      final api = Uri.parse('https://radiotechwebapp.onrender.com');
      for (final uri in [
        'https://untrusted.example/api/v1/distribution/app.apk',
        'https://radiotechwebapp.onrender.com/other/app.apk',
        'http://radiotechwebapp.onrender.com/api/v1/distribution/app.apk',
      ]) {
        expect(
          await AndroidUpdateService.authorizationFor(
            Uri.parse(uri),
            api,
            token,
          ),
          isNull,
        );
      }
      expect(loads, 0);
      expect(
        await AndroidUpdateService.authorizationFor(
          Uri.parse(
            'https://radiotechwebapp.onrender.com/api/v1/distribution/app.apk',
          ),
          api,
          token,
        ),
        'synthetic-token',
      );
      expect(loads, 1);
      await expectLater(
        AndroidUpdateService.authorizationFor(
          Uri.parse(
            'https://radiotechwebapp.onrender.com/api/v1/distribution/latest.json',
          ),
          api,
          () async => null,
        ),
        throwsStateError,
      );
    },
  );
}
