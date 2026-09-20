// Pruebas de CheckoutDigitalPage (CU19).
//
// No usan red: inyectan un CarritoService y un VentaDigitalService falsos.
// Cubren carga, render read-only, confirmación, doble submit, éxito PENDIENTE,
// errores 401/409, retorno `true` y el CTA de CU22 deshabilitado.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/autenticacion_seguridad/pages/login/login_page.dart';
import 'package:fashionstore_mobile/features/carrito/models/carrito_model.dart';
import 'package:fashionstore_mobile/features/carrito/services/carrito_service.dart';
import 'package:fashionstore_mobile/features/carrito/widgets/boton_gradiente.dart';
import 'package:fashionstore_mobile/features/carrito/widgets/cantidad_stepper.dart';
import 'package:fashionstore_mobile/features/ventas/models/venta_digital_model.dart';
import 'package:fashionstore_mobile/features/ventas/pages/checkout_digital_page.dart';
import 'package:fashionstore_mobile/features/ventas/pages/pago_electronico_page.dart';
import 'package:fashionstore_mobile/features/ventas/services/venta_digital_service.dart';

const int _carritoId = 45;

CarritoItem _item({int cantidad = 2}) => CarritoItem(
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
  cantidad: cantidad,
  stockDisponible: 5,
  subtotalLinea: 149.90 * cantidad,
);

CarritoDetalle _carrito({String estado = 'ACTIVO'}) => CarritoDetalle(
  carritoId: _carritoId,
  sucursalId: 2,
  sucursalNombre: 'Centro',
  estado: estado,
  fechaCreacion: null,
  fechaActualizacion: null,
  items: <CarritoItem>[_item()],
  cantidadTotalUnidades: 2,
  subtotalCarrito: 299.80,
);

VentaDigital _venta() => VentaDigital.fromJson(<String, dynamic>{
  'venta_id': 123,
  'carrito_id': _carritoId,
  'cliente_id': 4,
  'sucursal_id': 2,
  'sucursal_nombre': 'Centro',
  'canal': 'MOVIL',
  'estado': 'PENDIENTE',
  'fecha_hora': '2026-09-25T10:00:00',
  'total': '599.80',
  'cantidad_total_unidades': 2,
  'items': <dynamic>[],
});

class _FakeCarritoService extends CarritoService {
  _FakeCarritoService(this.carrito);

  final CarritoDetalle carrito;
  int llamadas = 0;

  @override
  Future<CarritoDetalle> obtenerCarrito(int carritoId) async {
    llamadas++;
    return carrito;
  }
}

class _FakeVentaService extends VentaDigitalService {
  _FakeVentaService({this.resultado, this.error, this.completer});

  final VentaDigital? resultado;
  final Object? error;
  final Completer<VentaDigital>? completer;
  int llamadas = 0;

  @override
  Future<VentaDigital> realizarCompra(int carritoId) async {
    llamadas++;
    final Completer<VentaDigital>? pendiente = completer;
    if (pendiente != null) return pendiente.future;
    final Object? fallo = error;
    if (fallo != null) throw fallo;
    return resultado!;
  }
}

Widget _app({
  required _FakeCarritoService carrito,
  required _FakeVentaService venta,
}) => MaterialApp(
  home: CheckoutDigitalPage(
    carritoId: _carritoId,
    carritoService: carrito,
    ventaService: venta,
  ),
);

Future<void> _confirmarCompra(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(BotonGradiente, 'CONFIRMAR COMPRA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CONFIRMAR'));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    // SessionExpired usa AuthStorage: sin este mock, el almacenamiento seguro
    // no responde en el entorno de pruebas.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('carga el carrito y muestra el resumen read-only', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(resultado: _venta());

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    expect(carrito.llamadas, 1);
    expect(find.text('Centro'), findsOneWidget);
    expect(find.text('Camisa Oxford'), findsOneWidget);
    expect(find.text('Bs 299.80'), findsWidgets);
    expect(
      find.widgetWithText(BotonGradiente, 'CONFIRMAR COMPRA'),
      findsOneWidget,
    );
    // Read-only: no hay stepper de cantidades en el checkout.
    expect(find.byType(CantidadStepper), findsNothing);

    await tester.scrollUntilVisible(find.text('VOLVER AL CARRITO'), 200);
    expect(find.text('VOLVER AL CARRITO'), findsOneWidget);
  });

  testWidgets('confirmar realiza una sola llamada y muestra PENDIENTE', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(resultado: _venta());

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await _confirmarCompra(tester);
    await tester.pump();

    expect(venta.llamadas, 1);
    expect(find.text('Compra preparada'), findsOneWidget);
    expect(find.text('Venta #123'), findsOneWidget);
    expect(find.text('PENDIENTE DE PAGO'), findsOneWidget);
    expect(find.text('Total: Bs 599.80'), findsOneWidget);
    expect(find.text('Pago aprobado'), findsNothing);
    expect(find.text('Compra completada'), findsNothing);
  });

  testWidgets('doble submit: no vuelve a llamar mientras procesa', (
    tester,
  ) async {
    final Completer<VentaDigital> completer = Completer<VentaDigital>();
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(completer: completer);

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await _confirmarCompra(tester);

    expect(venta.llamadas, 1);
    // El CTA queda cargando/deshabilitado: un segundo intento no llama de nuevo.
    await tester.tap(find.byType(BotonGradiente));
    await tester.pump();
    expect(venta.llamadas, 1);

    completer.complete(_venta());
    await tester.pump();
    await tester.pump();
    expect(find.text('Compra preparada'), findsOneWidget);
  });

  testWidgets('401 cierra la sesión y navega al login', (tester) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(
      error: const VentaDigitalException(
        'Tu sesión expiró. Vuelve a iniciar sesión.',
        statusCode: 401,
        unauthorized: true,
      ),
    );

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await _confirmarCompra(tester);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('409 muestra el mensaje y revalida el carrito', (tester) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(
      error: const VentaDigitalException(
        'El stock cambió y no alcanza para completar la compra.',
        statusCode: 409,
        conflicto: true,
      ),
    );

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await _confirmarCompra(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('stock'), findsWidgets);
    // Carga inicial + revalidación tras el conflicto.
    expect(carrito.llamadas, 2);
  });

  testWidgets('devuelve true al volver tras una conversión exitosa', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(resultado: _venta());
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
    await tester.pump();

    await _confirmarCompra(tester);
    await tester.pump();
    expect(find.text('Compra preparada'), findsOneWidget);

    await tester.tap(find.text('VOLVER A MIS CARRITOS'));
    await tester.pumpAndSettle();

    expect(resultado, isTrue);
  });

  testWidgets('CTA CONTINUAR AL PAGO se habilita y abre CU22', (tester) async {
    final _FakeCarritoService carrito = _FakeCarritoService(_carrito());
    final _FakeVentaService venta = _FakeVentaService(resultado: _venta());

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await _confirmarCompra(tester);
    await tester.pump();

    final BotonGradiente cta = tester.widget<BotonGradiente>(
      find.widgetWithText(BotonGradiente, 'CONTINUAR AL PAGO'),
    );
    expect(cta.onPressed, isNotNull);

    await tester.tap(find.text('CONTINUAR AL PAGO'));
    await tester.pumpAndSettle();

    expect(find.byType(PagoElectronicoPage), findsOneWidget);
    // Sin STRIPE_PUBLISHABLE_KEY en pruebas, CU22 avisa sin crash.
    expect(find.text('Pago electrónico no configurado.'), findsOneWidget);
  });
}
