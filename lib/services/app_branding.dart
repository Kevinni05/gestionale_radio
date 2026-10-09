class AppBranding {
  const AppBranding._();

  static const String name = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'RadioTech',
  );
  static const String displayName = String.fromEnvironment(
    'APP_DISPLAY_NAME',
    defaultValue: 'RadioTech',
  );
  static const String subtitle = String.fromEnvironment(
    'APP_SUBTITLE',
    defaultValue: 'Gestione operativa',
  );
  static const String company = String.fromEnvironment(
    'APP_COMPANY',
    defaultValue: 'RadioTech',
  );
  static const String supportEmail = String.fromEnvironment(
    'APP_SUPPORT_EMAIL',
    defaultValue: '',
  );
  static const String pdfBrand = String.fromEnvironment(
    'APP_PDF_BRAND',
    defaultValue: 'RadioTech Operations Suite',
  );
  static const String assetPrefix = String.fromEnvironment(
    'APP_ASSET_PREFIX',
    defaultValue: 'RadioTech',
  );

  static String get upperName => name.toUpperCase();
}
