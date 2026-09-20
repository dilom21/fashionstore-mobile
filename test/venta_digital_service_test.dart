// Pruebas de VentaDigitalService (CU19).
//
// Usan MockClient y un AuthStorage falso: no hay red externa. Verifican URL,
// método, JWT, body exacto (canal MOVIL), parsing 201 y el mapeo de errores.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/ventas/models/venta_digital_model.dart';
import 'package:fashionstore_mobile/features/ventas/services/venta_digital_service.dart';

const String _base = 'http://test.local';

const Map<String, dynamic> _ventaJson = <String, dynamic>{
  'venta_id': 123,
  'carrito_id': 45,
  'cliente_id': 4,
  'sucursal_id': 2,
  'sucursal_nombre': 'Centro',
  'canal': 'MOVIL',
  'estado': 'PENDIENTE',
  'fecha_hora': '2026-09-25T10:00:00',
  'total': '599.80',
  'cantidad_total_unidades': 3,
  'items': <dynamic>[
    <String, dynamic>{
      'detalle_id': 1,
      'inventario_id': 44,
      'producto_id': 9,
      'producto_nombre': 'Camisa',
      'imagen_principal': null,
      'variante_producto_id': 7,
      'sku': 'SKU-1',
      'talla_id': 1,
      'talla_nombre': 'M',
      'color_id': 3,
      'color_nombre': 'Negro',
      'temporada_id': 2,
      'temporada_nombre': 'Verano',
      'cantidad': 2,
      'precio_unitario': '149.90',
      'subtotal_linea': '299.80',
    },
  ],
};

class _FakeAuthStorage extends AuthStorage {
  _FakeAuthStorage(this._token);

  final String? _token;

  @override
  Future<String?> readToken() async => _token;
}

VentaDigitalService _servicio({
  required http.Client client,
  String? token = 'jwt-test',
  String baseUrl = _base,
}) => VentaDigitalService(
  storage: _FakeAuthStorage(token),
  client: client,
  baseUrl: baseUrl,
);

http.Client _responde(int status, Object body) => MockClient(
  (http.Request request) async => http.Response(
    body is String ? body : jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  ),
);

void main() {
  test('ApiConfig centraliza la ruta /ventas/digital', () {
    expect(
      ApiConfig.ventasDigitalUrlDesde('http://api.test'),
      'http://api.test/ventas/digital',
    );
  });

  test('realiza POST con JWT, body exacto y canal MOVIL; parsea 201', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(
        jsonEncode(_ventaJson),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final VentaDigital venta = await _servicio(client: client)
        .realizarCompra(45);

    expect(capturada.method, 'POST');
    expect(capturada.url.toString(), '$_base/ventas/digital');
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(capturada.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(capturada.body), <String, dynamic>{
      'carrito_id': 45,
      'canal': 'MOVIL',
    });
    expect(venta.ventaId, 123);
    expect(venta.estaPendiente, isTrue);
    expect(venta.total, 599.80);
  });

  test('sin token falla como no autorizado sin llamar al backend', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, token: null).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>()
            .having(
              (VentaDigitalException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having((VentaDigitalException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('sin API_BASE_URL falla con la ayuda de configuración', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, baseUrl: '').realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>().having(
          (VentaDigitalException e) => e.message,
          'message',
          ApiConfig.missingBaseUrlHint,
        ),
      ),
    );
  });

  test('401 se marca como unauthorized', () async {
    final http.Client client = _responde(401, <String, dynamic>{
      'detail': 'No autenticado',
    });

    await expectLater(
      _servicio(client: client).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>()
            .having(
              (VentaDigitalException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having((VentaDigitalException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('403 y 404 exponen mensajes de negocio', () async {
    await expectLater(
      _servicio(client: _responde(403, '{}')).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>().having(
          (VentaDigitalException e) => e.statusCode,
          'status',
          403,
        ),
      ),
    );

    await expectLater(
      _servicio(client: _responde(404, '{}')).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>().having(
          (VentaDigitalException e) => e.statusCode,
          'status',
          404,
        ),
      ),
    );
  });

  group('409 clasifica el conflicto', () {
    Future<String> mensajeDe(String detail) async {
      try {
        await _servicio(
          client: _responde(409, <String, dynamic>{'detail': detail}),
        ).realizarCompra(45);
        fail('debió lanzar VentaDigitalException');
      } on VentaDigitalException catch (error) {
        expect(error.conflicto, isTrue);
        expect(error.statusCode, 409);
        return error.message;
      }
    }

    test('stock insuficiente', () async {
      expect(
        await mensajeDe('Stock insuficiente para completar la compra'),
        contains('stock'),
      );
    });

    test('carrito ya convertido', () async {
      expect(
        await mensajeDe('El carrito ya fue convertido en una venta'),
        contains('convertido'),
      );
    });

    test('carrito no activo', () async {
      expect(
        await mensajeDe('El carrito no esta activo para comprar'),
        contains('activo'),
      );
    });

    test('carrito vacío', () async {
      expect(
        await mensajeDe('El carrito no contiene prendas para comprar'),
        contains('prendas'),
      );
    });

    test('no filtra SQL ni errores técnicos', () async {
      final String mensaje = await mensajeDe(
        'select * from venta where carrito_id = 45',
      );
      expect(mensaje.toLowerCase(), isNot(contains('select')));
      expect(mensaje.toLowerCase(), isNot(contains('sql')));
    });
  });

  test('422 se reporta como datos inválidos', () async {
    await expectLater(
      _servicio(client: _responde(422, '{}')).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>().having(
          (VentaDigitalException e) => e.statusCode,
          'status',
          422,
        ),
      ),
    );
  });

  test('5xx se reporta como error inesperado', () async {
    await expectLater(
      _servicio(client: _responde(500, '{}')).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>().having(
          (VentaDigitalException e) => e.statusCode,
          'status',
          500,
        ),
      ),
    );
  });

  test('timeout o fallo de red se reporta como conexión', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );

    await expectLater(
      _servicio(client: client).realizarCompra(45),
      throwsA(
        isA<VentaDigitalException>()
            .having((VentaDigitalException e) => e.statusCode, 'status', isNull)
            .having(
              (VentaDigitalException e) => e.message,
              'message',
              contains('No pudimos conectarnos'),
            ),
      ),
    );
  });
}
