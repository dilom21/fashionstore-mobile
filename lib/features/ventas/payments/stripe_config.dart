/// Configuración de Stripe para la app móvil de VANTER MEN (CU22).
///
/// La clave publicable (`pk_test_...`) no es un secreto, pero se inyecta en
/// tiempo de compilación para no hardcodearla:
///
///   flutter run \
///     --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
///     --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
///
/// Nunca deben viajar a la app `sk_test_...` ni `whsec_...`: son secretos del
/// backend. El SDK móvil solo necesita la publishable key.
class StripeConfig {
  /// Clase de solo constantes: no debe instanciarse.
  const StripeConfig._();

  /// Clave publicable de Stripe (`pk_test_...` o `pk_live_...`).
  static const String publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  /// Esquema de retorno registrado en Android/iOS.
  ///
  /// Debe coincidir con `Stripe.urlScheme`, el `returnURL` del PaymentSheet,
  /// el `intent-filter` de AndroidManifest y `CFBundleURLTypes` de Info.plist.
  static const String urlScheme = 'vantermen';

  /// URL de retorno usada por los métodos de pago que requieren redirección.
  static const String returnUrl = 'vantermen://stripe-redirect';

  /// Nombre del comercio mostrado por el PaymentSheet.
  static const String merchantDisplayName = 'VANTER MEN';

  /// Mensaje seguro cuando la publishable key no está configurada.
  static const String missingKeyMessage = 'Pago electrónico no configurado.';

  /// Indica si la clave inyectada en tiempo de compilación es utilizable.
  static bool get isConfigured => estaConfigurada(publishableKey);

  /// Valida una clave arbitraria (inyectable en pruebas).
  static bool estaConfigurada(String key) => key.trim().isNotEmpty;
}
