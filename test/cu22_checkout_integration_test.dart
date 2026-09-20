// Pruebas de integración CU19 ↔ CU22.
//
// Verifican que el CTA `CONTINUAR AL PAGO` del checkout de CU19 abre el pago
// electrónico con el `ventaId` correcto, sin crear una segunda venta, y que el
// éxito del pago se propaga en la navegación. Sin red ni plugin nativo.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/carrito/models/carrito_model.dart';
import 'package:fashionstore_mobile/features/carrito/services/carrito_service.dart';
import 'package:fashionstore_mobile/features/carrito/widgets/boton_gradiente.dart';
import 'package:fashionstore_mobile/features/ventas/models/pago_electronico_model.dart';
import 'package:fashionstore_mobile/features/ventas/models/venta_digital_model.dart';
import 'package:fashionstore_mobile/features/ventas/pages/checkout_digital_page.dart';
import 'package:fashionstore_mobile/features/ventas/pages/pago_electronico_page.dart';
import 'package:fashionstore_mobile/features/ventas/payments/stripe_payment_gateway.dart';
import 'package:fashionstore_mobile/features/ventas/services/pago_electronico_service.dart';
import 'package:fashionstore_mobile/features/ventas/services/venta_digital_service.dart';

const int _carritoId = 45;
const int _ventaId = 123;

CarritoDetalle _carrito() => CarritoDetalle(
  carritoId: _carritoId,
  sucursalId: 2,
  sucursalNombre: 'Centro',
  estado: 'ACTIVO',
  fechaCreacion: null,
  fechaActualizacion: null,
  items: <CarritoItem>[
    CarritoItem(
      detalleId: 1,
      inventarioId: 44,
      productoId: 9,
      productoNombre: 'Camisa Oxford',
      precioUnitario: 149.90,
      imagenPrincipal: null,
      varianteProductoId: 7,
      sku: 'SKU-1',
      tallaId: 1,
      tallaNombre: 'M',
      colorId: 3,
      colorNombre: 'Negro',
      temporadaId: 2,
      temporadaNombre: 'Verano',
      cantidad: 2,
      stockDisponible: 5,
      subtotalLinea: 299.80,
    ),
  ],
  cantidadTotalUnidades: 2,
  subtotalCarrito: 299.80,
);

VentaDigital _venta() => VentaDigital.fromJson(<String, dynamic>{
  'venta_id': _ventaId,
  'carrito_id': _carritoId,
  'cliente_id': 4,
  'sucursal_id': 2,
  'sucursal_nombre': 'Centro',
  'canal': 'MOVIL',
  'estado': 'PENDIENTE',
  'total': '299.80',
  'cantidad_total_unidades': 2,
  'items': <dynamic>[],
});

class _FakeCarritoService extends CarritoService {
  int llamadas = 0;

  @override
  Future<CarritoDetalle> obtenerCarrito(int carritoId) async {
    llamadas++;
    return _carrito();
  }
}

class _FakeVentaService extends VentaDigitalService {
  int llamadas = 0;

  @override
  Future<VentaDigital> realizarCompra(int carritoId) async {
    llamadas++;
    return _venta();
  }
}

class _FakeGateway implements StripePaymentGateway {
  int initCalls = 0;
  int presentCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<void> initialize() async => initCalls++;

  @override
  Future<void> initPaymentSheet({required String clientSecret}) async {}

  @override
  Future<StripeSheetOutcome> presentPaymentSheet() async {
    presentCalls++;
    return StripeSheetOutcome.completed;
  }
}

class _FakePagoService extends PagoElectronicoService {
  int intencionCalls = 0;
  int? ultimaVentaId;

  @override
  Future<IntencionPago> crearIntencion(int ventaId) async {
    intencionCalls++;
    ultimaVentaId = ventaId;
    return IntencionPago.fromJson(<String, dynamic>{
      'venta_id': ventaId,
      'pago_id': 77,
      'payment_intent_id': 'pi_123',
      'client_secret': 'pi_123_secret_abc',
      'monto': '299.80',
      'moneda': 'bob',
      'estado_pago': 'PENDIENTE',
    });
  }

  @override
  Future<EstadoPagoVenta> consultarEstado(int ventaId) async =>
      EstadoPagoVenta.fromJson(<String, dynamic>{
        'venta_id': ventaId,
        'estado_venta': 'COMPLETADA',
        'pago_id': 77,
        'estado_pago': 'APROBADO',
        'payment_intent_id': 'pi_123',
      });
}

Future<void> _confirmarCompra(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(BotonGradiente, 'CONFIRMAR COMPRA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONFIRMAR'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('CONTINUAR AL PAGO usa el ventaId de CU19 y no crea otra venta', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService();
    final _FakeVentaService venta = _FakeVentaService();
    final _FakePagoService pago = _FakePagoService();
    final _FakeGateway gateway = _FakeGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutDigitalPage(
          carritoId: _carritoId,
          carritoService: carrito,
          ventaService: venta,
          pagoService: pago,
          stripeGateway: gateway,
          pagoPollingInterval: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _confirmarCompra(tester);
    expect(find.text('Compra preparada'), findsOneWidget);

    await tester.tap(find.text('CONTINUAR AL PAGO'));
    await tester.pumpAndSettle();

    expect(find.byType(PagoElectronicoPage), findsOneWidget);
    expect(pago.intencionCalls, 1);
    expect(pago.ultimaVentaId, _ventaId);
    // CU19 solo creó la venta una vez: CU22 no vuelve a llamar /ventas/digital.
    expect(venta.llamadas, 1);
  });

  testWidgets('el pago exitoso se propaga como resultado true al cerrar', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService();
    final _FakeVentaService venta = _FakeVentaService();
    final _FakePagoService pago = _FakePagoService();
    final _FakeGateway gateway = _FakeGateway();
    bool? resultado;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  resultado = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => CheckoutDigitalPage(
                        carritoId: _carritoId,
                        carritoService: carrito,
                        ventaService: venta,
                        pagoService: pago,
                        stripeGateway: gateway,
                        pagoPollingInterval: Duration.zero,
                      ),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await _confirmarCompra(tester);
    await tester.tap(find.text('CONTINUAR AL PAGO'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PAGAR AHORA'));
    await tester.pumpAndSettle();

    expect(find.text('Compra completada'), findsOneWidget);
    expect(gateway.presentCalls, 1);

    await tester.tap(find.text('VOLVER AL INICIO'));
    await tester.pumpAndSettle();

    expect(resultado, isTrue);
    expect(find.byType(CheckoutDigitalPage), findsNothing);
  });
}
