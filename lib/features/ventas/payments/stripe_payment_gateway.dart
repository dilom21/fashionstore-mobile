/// Abstracción del SDK de Stripe (flutter_stripe) para CU22.
///
/// La UI de pago depende de esta interfaz y no del singleton nativo
/// `Stripe.instance`. Así los `flutter test` pueden usar un fake sin plugin
/// nativo, sin internet y sin claves reales.
library;

/// Resultado de presentar el PaymentSheet.
enum StripeSheetOutcome {
  /// El SDK terminó la presentación (el cobro puede haberse realizado o no;
  /// el backend es la autoridad final).
  completed,

  /// El usuario cerró/canceló el PaymentSheet: no equivale a un rechazo.
  canceled,
}

/// Error seguro del gateway Stripe (nunca expone secretos ni datos de tarjeta).
class StripePaymentGatewayException implements Exception {
  /// Crea el error. [canceled] distingue la cancelación del usuario.
  const StripePaymentGatewayException(this.message, {this.canceled = false});

  /// Mensaje apto para mostrar al cliente.
  final String message;

  /// `true` cuando el usuario canceló la hoja de pago.
  final bool canceled;

  @override
  String toString() =>
      'StripePaymentGatewayException(canceled: $canceled): $message';
}

/// Contrato mínimo del gateway de pago con Stripe PaymentSheet.
abstract interface class StripePaymentGateway {
  /// Indica si existe una publishable key utilizable.
  bool get isConfigured;

  /// Configura la clave publicable y el esquema de retorno en el SDK.
  Future<void> initialize();

  /// Prepara el PaymentSheet con el `client_secret` del PaymentIntent.
  Future<void> initPaymentSheet({required String clientSecret});

  /// Presenta el PaymentSheet y devuelve el resultado de la interacción.
  Future<StripeSheetOutcome> presentPaymentSheet();
}
