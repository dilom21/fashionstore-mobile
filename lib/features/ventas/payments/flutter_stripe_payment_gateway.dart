import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'stripe_config.dart';
import 'stripe_payment_gateway.dart';

/// Implementación real de [StripePaymentGateway] sobre `flutter_stripe`.
///
/// Envuelve el singleton `Stripe.instance`. No se debe invocar directamente
/// desde la UI: la página de pago depende de la abstracción para poder probarse
/// con un fake sin plugin nativo.
class FlutterStripePaymentGateway implements StripePaymentGateway {
  /// Crea el gateway. [publishableKey] es un punto de inyección para pruebas;
  /// en producción se usa [StripeConfig.publishableKey].
  FlutterStripePaymentGateway({String? publishableKey})
    : _publishableKey = (publishableKey ?? StripeConfig.publishableKey).trim();

  final String _publishableKey;

  @override
  bool get isConfigured => StripeConfig.estaConfigurada(_publishableKey);

  @override
  Future<void> initialize() async {
    if (!isConfigured) {
      throw const StripePaymentGatewayException(StripeConfig.missingKeyMessage);
    }
    // Nunca se imprime la clave.
    Stripe.publishableKey = _publishableKey;
    Stripe.urlScheme = StripeConfig.urlScheme;
    await Stripe.instance.applySettings();
  }

  @override
  Future<void> initPaymentSheet({required String clientSecret}) async {
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: StripeConfig.merchantDisplayName,
        returnURL: StripeConfig.returnUrl,
        style: ThemeMode.dark,
      ),
    );
  }

  @override
  Future<StripeSheetOutcome> presentPaymentSheet() async {
    try {
      await Stripe.instance.presentPaymentSheet();
      return StripeSheetOutcome.completed;
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) {
        return StripeSheetOutcome.canceled;
      }
      throw const StripePaymentGatewayException(
        'No pudimos completar el pago. Inténtalo nuevamente.',
      );
    } on StripePaymentGatewayException {
      rethrow;
    } catch (_) {
      throw const StripePaymentGatewayException(
        'No pudimos completar el pago. Inténtalo nuevamente.',
      );
    }
  }
}
