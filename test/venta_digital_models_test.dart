// Pruebas de los modelos de CU19 (venta digital).
//
// No usan red ni widgets: validan el parsing defensivo del contrato real
// `VentaDigitalResponse` del backend (Decimal como number/string, items,
// nullables y el estado PENDIENTE).

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/ventas/models/venta_digital_model.dart';

void main() {
  test('codigoVenta es solo presentación (VEN-00045)', () {
    expect(codigoVenta(45), 'VEN-00045');
    expect(codigoVenta(1), 'VEN-00001');
  });

  group('VentaDigital.fromJson', () {
    test('parsea el contrato real, Decimal string y items', () {
      final VentaDigital venta = VentaDigital.fromJson(<String, dynamic>{
        'venta_id': 123,
        'carrito_id': 45,
        'cliente_id': 4,
        'sucursal_id': 2,
        'sucursal_nombre': 'Centro',
        'canal': 'MOVIL',
        'estado': 'PENDIENTE',
        'fecha_hora': '2026-09-25T10:00:00',
        'total': '599.80',
        'cantidad_total_unidades': '3',
        'items': <dynamic>[
          <String, dynamic>{
            'detalle_id': 1,
            'inventario_id': 44,
            'producto_id': 9,
            'producto_nombre': 'Camisa',
            'imagen_principal': '',
            'variante_producto_id': 7,
            'sku': 'SKU-1',
            'talla_id': 1,
            'talla_nombre': 'M',
            'color_id': 3,
            'color_nombre': 'Negro',
            'temporada_id': 2,
            'temporada_nombre': 'Verano',
            'cantidad': '2',
            'precio_unitario': '149.90',
            'subtotal_linea': '299.80',
          },
        ],
      });

      expect(venta.ventaId, 123);
      expect(venta.carritoId, 45);
      expect(venta.clienteId, 4);
      expect(venta.sucursalId, 2);
      expect(venta.canal, 'MOVIL');
      expect(venta.estado, 'PENDIENTE');
      expect(venta.estaPendiente, isTrue);
      expect(venta.total, 599.80);
      expect(venta.totalFormateado, 'Bs 599.80');
      expect(venta.cantidadTotalUnidades, 3);
      expect(venta.cantidadLineas, 1);
      expect(venta.tieneItems, isTrue);
      expect(venta.codigo, 'VEN-00123');
      expect(venta.sucursalEtiqueta, 'Centro');
      expect(venta.fechaHora, isNotNull);

      final VentaItem item = venta.items.single;
      expect(item.productoNombre, 'Camisa');
      expect(item.imagenPrincipal, isNull);
      expect(item.varianteProductoId, 7);
      expect(item.tallaNombre, 'M');
      expect(item.colorNombre, 'Negro');
      expect(item.cantidad, 2);
      expect(item.precioUnitario, 149.90);
      expect(item.precioUnitarioFormateado, 'Bs 149.90');
      expect(item.subtotalLinea, 299.80);
      expect(item.subtotalFormateado, 'Bs 299.80');
    });

    test('soporta Decimal numérico, carrito_id null y listas ausentes', () {
      final VentaDigital venta = VentaDigital.fromJson(<String, dynamic>{
        'venta_id': 7,
        'carrito_id': null,
        'cliente_id': 1,
        'sucursal_id': 3,
        'sucursal_nombre': '   ',
        'canal': 'WEB',
        'estado': 'PENDIENTE',
        'total': 100,
        'cantidad_total_unidades': 0,
        'items': null,
      });

      expect(venta.carritoId, isNull);
      expect(venta.total, 100.0);
      expect(venta.items, isEmpty);
      expect(venta.tieneItems, isFalse);
      expect(venta.cantidadLineas, 0);
      expect(venta.fechaHora, isNull);
      expect(venta.sucursalEtiqueta, 'Sucursal 3');
    });

    test('un estado distinto de PENDIENTE no se marca como pendiente', () {
      final VentaDigital venta = VentaDigital.fromJson(<String, dynamic>{
        'venta_id': 9,
        'cliente_id': 1,
        'sucursal_id': 1,
        'estado': 'PAGADA',
      });

      expect(venta.estaPendiente, isFalse);
    });

    test('item con variante/talla/color/temporada nulos no falla', () {
      final VentaItem item = VentaItem.fromJson(<String, dynamic>{
        'detalle_id': 1,
        'inventario_id': 2,
        'producto_id': 3,
        'producto_nombre': 'Polo',
        'precio_unitario': '50.00',
        'subtotal_linea': 100,
      });

      expect(item.varianteProductoId, isNull);
      expect(item.tallaId, isNull);
      expect(item.colorId, isNull);
      expect(item.temporadaId, isNull);
      expect(item.tallaNombre, '');
      expect(item.subtotalLinea, 100.0);
    });
  });
}
