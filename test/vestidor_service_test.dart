// Pruebas de VestidorApiService (CU26 - parte Josias).
//
// Usan MockClient y un AuthStorage falso: sin red externa, sin cámara y sin
// MediaPipe. Verifican URL, método, JWT, cuerpos exactos, filtros opcionales,
// parsing y el mapeo de errores (401/403/404/409/422/5xx/timeout).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_session_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_api_service.dart';

const String _base = 'http://test.local';

const Map<String, dynamic> _configJson = <String, dynamic>{
  'producto_id': 1,
  'compatible': true,
  'configuraciones': <dynamic>[
    <String, dynamic>{
      'configuracion_id': 10,
      'recurso_producto_id': 99,
      'asset_url': 'https://cdn.test/polo-negro-tryon.png',
      'color_id': 1,
      'color': 'Negro',
      'zona_cuerpo': 'TORSO',
      'tipo_asset': 'PNG_2D',
      'factor_ancho': '1.45',
      'factor_alto': '1.60',
      'offset_x': '0.00',
      'offset_y': '0.05',
      'rotacion_offset': '0.00',
      'orden_capa': 1,
      'opacidad': '1.00',
    },
  ],
};

const Map<String, dynamic> _sesionJson = <String, dynamic>{
  'sesion_id': 4,
  'cliente_id': 2,
  'estado': 'ACTIVA',
  'fecha_inicio': '2026-09-21T10:00:00+00:00',
  'fecha_fin': null,
};

const Map<String, dynamic> _pruebaJson = <String, dynamic>{
  'prueba_id': 8,
  'sesion_vestidor_ar_id': 4,
  'configuracion_id': 10,
  'variante_producto_id': 11,
  'estado': 'INICIADA',
  'fecha_inicio': '2026-09-21T10:00:00+00:00',
  'fecha_fin': null,
};

class _FakeAuthStorage extends AuthStorage {
  _FakeAuthStorage(this._token);

  final String? _token;

  @override
  Future<String?> readToken() async => _token;
}

