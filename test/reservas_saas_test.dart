import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/reservas/models/reserva_model.dart';
import 'package:fashionstore_mobile/features/reservas/services/reserva_service.dart';

class _Storage extends AuthStorage {
  _Storage(this.token);

  final String? token;

  @override
  Future<String?> readToken() async => token;
}

Map<String, dynamic> _detail() => <String, dynamic>{
  'reserva_id': 77,
  'carrito_id': 45,
  'sucursal_id': 2,
  'sucursal_nombre': 'Centro',
  'fecha_reserva': '2026-11-10T09:00:00-04:00',
  'fecha_atencion': '2026-11-12T10:30:00-04:00',
  'estado': 'PENDIENTE',
  'observacion': 'Llegaré temprano',
  'cantidad_lineas': 1,
  'cantidad_unidades': 2,
  'items': <dynamic>[
    <String, dynamic>{
      'detalle_id': 1,
      'inventario_id': 44,
      'producto_id': 9,
      'producto_nombre': 'Camisa',
      'imagen_principal_url': null,
      'variante_producto_id': 7,
      'sku': 'SKU-1',
      'talla_id': 1,
      'talla_nombre': 'M',
      'color_id': 3,
      'color_nombre': 'Negro',
      'temporada_id': 2,
      'temporada_nombre': 'Verano',
      'cantidad': 2,
    },
  ],
};

void main() {
  test('crea reserva online con fecha aware y devuelve el id real', () async {
    late http.Request post;
    final http.Client client = MockClient((http.Request request) async {
      if (request.method == 'POST') {
        post = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'reserva_id': 77,
            'carrito_id': 45,
            'estado': 'PENDIENTE',
          }),
          201,
        );
      }
      return http.Response(jsonEncode(_detail()), 200);
    });

    final ReservaCreada creada =
        await ReservaService(
          client: client,
          storage: _Storage('jwt'),
          baseUrl: 'http://test.local',
        ).crearReserva(
          carritoId: 45,
          fechaAtencion: DateTime(2026, 11, 12, 10, 30),
          observacion: 'Llegaré temprano',
        );

    expect(creada.reservaId, 77);
    expect(post.url.path, '/tenant/reservas');
    expect(post.headers['Authorization'], 'Bearer jwt');
    final Map<String, dynamic> body =
        jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['carrito_id'], 45);
    expect(
      RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(body['fecha_atencion']),
      isTrue,
      reason: 'fecha_atencion debe incluir zona horaria',
    );
  });

  test('lista reservas con paginación del contrato SaaS', () async {
    final http.Client client = MockClient((http.Request request) async {
      expect(request.url.path, '/tenant/reservas');
      expect(request.url.queryParameters['limit'], '20');
      expect(request.url.queryParameters['offset'], '0');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{..._detail(), 'items': null},
          ],
          'total': 31,
          'limit': 20,
          'offset': 0,
        }),
        200,
      );
    });

    final ReservaListaResponse lista = await ReservaService(
      client: client,
      storage: _Storage('jwt'),
      baseUrl: 'http://test.local',
    ).listarReservas();

    expect(lista.items.single.reservaId, 77);
    expect(lista.totalReservas, 31);
  });

  test('obtiene detalle real y cancelación según contrato', () async {
    final List<String> paths = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      paths.add('${request.method} ${request.url.path}');
      if (request.method == 'PATCH') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'reserva_id': 77,
            'estado': 'CANCELADA',
          }),
          200,
        );
      }
      return http.Response(jsonEncode(_detail()), 200);
    });
    final ReservaService service = ReservaService(
      client: client,
      storage: _Storage('jwt'),
      baseUrl: 'http://test.local',
    );

    final ReservaDetalle detalle = await service.obtenerReserva(77);
    final ReservaEstado estado = await service.cancelarReserva(
      reservaId: 77,
      observacion: 'Ya no puedo asistir',
    );

    expect(detalle.items.single.productoNombre, 'Camisa');
    expect(detalle.cantidadTotalUnidades, 2);
    expect(estado.estado, 'CANCELADA');
    expect(paths, contains('GET /tenant/reservas/77'));
    expect(paths, contains('PATCH /tenant/reservas/77/cancelar'));
  });

  test('error de red no simula una reserva confirmada', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );

    await expectLater(
      ReservaService(client: client, storage: _Storage('jwt')).crearReserva(
        carritoId: 45,
        fechaAtencion: DateTime(2026, 11, 12, 10, 30),
      ),
      throwsA(
        isA<ReservaException>().having(
          (ReservaException e) => e.message,
          'message',
          isNot(contains('sincronizará')),
        ),
      ),
    );
  });
}
