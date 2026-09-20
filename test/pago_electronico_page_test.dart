// Pruebas de PagoElectronicoPage (CU22).
//
// No usan red ni plugin nativo: inyectan un PagoElectronicoService y un
// StripePaymentGateway falsos. Cubren configuración ausente, inicio, pago,
// cancelación, error, doble tap, polling, APROBADO/RECHAZADO/ANULADO, timeout,
// reconsulta y 401.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/autenticacion_seguridad/pages/login/login_page.dart';
import 'package:fashionstore_mobile/features/carrito/widgets/boton_gradiente.dart';
import 'package:fashionstore_mobile/features/ventas/models/pago_electronico_model.dart';
import 'package:fashionstore_mobile/features/ventas/pages/pago_electronico_page.dart';
import 'package:fashionstore_mobile/features/ventas/payments/stripe_payment_gateway.dart';
import 'package:fashionstore_mobile/features/ventas/services/pago_electronico_service.dart';

const int _ventaId = 123;

IntencionPago _intencion({double monto = 599.80}) =>
    IntencionPago.fromJson(<String, dynamic>{
      'venta_id': _ventaId,
      'pago_id': 77,
      'payment_intent_id': 'pi_123',
      'client_secret': 'pi_123_secret_abc',
      'monto': monto.toStringAsFixed(2),
      'moneda': 'bob',
      'estado_pago': 'PENDIENTE',
    });

EstadoPagoVenta _estado({
  required String estadoVenta,
  required String? estadoPago,
}) => EstadoPagoVenta.fromJson(<String, dynamic>{
  'venta_id': _ventaId,
  'estado_venta': estadoVenta,
  'pago_id': 77,
  'estado_pago': estadoPago,
  'payment_intent_id': 'pi_123',
});

class _FakeGateway implements StripePaymentGateway {
  _FakeGateway({
    this.configurado = true,
    this.outcome = StripeSheetOutcome.completed,
    this.initializeError,
    this.presentError,
    this.presentCompleter,
  });

  bool configurado;
  StripeSheetOutcome outcome;
  Object? initializeError;
  Object? presentError;
  Completer<StripeSheetOutcome>? presentCompleter;

  int initCalls = 0;
  int sheetCalls = 0;
  int presentCalls = 0;
  String? lastClientSecret;

  @override
  bool get isConfigured => configurado;

  @override
  Future<void> initialize() async {
    initCalls++;
    final Object? error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<void> initPaymentSheet({required String clientSecret}) async {
    sheetCalls++;
    lastClientSecret = clientSecret;
  }

  @override
  Future<StripeSheetOutcome> presentPaymentSheet() async {
    presentCalls++;
    final Completer<StripeSheetOutcome>? completer = presentCompleter;
    if (completer != null) return completer.future;
    final Object? error = presentError;
    if (error != null) throw error;
    return outcome;
  }
}

class _FakePagoService extends PagoElectronicoService {
  _FakePagoService({
    IntencionPago? intencion,
    this.intencionError,
    this.estados = const <EstadoPagoVenta>[],
    this.estadoError,
  }) : intencion = intencion ?? _intencion();

  final IntencionPago intencion;
  final Object? intencionError;
  final List<EstadoPagoVenta> estados;
  final Object? estadoError;

  int intencionCalls = 0;
  int estadoCalls = 0;
  int? ultimaVentaId;

  @override
  Future<IntencionPago> crearIntencion(int ventaId) async {
    intencionCalls++;
    ultimaVentaId = ventaId;
    final Object? error = intencionError;
    if (error != null) throw error;
    return intencion;
  }

