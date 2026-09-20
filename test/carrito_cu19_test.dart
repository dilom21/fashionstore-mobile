// Pruebas de integración CU19 ↔ CU15/CU16.
//
// Verifican que `IR A PAGAR` abre el checkout real (sin placeholder) y que
// `RESERVAR PRENDAS` de CU16 sigue funcionando. Sin red: se inyectan servicios.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/carrito/models/carrito_model.dart';
import 'package:fashionstore_mobile/features/carrito/pages/carrito_detalle_page.dart';
import 'package:fashionstore_mobile/features/carrito/services/carrito_service.dart';
import 'package:fashionstore_mobile/features/reservas/pages/crear_reserva_page.dart';
import 'package:fashionstore_mobile/features/ventas/models/venta_digital_model.dart';
import 'package:fashionstore_mobile/features/ventas/pages/checkout_digital_page.dart';
import 'package:fashionstore_mobile/features/ventas/services/venta_digital_service.dart';

const int _carritoId = 45;

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
    return VentaDigital.fromJson(<String, dynamic>{
      'venta_id': 123,
      'carrito_id': carritoId,
      'cliente_id': 4,
      'sucursal_id': 2,
      'sucursal_nombre': 'Centro',
      'canal': 'MOVIL',
      'estado': 'PENDIENTE',
      'total': '299.80',
      'cantidad_total_unidades': 2,
      'items': <dynamic>[],
    });
  }
}

Widget _app({
  required _FakeCarritoService carrito,
  required _FakeVentaService venta,
}) => MaterialApp(
  home: CarritoDetallePage(
    carritoId: _carritoId,
    service: carrito,
    ventaService: venta,
  ),
);

void main() {
  testWidgets('IR A PAGAR abre el checkout y ya no muestra el placeholder', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService();
    final _FakeVentaService venta = _FakeVentaService();

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    expect(find.text('IR A PAGAR'), findsOneWidget);
    expect(find.text('RESERVAR PRENDAS'), findsOneWidget);

    await tester.ensureVisible(find.text('IR A PAGAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IR A PAGAR'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckoutDigitalPage), findsOneWidget);
    expect(find.text('Proceso de pago disponible próximamente.'), findsNothing);
  });

  testWidgets('desde el checkout se confirma la compra PENDIENTE', (
    tester,
  ) async {
    final _FakeCarritoService carrito = _FakeCarritoService();
    final _FakeVentaService venta = _FakeVentaService();

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('IR A PAGAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IR A PAGAR'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('CONFIRMAR COMPRA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRMAR COMPRA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRMAR'));
    await tester.pump();
    await tester.pump();

    expect(venta.llamadas, 1);
    expect(find.text('PENDIENTE DE PAGO'), findsOneWidget);
  });

  testWidgets('RESERVAR PRENDAS de CU16 sigue funcionando', (tester) async {
    final _FakeCarritoService carrito = _FakeCarritoService();
    final _FakeVentaService venta = _FakeVentaService();

    await tester.pumpWidget(_app(carrito: carrito, venta: venta));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('RESERVAR PRENDAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESERVAR PRENDAS'));
    await tester.pumpAndSettle();

    expect(find.byType(CrearReservaPage), findsOneWidget);
  });
}
