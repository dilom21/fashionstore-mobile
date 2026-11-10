import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/core/storage/tenant_session.dart';
import 'package:fashionstore_mobile/features/autenticacion_seguridad/models/auth_models.dart';
import 'package:fashionstore_mobile/features/autenticacion_seguridad/services/auth_service.dart';

const String _base = 'http://test.local';

class _MemoryStorage extends AuthStorage {
  _MemoryStorage({this.token, this.session});

  String? token;
  TenantSession? session;
  int cleared = 0;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> deleteToken() async => token = null;

  @override
  Future<TenantSession?> readSession() async => session;

  @override
  Future<void> saveSession(TenantSession value) async => session = value;

  @override
  Future<void> clearSession() async {
    cleared++;
    token = null;
    session = null;
  }
}

Map<String, dynamic> _me({
  String slug = 'acme',
  int empresaId = 2,
  int usuarioId = 7,
}) => <String, dynamic>{
  'usuario_id': usuarioId,
  'empresa_id': empresaId,
  'empresa_slug': slug,
  'empresa_nombre': 'Acme',
  'rol': 'CLIENTE',
  'contexto': 'cliente',
  'plan_codigo': 'BASICO',
  'permite_reportes_ia': false,
  'correo': 'ana@acme.com',
  'nombre': 'Ana',
  'apellido': 'Paz',
};

AuthService _service(http.Client client, _MemoryStorage storage) =>
    AuthService(client: client, storage: storage, baseUrl: _base);

void main() {
  test('lista empresas habilitadas desde el endpoint público tenant', () async {
    late http.Request captured;
    final http.Client client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<dynamic>[
          <String, dynamic>{'slug': 'acme', 'nombre_comercial': 'Acme'},
          <String, dynamic>{'slug': 'beta', 'nombre_comercial': 'Beta'},
        ]),
        200,
      );
    });

    final List<EmpresaTenant> empresas = await _service(
      client,
      _MemoryStorage(),
    ).listarEmpresas();

    expect(captured.method, 'GET');
    expect(captured.url.path, '/auth/tenant/empresas');
    expect(empresas.map((EmpresaTenant e) => e.slug), ['acme', 'beta']);
    expect(empresas.first.etiqueta, 'Acme');
  });

  test(
    'login envía empresa_slug/contexto y confirma /me antes de guardar',
    () async {
      late http.Request loginRequest;
      final _MemoryStorage storage = _MemoryStorage();
      final http.Client client = MockClient((http.Request request) async {
        if (request.url.path.endsWith('/login')) {
          loginRequest = request;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'jwt-tenant',
              'token_type': 'bearer',
              'empresa_id': 2,
              'empresa_slug': 'acme',
              'empresa_nombre': 'Acme',
              'rol': 'CLIENTE',
              'contexto': 'cliente',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/me')) {
          expect(request.headers['Authorization'], 'Bearer jwt-tenant');
          return http.Response(jsonEncode(_me()), 200);
        }
        return http.Response('{}', 404);
      });

      final ClienteLoginResponse result = await _service(client, storage)
          .loginCliente(
            correo: 'ana@acme.com',
            password: 'Secreta123!',
            empresaSlug: 'ACME',
          );

      expect(result.accessToken, 'jwt-tenant');
      expect(jsonDecode(loginRequest.body), <String, dynamic>{
        'correo': 'ana@acme.com',
        'password': 'Secreta123!',
        'empresa_slug': 'acme',
        'contexto': 'cliente',
      });
      expect(storage.token, 'jwt-tenant');
      expect(storage.session?.empresaSlug, 'acme');
      expect(storage.session?.nombreCompleto, 'Ana Paz');
      expect(storage.session?.scopeKey, '2:7');
    },
  );

  test('login 401 reporta credenciales sin guardar token', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final http.Client client = MockClient(
      (http.Request request) async => http.Response('{}', 401),
    );

    await expectLater(
      _service(client, storage).loginCliente(
        correo: 'ana@acme.com',
        password: 'mala',
        empresaSlug: 'acme',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(storage.token, isNull);
  });

  test('login rechaza una empresa distinta a la confirmada por /me', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final http.Client client = MockClient((http.Request request) async {
      if (request.url.path.endsWith('/login')) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'access_token': 'jwt',
            'empresa_id': 2,
            'empresa_slug': 'acme',
            'empresa_nombre': 'Acme',
            'rol': 'CLIENTE',
            'contexto': 'cliente',
          }),
          200,
        );
      }
      return http.Response(jsonEncode(_me(slug: 'otra')), 200);
    });

    await expectLater(
      _service(client, storage).loginCliente(
        correo: 'ana@acme.com',
        password: 'Secreta123!',
        empresaSlug: 'acme',
      ),
      throwsA(isA<AuthException>()),
    );
    expect(storage.token, isNull);
    expect(storage.cleared, greaterThan(0));
  });

  test('registro SaaS envía empresa_slug al endpoint tenant', () async {
    late http.Request captured;
    final http.Client client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'mensaje': 'Cuenta creada',
          'usuario_id': 7,
          'cliente_id': 9,
          'empresa_slug': 'acme',
          'correo': 'ana@acme.com',
          'nombre': 'Ana',
          'apellido': 'Paz',
        }),
        201,
      );
    });

    final ClienteRegistroResponse response =
        await _service(client, _MemoryStorage()).registrarCliente(
          ClienteRegistroRequest(
            empresaSlug: 'acme',
            correo: 'ana@acme.com',
            password: 'Secreta123!',
            passwordConfirmacion: 'Secreta123!',
            nombre: 'Ana',
            apellido: 'Paz',
            ci: '1234567',
            telefono: '70000000',
            sexo: SexoCliente.femenino,
            fechaNacimiento: DateTime(1995, 5, 4),
          ),
        );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/auth/tenant/clientes/registro');
    final Map<String, dynamic> body =
        jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['empresa_slug'], 'acme');
    expect(body.containsKey('rol'), isFalse);
    expect(response.correo, 'ana@acme.com');
  });

  test('restaura sesión vigente y limpia token expirado', () async {
    final TenantSession session = const TenantSession(
      empresaId: 2,
      usuarioId: 7,
      empresaSlug: 'acme',
      empresaNombre: 'Acme',
    );
    final _MemoryStorage vigente = _MemoryStorage(
      token: 'jwt',
      session: session,
    );
    final http.Client ok = MockClient(
      (http.Request request) async => http.Response(jsonEncode(_me()), 200),
    );
    expect(await _service(ok, vigente).restaurarSesion(), isTrue);

    final _MemoryStorage expirado = _MemoryStorage(
      token: 'jwt',
      session: session,
    );
    final http.Client expired = MockClient(
      (http.Request request) async => http.Response('{}', 401),
    );
    expect(await _service(expired, expirado).restaurarSesion(), isFalse);
    expect(expirado.token, isNull);
  });
}