  @override
  Future<EstadoPagoVenta> consultarEstado(int ventaId) async {
    estadoCalls++;
    final Object? error = estadoError;
    if (error != null) throw error;
    final int indice = (estadoCalls - 1).clamp(0, estados.length - 1);
    return estados[indice];
  }
}

Widget _app({
  required PagoElectronicoService service,
  required StripePaymentGateway gateway,
  Duration interval = Duration.zero,
  int maxIntentos = 20,
  double? total,
}) => MaterialApp(
  home: PagoElectronicoPage(
    ventaId: _ventaId,
    total: total,
    service: service,
    gateway: gateway,
    pollingInterval: interval,
    maxIntentos: maxIntentos,
  ),
);

Future<void> _pagar(WidgetTester tester) async {
  await tester.tap(find.text('PAGAR AHORA'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // SessionExpired usa AuthStorage: sin este mock, el almacenamiento seguro
    // no responde en el entorno de pruebas.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('sin publishable key muestra aviso sin crash y sin red', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(configurado: false);
    final _FakePagoService service = _FakePagoService();

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('Pago electrónico no configurado.'), findsOneWidget);
    expect(gateway.initCalls, 0);
    expect(service.intencionCalls, 0);
  });

  testWidgets('inicia Stripe, crea la intención e inicializa el PaymentSheet', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService();

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();

    expect(gateway.initCalls, 1);
    expect(service.intencionCalls, 1);
    expect(service.ultimaVentaId, _ventaId);
    expect(gateway.sheetCalls, 1);
    expect(gateway.lastClientSecret, 'pi_123_secret_abc');
    expect(find.text('PAGAR AHORA'), findsOneWidget);
    expect(find.text('Venta #123'), findsOneWidget);
  });

  testWidgets('el monto mostrado proviene del backend, no del total de CU19', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      intencion: _intencion(monto: 599.80),
    );

    await tester.pumpWidget(
      _app(service: service, gateway: gateway, total: 1.0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bs 599.80'), findsWidgets);
    expect(find.text('Bs 1.00'), findsNothing);
  });

  testWidgets('error de inicialización muestra mensaje y permite reintentar', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(
      initializeError: const StripePaymentGatewayException(
        'Pago electrónico no configurado.',
      ),
    );
    final _FakePagoService service = _FakePagoService();

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('Pago electrónico no configurado.'), findsOneWidget);
    expect(service.intencionCalls, 0);
  });

  testWidgets('pago APROBADO por backend muestra Compra completada', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'PENDIENTE'),
        _estado(estadoVenta: 'COMPLETADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(gateway.presentCalls, 1);
    expect(service.estadoCalls, greaterThanOrEqualTo(2));
    expect(find.text('Compra completada'), findsOneWidget);
    expect(find.text('Pago aprobado'), findsOneWidget);
    expect(find.text('Monto Bs 599.80'), findsOneWidget);
  });

  testWidgets('cancelación del usuario no confirma ni marca rechazo', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(
      outcome: StripeSheetOutcome.canceled,
    );
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'COMPLETADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.textContaining('Pago cancelado'), findsWidgets);
    expect(find.text('Compra completada'), findsNothing);
    expect(find.text('Pago rechazado'), findsNothing);
    expect(service.estadoCalls, 0);
    expect(find.text('PAGAR AHORA'), findsOneWidget);
  });

  testWidgets('error del SDK muestra mensaje y no confirma la venta', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(
      presentError: const StripePaymentGatewayException(
        'No pudimos completar el pago. Inténtalo nuevamente.',
      ),
    );
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'COMPLETADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.textContaining('No pudimos completar el pago'), findsWidgets);
    expect(find.text('Compra completada'), findsNothing);
    expect(service.estadoCalls, 0);
  });

  testWidgets('doble tap no presenta el PaymentSheet dos veces', (
    tester,
  ) async {
    final Completer<StripeSheetOutcome> completer =
        Completer<StripeSheetOutcome>();
    final _FakeGateway gateway = _FakeGateway(presentCompleter: completer);
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'COMPLETADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PAGAR AHORA'));
    await tester.pump();
    await tester.tap(find.byType(BotonGradiente));
    await tester.pump();

    expect(gateway.presentCalls, 1);

    completer.complete(StripeSheetOutcome.completed);
    await tester.pumpAndSettle();
    expect(find.text('Compra completada'), findsOneWidget);
  });

  testWidgets('RECHAZADO muestra aviso y permite reintentar la intención', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'RECHAZADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.text('Pago rechazado'), findsOneWidget);
    expect(find.text('Tu venta sigue pendiente.'), findsOneWidget);
    expect(find.text('Compra completada'), findsNothing);

    await tester.tap(find.text('REINTENTAR PAGO'));
    await tester.pumpAndSettle();

    expect(service.intencionCalls, 2);
    expect(find.text('PAGAR AHORA'), findsOneWidget);
  });

  testWidgets('ANULADO permite reintentar con una nueva intención', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'ANULADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.text('Pago anulado'), findsOneWidget);
    expect(find.text('Tu venta sigue pendiente.'), findsOneWidget);

    await tester.tap(find.text('REINTENTAR PAGO'));
    await tester.pumpAndSettle();

    expect(service.intencionCalls, 2);
    expect(find.text('PAGAR AHORA'), findsOneWidget);
  });

  testWidgets('timeout del webhook ofrece reconsultar sin volver a cobrar', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'PENDIENTE'),
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'PENDIENTE'),
        _estado(estadoVenta: 'PENDIENTE', estadoPago: 'PENDIENTE'),
      ],
    );

    await tester.pumpWidget(
      _app(service: service, gateway: gateway, maxIntentos: 3),
    );
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.text('Pago en confirmación'), findsOneWidget);
    expect(find.text('RECONSULTAR ESTADO'), findsOneWidget);
    expect(find.text('Pago rechazado'), findsNothing);
    expect(service.estadoCalls, 3);
    expect(gateway.presentCalls, 1);

    await tester.tap(find.text('RECONSULTAR ESTADO'));
    await tester.pumpAndSettle();

    expect(service.estadoCalls, greaterThan(3));
    expect(service.intencionCalls, 1);
    expect(gateway.presentCalls, 1);
  });

  testWidgets('401 durante el polling cierra la sesión', (tester) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estadoError: const PagoElectronicoException(
        'Tu sesión expiró. Vuelve a iniciar sesión.',
        statusCode: 401,
        unauthorized: true,
      ),
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('401 al crear la intención cierra la sesión', (tester) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      intencionError: const PagoElectronicoException(
        'Tu sesión expiró. Vuelve a iniciar sesión.',
        statusCode: 401,
        unauthorized: true,
      ),
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('CANCELADA + APROBADO muestra Reembolso en proceso sin CTA de pago', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'CANCELADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.text('Reembolso en proceso'), findsWidgets);
    expect(
      find.text('No se te volverá a cobrar esta venta.'),
      findsOneWidget,
    );
    expect(find.text('RECONSULTAR ESTADO'), findsOneWidget);
    expect(find.text('PAGAR AHORA'), findsNothing);
    expect(find.text('REINTENTAR PAGO'), findsNothing);
    expect(find.text('Compra completada'), findsNothing);
  });

  testWidgets('CANCELADA + REEMBOLSADO muestra Pago reembolsado terminal', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'CANCELADA', estadoPago: 'REEMBOLSADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(find.text('Pago reembolsado'), findsWidgets);
    expect(find.text('El pago fue devuelto correctamente.'), findsOneWidget);
    expect(find.text('VOLVER AL INICIO'), findsOneWidget);
    expect(find.text('RECONSULTAR ESTADO'), findsNothing);
    expect(find.text('PAGAR AHORA'), findsNothing);
    expect(find.text('Compra completada'), findsNothing);
  });

  testWidgets('RECONSULTAR ESTADO en reembolso no crea intención ni PaymentSheet', (
    tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway();
    final _FakePagoService service = _FakePagoService(
      estados: <EstadoPagoVenta>[
        _estado(estadoVenta: 'CANCELADA', estadoPago: 'APROBADO'),
      ],
    );

    await tester.pumpWidget(_app(service: service, gateway: gateway));
    await tester.pumpAndSettle();
    await _pagar(tester);

    expect(service.intencionCalls, 1);
    expect(gateway.presentCalls, 1);
    final int estadosAntes = service.estadoCalls;

    await tester.tap(find.text('RECONSULTAR ESTADO'));
    await tester.pumpAndSettle();

    expect(service.estadoCalls, greaterThan(estadosAntes));
    expect(service.intencionCalls, 1);
    expect(gateway.presentCalls, 1);
    expect(find.text('Reembolso en proceso'), findsWidgets);
  });
}
