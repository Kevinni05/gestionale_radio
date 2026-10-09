import 'package:flutter_test/flutter_test.dart';
import 'package:gestionale_radio/services/app_branding.dart';

void main() {
  test('default product branding remains usable without buyer overrides', () {
    expect(AppBranding.name, isNotEmpty);
    expect(AppBranding.displayName, isNotEmpty);
    expect(AppBranding.company, isNotEmpty);
    expect(AppBranding.assetPrefix, isNotEmpty);
    expect(AppBranding.upperName, AppBranding.name.toUpperCase());
  });
}
