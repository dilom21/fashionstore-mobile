import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';
import '../models/auth_models.dart';

/// Error de autenticación con un mensaje apto para mostrar al usuario.
///
/// [unauthorized] indica que el backend rechazó el token (sesión no válida),
/// lo que permite a quien llama decidir si debe eliminar el token guardado.
class AuthException implements Exception {
  const AuthException(this.message, {this.unauthorized = false});

  final String message;
  final bool unauthorized;

  @override
  String toString() => 'AuthException($message)';
}

/// Servicio de autenticación exclusivo para CLIENTES del SaaS multitenant.
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Consume únicamente endpoints de cliente:
///   GET  /auth/tenant/empresas
///   POST /auth/tenant/login
///   POST /auth/tenant/clientes/registro (público, no emite token)
///   GET  /auth/tenant/me
///
/// Nunca usa `POST /auth/personal/login` ni endpoints legacy de clientes.
class AuthService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  AuthService({
    AuthStorage? storage,
    http.Client? client,
    LocalDatabase? database,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _database = database ?? LocalDatabase.instance,
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _credentialsErrorMessage =
      'Correo o contraseña incorrectos.';
  static const String _invalidSessionMessage =
      'No pudimos iniciar sesión. Verifica tus datos.';
  static const String _registroCorreoDuplicadoMessage =
      'Ya existe una cuenta registrada con este correo.';
  static const String _registroDocumentoDuplicadoMessage =
      'Ya existe un cliente registrado con este documento.';
  static const String _registroPasswordsMessage =
      'Las contraseñas no coinciden.';
  static const String _registroDatosMessage =
      'Revisa los datos ingresados e inténtalo nuevamente.';
  static const String _registroServidorMessage =
      'No pudimos crear tu cuenta. Inténtalo nuevamente.';
  static const String _empresaNoDisponibleMessage =
      'La empresa seleccionada ya no está disponible para registro.';
  static const String _empresasConnectionMessage =
      'No pudimos cargar las empresas. Verifica tu conexión e inténtalo nuevamente.';
  static const String _sessionContextMessage =
      'La sesión no corresponde a un cliente de esta empresa.';

  final AuthStorage _storage;
  final http.Client _client;
  final LocalDatabase _database;
  final String _baseUrl;

  /// Obtiene las empresas habilitadas para el selector visual de login.
  ///
  /// Endpoint público: no envía JWT ni datos administrativos.
  Future<List<EmpresaTenant>> listarEmpresas() async {
    _asegurarConfiguracion();

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/auth/tenant/empresas'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } catch (_) {
      throw const AuthException(_empresasConnectionMessage);
    }

    if (response.statusCode == 200) {
      try {
        final Object? decoded = jsonDecode(response.body);
        if (decoded is! List) {
          throw const AuthException(_unexpectedErrorMessage);
        }
        final List<EmpresaTenant> empresas = decoded
            .whereType<Map>()
            .map(
              (Map item) =>
                  EmpresaTenant.fromJson(item.cast<String, dynamic>()),
            )
            .where((EmpresaTenant empresa) => empresa.slug.isNotEmpty)
            .toList();
        return empresas;
      } catch (_) {
        throw const AuthException(_unexpectedErrorMessage);
      }
    }

    if (response.statusCode == 503) {
      throw const AuthException(
        'El selector de empresas aún no está disponible.',
      );
    }
    throw const AuthException(_unexpectedErrorMessage);
  }

  /// Autentica a un CLIENTE y guarda su token JWT si el contexto es `cliente`.
  Future<ClienteLoginResponse> loginCliente({
    required String correo,
    required String password,
    required String empresaSlug,
  }) async {
    _asegurarConfiguracion();

    final String slug = empresaSlug.trim().toLowerCase();
    if (slug.isEmpty) {
      throw const AuthException('Selecciona una empresa para iniciar sesión.');
    }

    final LoginRequest request = LoginRequest(
      correo: correo,
      password: password,
      empresaSlug: slug,
    );

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/auth/tenant/login'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const AuthException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      late final ClienteLoginResponse resultado;
      try {
        resultado = ClienteLoginResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } catch (_) {
        throw const AuthException(_unexpectedErrorMessage);
      }

      // La app móvil es solo para CLIENTES.
      if (resultado.usuario.contexto != 'cliente') {
        await _storage.clearSession();
        throw const AuthException(_sessionContextMessage);
      }

      await _storage.saveToken(resultado.accessToken);
      try {
        final UsuarioAuth me = await obtenerUsuarioActual();
        if (me.contexto != 'cliente' ||
            me.empresaId != resultado.empresaId ||
            me.empresaSlug.trim().toLowerCase() != slug) {
          await _storage.clearSession();
          throw const AuthException(_sessionContextMessage);
        }
        await _storage.saveSession(
          TenantSession(
            empresaId: me.empresaId,
            usuarioId: me.id,
            empresaSlug: me.empresaSlug,
            empresaNombre: me.empresaNombre,
            contexto: me.contexto,
            rol: me.rol,
            correo: me.correo.trim().isEmpty
                ? correo.trim().toLowerCase()
                : me.correo,
            nombre: me.nombre,
            apellido: me.apellido,
            sucursalId: me.sucursalId,
            planCodigo: me.planCodigo,
          ),
        );
      } on AuthException {
        rethrow;
      } catch (_) {
        await _storage.clearSession();
        throw const AuthException(_unexpectedErrorMessage);
      }
      return resultado;
    }

    if (response.statusCode == 401) {
      throw const AuthException(_credentialsErrorMessage);
    }
    if (response.statusCode == 422) {
      throw const AuthException(_invalidSessionMessage);
    }
    if (response.statusCode == 503) {
      throw const AuthException(
        'El servicio de autenticación no está disponible. Inténtalo más tarde.',
      );
    }

    throw const AuthException(_unexpectedErrorMessage);
  }

  /// Registra una cuenta de CLIENTE (`POST /auth/tenant/clientes/registro`).
  ///
  /// Endpoint PÚBLICO: no envía `Authorization` ni requiere sesión. La
  /// respuesta 201 NO incluye `access_token`, por lo que este método **no**
  /// guarda nada en `AuthStorage` ni inicia sesión: el cliente debe iniciar
  /// sesión después con [loginCliente].
  Future<ClienteRegistroResponse> registrarCliente(
    ClienteRegistroRequest request,
  ) async {
    _asegurarConfiguracion();

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/auth/tenant/clientes/registro'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AuthException(_connectionErrorMessage);
    } on http.ClientException {
      throw const AuthException(_connectionErrorMessage);
    } catch (_) {
      throw const AuthException(_connectionErrorMessage);
    }

    if (response.statusCode == 201) {
      try {
        return ClienteRegistroResponse.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } catch (_) {
        throw const AuthException(_unexpectedErrorMessage);
      }
    }

    throw _errorRegistro(response);
  }

  /// Traduce el error del registro SaaS a un mensaje apto para el cliente.
  ///
  /// Contrato real: 400 política de contraseña/confirmación; 404 empresa no
  /// disponible; 409 correo o CI duplicado; 422 datos inválidos; 503 registro
  /// empresarial no disponible.
  AuthException _errorRegistro(http.Response response) {
    final String detail = _leerDetail(response.body);
    final String detalle = detail.toLowerCase();

    switch (response.statusCode) {
      case 400:
        if (detalle.contains('no coinciden')) {
          return const AuthException(_registroPasswordsMessage);
        }
        if (detail.isNotEmpty && detalle.contains('contrase')) {
          return AuthException(detail);
        }
        return const AuthException(_registroDatosMessage);
      case 404:
        return const AuthException(_empresaNoDisponibleMessage);
      case 409:
        if (detalle.contains('documento') || detalle.contains(' ci')) {
          return const AuthException(_registroDocumentoDuplicadoMessage);
        }
        return const AuthException(_registroCorreoDuplicadoMessage);
      case 422:
        if (detalle.contains('no coinciden')) {
          return const AuthException(_registroPasswordsMessage);
        }
        if (detail.isNotEmpty && detalle.contains('contrase')) {
          // Política de contraseña: el texto controlado es del backend.
          return AuthException(detail);
        }
        return const AuthException(_registroDatosMessage);
      case 503:
        return const AuthException(
          'El registro de empresas aún no está disponible. Inténtalo más tarde.',
        );
      default:
        return const AuthException(_registroServidorMessage);
    }
  }

  /// Lee `detail` del JSON de FastAPI de forma defensiva.
  ///
  /// Devuelve cadena vacía si el cuerpo no es JSON o no trae `detail`, para no
  /// exponer nunca JSON crudo, stacktraces ni errores técnicos.
  String _leerDetail(String body) {
    try {
      final Object? data = jsonDecode(body);
      if (data is! Map) return '';
      final Object? detail = data['detail'];
      if (detail is String) return detail.trim();
      if (detail is List && detail.isNotEmpty) {
        final Object? primero = detail.first;
        if (primero is Map && primero['msg'] is String) {
          return (primero['msg'] as String).trim();
        }
      }
    } catch (_) {
      // Cuerpo no JSON: se ignora y se usa el mensaje por defecto.
    }
    return '';
  }

  /// Obtiene el usuario autenticado usando el token guardado.
  Future<UsuarioAuth> obtenerUsuarioActual() async {
    _asegurarConfiguracion();

    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const AuthException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const AuthException(
        'Tu sesión no está activa.',
        unauthorized: true,
      );
    }

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('$_baseUrl/auth/tenant/me'),
            headers: <String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
    } catch (_) {
      throw const AuthException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      late final UsuarioAuth usuario;
      try {
        usuario = UsuarioAuth.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } catch (_) {
        throw const AuthException(_unexpectedErrorMessage);
      }
      return usuario;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthException('Tu sesión expiró.', unauthorized: true);
    }

    throw const AuthException(_unexpectedErrorMessage);
  }

  /// Lee la sesión tenant local (sin validar contra el backend).
  Future<TenantSession?> leerSesion() async {
    try {
      return await _storage.readSession();
    } catch (_) {
      return null;
    }
  }

  /// Intenta restaurar una sesión guardada.
  ///
  /// Devuelve `true` solo si existe un token válido y el contexto es `cliente`.
  /// Si el token fue rechazado por el backend, se elimina localmente.
  Future<bool> restaurarSesion() async {
    if (_baseUrl.isEmpty) return false;

    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      return false;
    }
    if (token == null || token.isEmpty) return false;
    final TenantSession? localSession;
    try {
      localSession = await _storage.readSession();
    } catch (_) {
      return false;
    }
    if (localSession == null ||
        localSession.empresaId <= 0 ||
        localSession.usuarioId <= 0 ||
        localSession.empresaSlug.trim().isEmpty) {
      return false;
    }

    try {
      final UsuarioAuth usuario = await obtenerUsuarioActual();
      if (usuario.contexto != 'cliente') {
        await _storage.clearSession();
        return false;
      }
      if (localSession.usuarioId != usuario.id ||
          localSession.empresaId != usuario.empresaId ||
          localSession.empresaSlug.trim().toLowerCase() !=
              usuario.empresaSlug.trim().toLowerCase()) {
        await _storage.clearSession();
        return false;
      }
      // Se refresca el perfil real (puede haber cambiado nombre/sucursal).
      await _storage.saveSession(
        TenantSession(
          empresaId: usuario.empresaId,
          usuarioId: usuario.id,
          empresaSlug: usuario.empresaSlug,
          empresaNombre: usuario.empresaNombre,
          contexto: usuario.contexto,
          rol: usuario.rol,
          correo: usuario.correo.trim().isEmpty
              ? localSession.correo
              : usuario.correo,
          nombre: usuario.nombre,
          apellido: usuario.apellido,
          sucursalId: usuario.sucursalId,
          planCodigo: usuario.planCodigo,
        ),
      );
      return true;
    } on AuthException catch (error) {
      if (error.unauthorized) {
        await _storage.clearSession();
        return false;
      }
      // Sin conectividad se conserva la sesión tenant local para permitir
      // catálogo cacheado y consulta offline. No se procesa ninguna operación
      // comercial pendiente.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Elimina el token JWT local (cierre de sesión).
  ///
  /// No existe endpoint de logout en el backend: el JWT se descarta en el
  /// dispositivo. Solo se limpia la caché de lectura del scope actual; las
  /// operaciones offline pendientes NO se borran silenciosamente.
  Future<void> cerrarSesion() async {
    TenantSession? session;
    try {
      session = await _storage.readSession();
    } catch (_) {
      session = null;
    }
    await _storage.clearSession();
    if (session == null) return;
    try {
      await _storage.clearPendingCheckout(session.scopeKey);
      await _database.clearCacheScope(session.scopeKey);
    } catch (_) {
      // La sesión ya quedó cerrada; el almacenamiento local es prescindible.
    }
  }

  void _asegurarConfiguracion() {
    if (_baseUrl.isEmpty) {
      throw const AuthException(ApiConfig.missingBaseUrlHint);
    }
  }
}
