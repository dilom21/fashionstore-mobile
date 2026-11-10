import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/ventas/models/comprobante_venta_model.dart';
import 'package:fashionstore_mobile/features/ventas/models/historial_compras_model.dart';
import 'package:fashionstore_mobile/features/ventas/services/comprobante_venta_service.dart';
import 'package:fashionstore_mobile/features/ventas/services/historial_compras_service.dart';

const String _base = 'http://test.local';

class _Storage extends AuthStorage {
  @override
  Future<String?> readToken() async => 'jwt';
}

Map<String, dynamic> _comprobanteJson() => <String, dynamic>{
  'venta_id': 123,
  'fecha_hora': '2026-11-10T10:00:00-04:00',
  'canal': 'MOVIL',
  'estado_venta': 'COMPLETADA',
  'total': '299.80',
  'cliente': <String, dynamic>{
    'id': 9,
    'nombre': 'Ana',
    'apellido': 'Paz',
    'ci': '1234567',
    'telefono': '70000000',
  },
  'empleado': null,
  'sucursal': <String, dynamic>{
    'id': 2,
    'nombre': 'Centro',
    'direccion': 'Av. Principal',
  },
  'pago': <String, dynamic>{
    'pago_id': 5,
    'fecha_hora': '2026-11-10T10:01:00-04:00',
    'monto': '299.80',
    'metodo': 'TARJETA',
    'estado': 'APROBADO',
  },
  'items': <dynamic>[],
  'cantidad_total_unidades': 2,
};

void main() {
  test('el detalle del historial usa la ruta tenant correcta', () async {
    late http.Request captured;
    final http.Client client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'venta_id': 123,
          'fecha_hora': '2026-11-10T10:00:00-04:00',
          'canal': 'MOVIL',
          'estado': 'COMPLETADA',
          'total': '299.80',
          'sucursal': <String, dynamic>{
            'id': 2,
            'nombre': 'Centro',
            'direccion': 'Av. Principal',
          },
          'pago': null,
          'items': <dynamic>[],
          'cantidad_total_unidades': 2,
        }),
        200,
      );
    });

    final HistorialCompraDetalle detalle = await HistorialComprasService(
      client: client,
      storage: _Storage(),
      baseUrl: _base,
    ).obtenerDetalle(123);

    expect(captured.url.path, '/tenant/ventas/historial/123');
    expect(detalle.ventaId, 123);
    expect(
      ApiConfig.historialCompraDetalleUrlDesde(_base, 123),
      '$_base/tenant/ventas/historial/123',
    );
  });

  test(
    'el comprobante del cliente usa la ruta colgada del historial',
    () async {
      late http.Request captured;
      final http.Client client = MockClient((http.Request request) async {
        captured = request;
        return http.Response(jsonEncode(_comprobanteJson()), 200);
      });

      final ComprobanteVenta comprobante = await ComprobanteVentaService(
        client: client,
        storage: _Storage(),
        baseUrl: _base,
      ).obtenerComprobante(123);

      expect(captured.url.path, '/tenant/ventas/historial/123/comprobante');
      expect(
        ApiConfig.comprobanteVentaUrlDesde(_base, 123),
        '$_base/tenant/ventas/historial/123/comprobante',
      );
      expect(comprobante.pago.estado, 'APROBADO');
      expect(comprobante.cliente?.nombreCompleto, 'Ana Paz');
    },
  );
}