VestidorApiService _servicio({
  required http.Client client,
  String? token = 'jwt-test',
  String baseUrl = _base,
}) => VestidorApiService(
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
  test('GET configuraciones usa JWT, filtros y parsea 200', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(
        jsonEncode(_configJson),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final VestidorConfiguracionesResponse respuesta = await _servicio(
      client: client,
    ).obtenerConfiguraciones(productoId: 1, varianteId: 11, colorId: 1);

    expect(capturada.method, 'GET');
    expect(
      capturada.url.toString(),
      '$_base/vestidor-virtual/productos/1/configuraciones'
      '?variante_id=11&color_id=1',
    );
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(respuesta.compatible, isTrue);
    expect(respuesta.configuraciones.single.assetUrl,
        'https://cdn.test/polo-negro-tryon.png');
    expect(respuesta.configuraciones.single.esUsable, isTrue);
  });

  test('GET configuraciones omite filtros vacíos', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_configJson), 200);
    });

    await _servicio(client: client).obtenerConfiguraciones(productoId: 1);

    expect(
      capturada.url.toString(),
      '$_base/vestidor-virtual/productos/1/configuraciones',
    );
  });

  test('crearSesion hace POST y parsea 201', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_sesionJson), 201);
    });

    final VestidorSesion sesion = await _servicio(client: client).crearSesion();

    expect(capturada.method, 'POST');
    expect(capturada.url.toString(), '$_base/vestidor-virtual/sesiones');
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(sesion.sesionId, 4);
    expect(sesion.estaActiva, isTrue);
  });

  test('iniciarPrueba envía configuracion y variante opcional', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_pruebaJson), 201);
    });

    final VestidorPrueba prueba = await _servicio(client: client).iniciarPrueba(
      sesionId: 4,
      configuracionId: 10,
      varianteProductoId: 11,
    );

    expect(capturada.method, 'POST');
    expect(
      capturada.url.toString(),
      '$_base/vestidor-virtual/sesiones/4/pruebas',
    );
    expect(jsonDecode(capturada.body), <String, dynamic>{
      'configuracion_id': 10,
      'variante_producto_id': 11,
    });
    expect(prueba.pruebaId, 8);
    expect(prueba.estaIniciada, isTrue);
  });

  test('iniciarPrueba omite variante cuando no se envía', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_pruebaJson), 201);
    });

    await _servicio(client: client).iniciarPrueba(
      sesionId: 4,
      configuracionId: 10,
    );

    expect(jsonDecode(capturada.body), <String, dynamic>{
      'configuracion_id': 10,
    });
  });

  test('finalizarPrueba hace PATCH con el estado final', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_pruebaJson), 200);
    });

    await _servicio(client: client).finalizarPrueba(
      pruebaId: 8,
      estado: VestidorPruebaEstado.completada,
    );

    expect(capturada.method, 'PATCH');
    expect(
      capturada.url.toString(),
      '$_base/vestidor-virtual/pruebas/8/finalizar',
    );
    expect(jsonDecode(capturada.body), <String, dynamic>{
      'estado': 'COMPLETADA',
    });
  });

  test('finalizarSesion hace PATCH con el estado final', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_sesionJson), 200);
    });

    await _servicio(client: client).finalizarSesion(
      sesionId: 4,
      estado: VestidorSesionEstado.finalizada,
    );

    expect(capturada.method, 'PATCH');
    expect(
      capturada.url.toString(),
      '$_base/vestidor-virtual/sesiones/4/finalizar',
    );
    expect(jsonDecode(capturada.body), <String, dynamic>{
      'estado': 'FINALIZADA',
    });
  });

  test('sin token falla como no autorizado sin llamar al backend', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, token: null).crearSesion(),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.unauthorized,
                'unauthorized', isTrue)
            .having((VestidorApiException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('sin API_BASE_URL falla con la ayuda de configuración', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, baseUrl: '').crearSesion(),
      throwsA(
        isA<VestidorApiException>().having(
          (VestidorApiException e) => e.message,
          'message',
          ApiConfig.missingBaseUrlHint,
        ),
      ),
    );
  });

  test('401 se marca como unauthorized', () async {
    await expectLater(
      _servicio(client: _responde(401, '{}')).crearSesion(),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.unauthorized,
                'unauthorized', isTrue)
            .having((VestidorApiException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('403 expone su código', () async {
    await expectLater(
      _servicio(client: _responde(403, '{}')).crearSesion(),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.statusCode, 'status', 403),
      ),
    );
  });

  test('404 se marca como notFound', () async {
    await expectLater(
      _servicio(client: _responde(404, '{}')).obtenerConfiguraciones(
        productoId: 999,
      ),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.notFound, 'notFound', isTrue)
            .having((VestidorApiException e) => e.statusCode, 'status', 404),
      ),
    );
  });

  test('409 se marca como conflict', () async {
    await expectLater(
      _servicio(client: _responde(409, '{}')).iniciarPrueba(
        sesionId: 4,
        configuracionId: 10,
      ),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.conflict, 'conflict', isTrue)
            .having((VestidorApiException e) => e.statusCode, 'status', 409),
      ),
    );
  });

  test('422 expone su código', () async {
    await expectLater(
      _servicio(client: _responde(422, '{}')).finalizarSesion(
        sesionId: 4,
        estado: 'ACTIVA',
      ),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.statusCode, 'status', 422),
      ),
    );
  });

  test('5xx inesperado se reporta como error', () async {
    await expectLater(
      _servicio(client: _responde(500, '{}')).crearSesion(),
      throwsA(
        isA<VestidorApiException>()
            .having((VestidorApiException e) => e.statusCode, 'status', 500),
      ),
    );
  });

  test('timeout o fallo de red se reporta como conexión', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );

    await expectLater(
      _servicio(client: client).crearSesion(),
      throwsA(
        isA<VestidorApiException>().having(
          (VestidorApiException e) => e.message,
          'message',
          contains('No pudimos conectarnos'),
        ),
      ),
    );
  });

  test('cuerpo inválido se reporta como error inesperado', () async {
    await expectLater(
      _servicio(client: _responde(200, 'no-json')).crearSesion(),
      throwsA(isA<VestidorApiException>()),
    );
  });
}
