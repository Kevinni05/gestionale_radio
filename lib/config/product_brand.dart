class ProductBrand {
  const ProductBrand._();

  static const appName = String.fromEnvironment(
    'APP_DISPLAY_NAME',
    defaultValue: 'RadioTech',
  );

  static const appSubtitle = String.fromEnvironment(
    'APP_SUBTITLE',
    defaultValue: 'Gestione operativa',
  );

  static const logoAsset = String.fromEnvironment(
    'BRAND_LOGO_ASSET',
    defaultValue: 'assets/brand/radiotech-symbol-v1.png',
  );

  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: '',
  );
}
