// Pruebas de StripeConfig (CU22).
//
// Verifican el comportamiento con y sin publishable key sin depender del
// plugin nativo ni de claves reales. En `flutter test` no se inyecta
// `--dart-define=STRIPE_PUBLISHABLE_KEY`, así que la clave es vacía.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/ventas/payments/stripe_config.dart';

void main() {
  test('sin STRIPE_PUBLISHABLE_KEY no está configurado y no lanza', () {
    expect(StripeConfig.publishableKey.trim(), isEmpty);
    expect(StripeConfig.isConfigured, isFalse);
    expect(StripeConfig.missingKeyMessage, 'Pago electrónico no configurado.');
  });

  test('estaConfigurada reconoce claves válidas y rechaza vacías', () {
    expect(StripeConfig.estaConfigurada(''), isFalse);
    expect(StripeConfig.estaConfigurada('   '), isFalse);
    expect(StripeConfig.estaConfigurada('pk_test_123'), isTrue);
    expect(StripeConfig.estaConfigurada('  pk_test_123  '), isTrue);
  });

  test('returnURL y esquema son consistentes', () {
    expect(StripeConfig.urlScheme, 'vantermen');
    expect(StripeConfig.returnUrl, 'vantermen://stripe-redirect');
    expect(
      StripeConfig.returnUrl.startsWith('${StripeConfig.urlScheme}://'),
      isTrue,
    );
    expect(StripeConfig.merchantDisplayName, 'VANTER MEN');
  });
}
