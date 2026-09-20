// Pruebas de PagoElectronicoService (CU22).
//
// Usan MockClient y un AuthStorage falso: no hay red externa ni plugin nativo.
// Verifican URL, método, JWT, body exacto (solo venta_id), parsing y el mapeo
// de errores HTTP del backend Stripe.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/features/ventas/models/pago_electronico_model.dart';
import 'package:fashionstore_mobile/features/ventas/services/pago_electronico_service.dart';

const String _base = 'http://test.local';

const Map<String, dynamic> _intencionJson = <String, dynamic>{
  'venta_id': 123,
  'pago_id': 77,
  'payment_intent_id': 'pi_123',
  'client_secret': 'pi_123_secret_abc',
  'monto': '599.80',
  'moneda': 'bob',
  'estado_pago': 'PENDIENTE',
};

const Map<String, dynamic> _estadoJson = <String, dynamic>{
  'venta_id': 123,
  'estado_venta': 'COMPLETADA',
  'pago_id': 77,
  'estado_pago': 'APROBADO',
  'payment_intent_id': 'pi_123',
};

class _FakeAuthStorage extends AuthStorage {
  _FakeAuthStorage(this._token);

  final String? _token;

  @override
  Future<String?> readToken() async => _token;
}

PagoElectronicoService _servicio({
  required http.Client client,
  String? token = 'jwt-test',
  String baseUrl = _base,
}) => PagoElectronicoService(
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
  test('ApiConfig centraliza las rutas de CU22', () {
    expect(
      ApiConfig.stripeIntencionUrlDesde('http://api.test'),
      'http://api.test/pagos/stripe/intencion',
    );
    expect(
      ApiConfig.stripeEstadoVentaUrlDesde('http://api.test', 123),
      'http://api.test/pagos/stripe/ventas/123/estado',
    );
  });

  test('crearIntencion hace POST con JWT, body exacto y parsea 201', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(
        jsonEncode(_intencionJson),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final IntencionPago intencion = await _servicio(client: client)
        .crearIntencion(123);

    expect(capturada.method, 'POST');
    expect(capturada.url.toString(), '$_base/pagos/stripe/intencion');
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(capturada.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(capturada.body), <String, dynamic>{'venta_id': 123});
    expect(intencion.ventaId, 123);
    expect(intencion.tieneClientSecret, isTrue);
    expect(intencion.monto, 599.80);
  });

  test('consultarEstado hace GET con JWT y parsea 200', () async {
    late http.Request capturada;
    final http.Client client = MockClient((http.Request request) async {
      capturada = request;
      return http.Response(
        jsonEncode(_estadoJson),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final EstadoPagoVenta estado = await _servicio(client: client)
        .consultarEstado(123);

    expect(capturada.method, 'GET');
    expect(capturada.url.toString(), '$_base/pagos/stripe/ventas/123/estado');
    expect(capturada.headers['Authorization'], 'Bearer jwt-test');
    expect(estado.pagoAprobado, isTrue);
    expect(estado.compraCompletada, isTrue);
  });

  test('sin token falla como no autorizado sin llamar al backend', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, token: null).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>()
            .having(
              (PagoElectronicoException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having(
              (PagoElectronicoException e) => e.statusCode,
              'status',
              401,
            ),
      ),
    );
  });

  test('sin API_BASE_URL falla con la ayuda de configuración', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw StateError('no debe llamarse'),
    );

    await expectLater(
      _servicio(client: client, baseUrl: '').crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.message,
          'message',
          ApiConfig.missingBaseUrlHint,
        ),
      ),
    );
  });

  test('401 se marca como unauthorized', () async {
    await expectLater(
      _servicio(
        client: _responde(401, <String, dynamic>{'detail': 'No autenticado'}),
      ).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>()
            .having(
              (PagoElectronicoException e) => e.unauthorized,
              'unauthorized',
              isTrue,
            )
            .having(
              (PagoElectronicoException e) => e.statusCode,
              'status',
              401,
            ),
      ),
    );
  });

  test('403 venta ajena y 404 venta no encontrada', () async {
    await expectLater(
      _servicio(client: _responde(403, '{}')).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.statusCode,
          'status',
          403,
        ),
      ),
    );

    await expectLater(
      _servicio(client: _responde(404, '{}')).consultarEstado(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.statusCode,
          'status',
          404,
        ),
      ),
    );
  });

  test('409 venta no pagable se marca como conflicto', () async {
    await expectLater(
      _servicio(
        client: _responde(409, <String, dynamic>{
          'detail': 'La venta ya tiene un pago aprobado',
        }),
      ).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>()
            .having(
              (PagoElectronicoException e) => e.conflicto,
              'conflicto',
              isTrue,
            )
            .having((PagoElectronicoException e) => e.statusCode, 'status', 409)
            .having(
              (PagoElectronicoException e) => e.message,
              'message',
              'La venta ya tiene un pago aprobado',
            ),
      ),
    );
  });

  test('409 no filtra SQL ni errores técnicos', () async {
    try {
      await _servicio(
        client: _responde(409, <String, dynamic>{
          'detail': 'select * from pago where venta_id = 123',
        }),
      ).crearIntencion(123);
      fail('debió lanzar PagoElectronicoException');
    } on PagoElectronicoException catch (error) {
      expect(error.message.toLowerCase(), isNot(contains('select')));
      expect(error.message.toLowerCase(), isNot(contains('sql')));
    }
  });

  test('422 se reporta como datos inválidos', () async {
    await expectLater(
      _servicio(client: _responde(422, '{}')).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.statusCode,
          'status',
          422,
        ),
      ),
    );
  });

  test('500 configuración Stripe y 502 pasarela no disponible', () async {
    await expectLater(
      _servicio(client: _responde(500, '{}')).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.message,
          'message',
          contains('Stripe no está configurado'),
        ),
      ),
    );

    await expectLater(
      _servicio(client: _responde(502, '{}')).crearIntencion(123),
      throwsA(
        isA<PagoElectronicoException>().having(
          (PagoElectronicoException e) => e.message,
          'message',
          contains('pasarela'),
        ),
      ),
    );
  });

  test('timeout o fallo de red se reporta como conexión', () async {
    final http.Client client = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );

    await expectLater(
      _servicio(client: client).consultarEstado(123),
      throwsA(
        isA<PagoElectronicoException>()
            .having(
              (PagoElectronicoException e) => e.statusCode,
              'status',
              isNull,
            )
            .having(
              (PagoElectronicoException e) => e.message,
              'message',
              contains('No pudimos conectarnos'),
            ),
      ),
    );
  });
}
