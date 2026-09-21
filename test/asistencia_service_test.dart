// Pruebas de AsistenciaService.
//
// Usan MockClient y un AuthStorage falso: no hay red externa ni API keys.
// Verifican URL, método, JWT, body exacto, filtros opcionales, parsing y el
// mapeo de errores (401/403/422/502/503/504/5xx).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/asistencia_inteligente/models/asistencia_models.dart';
import 'package:fashionstore_mobile/features/asistencia_inteligente/services/asistencia_service.dart';

const String _base = 'http://test.local';

const Map<String, dynamic> _respuestaJson = <String, dynamic>{
  'titulo': 'Look casual premium para oficina',
  'descripcion': 'Elegimos prendas versátiles.',
  'recomendaciones': <dynamic>[
    <String, dynamic>{
      'producto_id': 1,
      'nombre': 'Polo Premium Piqué',
      'precio': '149.90',
      'imagen_url': 'https://cdn.test/model.webp',
      'categoria': 'Polos',
      'variante_id': 10,
      'talla': 'M',
      'color': 'Negro',
      'inventario_id': 23,
      'sucursal_id': 1,
      'sucursal': 'Sucursal Centro',
      'temporada': 'Primavera-Verano 2026',
      'stock_disponible': 10,
      'motivo': 'Versátil',
      'requiere_seleccion': false,
    },
  ],
};

class _FakeAuthStorage extends AuthStorage {
  _FakeAuthStorage(this._token);

  final String? _token;

  @override
  Future<String?> readToken() async => _token;
}

AsistenciaService _servicio({
  required http.Client client,
  String? token = 'jwt-test',
  String baseUrl = _base,
}) => AsistenciaService(
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
  test('ApiConfig centraliza la ruta /asistencia-inteligente/recomendaciones',
      () {
    expect(
      ApiConfig.asistenciaRecomendacionesUrlDesde('http://api.test'),
      'http://api.test/asistencia-inteligente/recomendaciones',
    );
  });

  test('realiza POST con JWT, body mínimo y parsea 200', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(
        jsonEncode(_respuestaJson),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final RecomendacionesResponse respuesta = await _servicio(client: client)
        .recomendar(consulta: '  look casual  ');

    expect(capturada.method, 'POST');
    expect(
      capturada.url.toString(),
      '$_base/asistencia-inteligente/recomendaciones',
    );
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(capturada.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(capturada.body), <String, dynamic>{
      'consulta': 'look casual',
      'limite': 4,
    });
    expect(respuesta.titulo, 'Look casual premium para oficina');
    expect(respuesta.recomendaciones.single.inventarioId, 23);
    expect(respuesta.recomendaciones.single.puedeAgregarDirecto, isTrue);
  });

  test('incluye filtros opcionales solo cuando están presentes', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_respuestaJson), 200);
    });

    await _servicio(client: client).recomendar(
      consulta: 'oficina',
      talla: 'M',
      color: 'Negro',
      presupuestoMax: 400,
      sucursalId: 1,
      limite: 2,
    );

    expect(jsonDecode(capturada.body), <String, dynamic>{
      'consulta': 'oficina',
      'limite': 2,
      'talla': 'M',
      'color': 'Negro',
      'presupuesto_max': 400,
      'sucursal_id': 1,
    });
  });

  test('omite filtros vacíos o inválidos', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(jsonEncode(_respuestaJson), 200);
    });

    await _servicio(client: client).recomendar(
      consulta: 'oficina',
      talla: '   ',
      color: '',
      presupuestoMax: 0,
      sucursalId: 0,
    );

    expect(jsonDecode(capturada.body), <String, dynamic>{
      'consulta': 'oficina',
      'limite': 4,
    });
  });

  test('sin token falla como no autorizado sin llamar al backend', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, token: null).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having(
              (AsistenciaException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having((AsistenciaException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('sin API_BASE_URL falla con la ayuda de configuración', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, baseUrl: '').recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>().having(
          (AsistenciaException e) => e.message,
          'message',
          ApiConfig.missingBaseUrlHint,
        ),
      ),
    );
  });

  test('401 se marca como unauthorized', () async {
    await expectLater(
      _servicio(client: _responde(401, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having(
              (AsistenciaException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having((AsistenciaException e) => e.statusCode, 'status', 401),
      ),
    );
  });

  test('403 y 422 exponen su código', () async {
    await expectLater(
      _servicio(client: _responde(403, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having((AsistenciaException e) => e.statusCode, 'status', 403),
      ),
    );
    await expectLater(
      _servicio(client: _responde(422, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having((AsistenciaException e) => e.statusCode, 'status', 422),
      ),
    );
  });

  test('503 marca noConfigurada', () async {
    await expectLater(
      _servicio(client: _responde(503, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having(
              (AsistenciaException e) => e.noConfigurada,
              'noConfigurada',
              isTrue,
            )
            .having((AsistenciaException e) => e.statusCode, 'status', 503),
      ),
    );
  });

  test('504 y 502 usan mensajes de negocio', () async {
    await expectLater(
      _servicio(client: _responde(504, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>().having(
          (AsistenciaException e) => e.message,
          'message',
          contains('tardó demasiado'),
        ),
      ),
    );
    await expectLater(
      _servicio(client: _responde(502, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>().having(
          (AsistenciaException e) => e.message,
          'message',
          contains('No pudimos generar recomendaciones'),
        ),
      ),
    );
  });

  test('5xx inesperado se reporta como error', () async {
    await expectLater(
      _servicio(client: _responde(500, '{}')).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>()
            .having((AsistenciaException e) => e.statusCode, 'status', 500),
      ),
    );
  });

  test('timeout o fallo de red se reporta como conexión', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );

    await expectLater(
      _servicio(client: client).recomendar(consulta: 'look'),
      throwsA(
        isA<AsistenciaException>().having(
          (AsistenciaException e) => e.message,
          'message',
          contains('No pudimos conectarnos'),
        ),
      ),
    );
  });

  test('cuerpo inválido se reporta como error inesperado', () async {
    await expectLater(
      _servicio(client: _responde(200, 'no-json')).recomendar(consulta: 'x'),
      throwsA(isA<AsistenciaException>()),
    );
  });
}
