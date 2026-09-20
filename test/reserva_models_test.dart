// Pruebas de los modelos y helpers de CU16 (reserva de prendas).
//
// No usan red ni widgets: validan el parsing defensivo del contrato real y las
// reglas de estado que aplica la interfaz (solo PENDIENTE y CONFIRMADA pueden
// cancelarse; VENCIDA es solo histórica).

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/core/utils/date_formatters.dart';
import 'package:fashionstore_mobile/features/reservas/models/reserva_model.dart';

void main() {
  group('EstadoReserva', () {
    test('mapea los estados reales del backend', () {
      expect(EstadoReserva.desde('PENDIENTE'), EstadoReserva.pendiente);
      expect(EstadoReserva.desde(' confirmada '), EstadoReserva.confirmada);
      expect(EstadoReserva.desde('ATENDIDA'), EstadoReserva.atendida);
      expect(EstadoReserva.desde('CANCELADA'), EstadoReserva.cancelada);
      expect(EstadoReserva.desde('VENCIDA'), EstadoReserva.vencida);
      expect(EstadoReserva.desde('OTRO'), EstadoReserva.desconocido);
      expect(EstadoReserva.desde(null), EstadoReserva.desconocido);
    });

    test('solo PENDIENTE y CONFIRMADA son cancelables', () {
      expect(EstadoReserva.pendiente.esCancelable, isTrue);
      expect(EstadoReserva.confirmada.esCancelable, isTrue);
      expect(EstadoReserva.atendida.esCancelable, isFalse);
      expect(EstadoReserva.cancelada.esCancelable, isFalse);
      expect(EstadoReserva.vencida.esCancelable, isFalse);
      expect(EstadoReserva.desconocido.esCancelable, isFalse);
    });
  });

  test('codigoReserva es solo presentación (RES-00044)', () {
    expect(codigoReserva(44), 'RES-00044');
    expect(codigoReserva(1), 'RES-00001');
  });

  group('ReservaDetalle.fromJson', () {
    test('parsea el contrato real y sus items', () {
      final ReservaDetalle reserva = ReservaDetalle.fromJson(<String, dynamic>{
        'reserva_id': 44,
        'carrito_id': 7,
        'cliente_id': 4,
        'sucursal_id': 2,
        'sucursal_nombre': 'Centro',
        'fecha_reserva': '2026-09-25T10:00:00',
        'fecha_atencion': '2026-09-26T15:30:00',
        'estado': 'PENDIENTE',
        'observacion': '   ',
        'cantidad_total_unidades': '5',
        'items': <dynamic>[
          <String, dynamic>{
            'detalle_id': 1,
            'inventario_id': 44,
            'producto_id': 9,
            'producto_nombre': 'Camisa',
            'imagen_principal': '',
            'sku': 'SKU-1',
            'talla_nombre': 'M',
            'color_nombre': 'Negro',
            'temporada_nombre': 'Verano',
            'cantidad': '2',
          },
        ],
      });

      expect(reserva.codigo, 'RES-00044');
      expect(reserva.estadoReserva, EstadoReserva.pendiente);
      expect(reserva.esCancelable, isTrue);
      expect(reserva.observacion, isNull);
      expect(reserva.cantidadTotalUnidades, 5);
      expect(reserva.cantidadLineas, 1);
      expect(reserva.tieneItems, isTrue);
      expect(reserva.items.single.cantidad, 2);
      expect(reserva.items.single.imagenPrincipal, isNull);
      expect(reserva.sucursalEtiqueta, 'Centro');
    });

    test('soporta listas ausentes y sucursal sin nombre', () {
      final ReservaDetalle reserva = ReservaDetalle.fromJson(<String, dynamic>{
        'reserva_id': 1,
        'sucursal_id': 3,
        'estado': 'VENCIDA',
        'items': null,
      });

      expect(reserva.items, isEmpty);
      expect(reserva.tieneItems, isFalse);
      expect(reserva.sucursalEtiqueta, 'Sucursal 3');
      expect(reserva.esCancelable, isFalse);
      expect(reserva.fechaAtencion, isNull);
    });
  });

  test('ReservaListaResponse usa total_reservas del backend', () {
    final ReservaListaResponse lista = ReservaListaResponse.fromJson(
      <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{
            'reserva_id': 5,
            'sucursal_nombre': 'Ventura',
            'estado': 'CONFIRMADA',
            'cantidad_lineas': 2,
            'cantidad_unidades': 3,
            'observacion': 'Llamar antes',
            'fecha_atencion': '2026-10-01T09:15:00',
          },
        ],
        'total_reservas': 1,
      },
    );

    expect(lista.totalReservas, 1);
    expect(lista.estaVacio, isFalse);
    expect(lista.items.single.codigo, 'RES-00005');
    expect(lista.items.single.cantidadUnidades, 3);
    expect(lista.items.single.observacionCorta, 'Llamar antes');
    expect(lista.items.single.esCancelable, isTrue);
  });

  test('formatearIsoLocal construye el ISO local de fecha_atencion', () {
    expect(
      formatearIsoLocal(DateTime(2026, 9, 25, 15, 30, 0)),
      '2026-09-25T15:30:00',
    );
  });
}
