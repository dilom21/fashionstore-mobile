// Pruebas de los modelos de CU22 (IntencionPago / EstadoPagoVenta).
//
// Parsing defensivo del contrato real del backend, sin red ni plugin nativo.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/ventas/models/pago_electronico_model.dart';

void main() {
  group('IntencionPago', () {
    test('parsea el contrato real con monto Decimal string', () {
      final IntencionPago intencion = IntencionPago.fromJson(<String, dynamic>{
        'venta_id': 123,
        'pago_id': 77,
        'payment_intent_id': 'pi_123',
        'client_secret': 'pi_123_secret_abc',
        'monto': '599.80',
        'moneda': 'bob',
        'estado_pago': 'PENDIENTE',
      });

      expect(intencion.ventaId, 123);
      expect(intencion.pagoId, 77);
      expect(intencion.paymentIntentId, 'pi_123');
      expect(intencion.tieneClientSecret, isTrue);
      expect(intencion.monto, 599.80);
      expect(intencion.montoFormateado, 'Bs 599.80');
      expect(intencion.monedaNormalizada, 'BOB');
      expect(intencion.estadoPago, 'PENDIENTE');
    });

    test('acepta monto numérico y client_secret null sin romper', () {
      final IntencionPago intencion = IntencionPago.fromJson(<String, dynamic>{
        'venta_id': '9',
        'pago_id': 1,
        'payment_intent_id': 'pi_9',
        'client_secret': null,
        'monto': 10,
        'moneda': 'BOB',
        'estado_pago': 'PENDIENTE',
      });

      expect(intencion.ventaId, 9);
      expect(intencion.monto, 10);
      expect(intencion.tieneClientSecret, isFalse);
    });

    test('client_secret vacío o en blanco no cuenta como presente', () {
      IntencionPago intencion = IntencionPago.fromJson(<String, dynamic>{
        'venta_id': 1,
        'pago_id': 1,
        'payment_intent_id': 'pi_1',
        'client_secret': '   ',
        'monto': '1.00',
        'moneda': 'BOB',
        'estado_pago': 'PENDIENTE',
      });
      expect(intencion.tieneClientSecret, isFalse);

      intencion = IntencionPago.fromJson(<String, dynamic>{});
      expect(intencion.ventaId, 0);
      expect(intencion.tieneClientSecret, isFalse);
    });
  });

  group('EstadoPagoVenta', () {
    EstadoPagoVenta estado(Map<String, dynamic> json) =>
        EstadoPagoVenta.fromJson(json);

    test('APROBADO implica compra completada y estado terminal', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'COMPLETADA',
        'pago_id': 77,
        'estado_pago': 'APROBADO',
        'payment_intent_id': 'pi_123',
      });

      expect(e.pagoAprobado, isTrue);
      expect(e.ventaFinalizada, isTrue);
      expect(e.compraCompletada, isTrue);
      expect(e.esTerminal, isTrue);
      expect(e.pagoRechazado, isFalse);
    });

    test('RECHAZADO no confirma la compra y es terminal', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'PENDIENTE',
        'pago_id': 77,
        'estado_pago': 'RECHAZADO',
        'payment_intent_id': 'pi_123',
      });

      expect(e.pagoRechazado, isTrue);
      expect(e.compraCompletada, isFalse);
      expect(e.esTerminal, isTrue);
    });

    test('ANULADO no confirma la compra y es terminal', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'PENDIENTE',
        'pago_id': null,
        'estado_pago': 'ANULADO',
        'payment_intent_id': null,
      });

      expect(e.pagoAnulado, isTrue);
      expect(e.compraCompletada, isFalse);
      expect(e.esTerminal, isTrue);
      expect(e.pagoId, isNull);
    });

    test('CANCELADA + APROBADO es reembolso en proceso, nunca éxito', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'CANCELADA',
        'pago_id': 221,
        'estado_pago': 'APROBADO',
        'payment_intent_id': 'pi_467',
      });

      expect(e.ventaCancelada, isTrue);
      expect(e.pagoAprobado, isTrue);
      expect(e.estadoVisual, EstadoVisualPago.reembolsoEnProceso);
      expect(e.compraCompletada, isFalse);
      expect(e.esTerminal, isTrue);
    });

    test('CANCELADA + REEMBOLSADO es reembolso completado terminal', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'CANCELADA',
        'pago_id': 221,
        'estado_pago': 'REEMBOLSADO',
        'payment_intent_id': 'pi_467',
      });

      expect(e.pagoReembolsado, isTrue);
      expect(e.estadoVisual, EstadoVisualPago.reembolsado);
      expect(e.compraCompletada, isFalse);
      expect(e.esTerminal, isTrue);
    });

    test('CANCELADA con otro pago también queda como reembolso en proceso', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'CANCELADA',
        'pago_id': 221,
        'estado_pago': 'PENDIENTE',
      });

      expect(e.estadoVisual, EstadoVisualPago.reembolsoEnProceso);
      expect(e.compraCompletada, isFalse);
      expect(e.esTerminal, isTrue);
    });

    test('compensacion_estado opcional promueve a reembolsado', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'CANCELADA',
        'pago_id': 221,
        'estado_pago': 'APROBADO',
        'compensacion_estado': 'REEMBOLSADO',
      });

      expect(e.compensacionEstado, 'REEMBOLSADO');
      expect(e.compensacionReembolsada, isTrue);
      expect(e.estadoVisual, EstadoVisualPago.reembolsado);
    });

    test('sin compensacion_estado el mapper usa estado_venta + estado_pago', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'CANCELADA',
        'estado_pago': 'APROBADO',
      });

      expect(e.compensacionEstado, isNull);
      expect(e.estadoVisual, EstadoVisualPago.reembolsoEnProceso);
    });

    test('APROBADO sin venta finalizada sigue en confirmación', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 467,
        'estado_venta': 'PENDIENTE',
        'estado_pago': 'APROBADO',
      });

      expect(e.estadoVisual, EstadoVisualPago.enConfirmacion);
      expect(e.esTerminal, isFalse);
    });

    test('PENDIENTE y null no son terminales', () {
      final EstadoPagoVenta pendiente = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'PENDIENTE',
        'estado_pago': 'PENDIENTE',
      });
      expect(pendiente.pagoPendiente, isTrue);
      expect(pendiente.esTerminal, isFalse);
      expect(pendiente.compraCompletada, isFalse);

      final EstadoPagoVenta sinPago = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'PENDIENTE',
        'pago_id': null,
        'estado_pago': null,
        'payment_intent_id': null,
      });
      expect(sinPago.pagoPendiente, isTrue);
      expect(sinPago.esTerminal, isFalse);
    });

    test('venta PAGADA también cuenta como compra completada', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': 'PAGADA',
        'estado_pago': null,
      });
      expect(e.ventaFinalizada, isTrue);
      expect(e.compraCompletada, isTrue);
    });

    test('normaliza minúsculas y espacios', () {
      final EstadoPagoVenta e = estado(<String, dynamic>{
        'venta_id': 123,
        'estado_venta': ' completada ',
        'estado_pago': ' aprobado ',
      });
      expect(e.pagoAprobado, isTrue);
      expect(e.ventaFinalizada, isTrue);
    });
  });

  test('formatearMontoPago usa dos decimales', () {
    expect(formatearMontoPago(0), 'Bs 0.00');
    expect(formatearMontoPago(599.8), 'Bs 599.80');
  });
}
