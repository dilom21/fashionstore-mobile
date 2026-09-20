import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
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

/// Servicio de autenticación exclusivo para CLIENTES de VANTER MEN.
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Consume únicamente endpoints de cliente:
///   POST /auth/clientes/login
///   GET  /auth/me
///
/// Nunca usa `POST /auth/personal/login` (personal interno del sistema web).
class AuthService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  AuthService({AuthStorage? storage, http.Client? client})
    : _storage = storage ?? AuthStorage(),
      _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _credentialsErrorMessage =
      'Correo o contraseña incorrectos.';
  static const String _invalidSessionMessage =
      'No pudimos iniciar sesión. Verifica tus datos.';

  final AuthStorage _storage;
  final http.Client _client;

  /// Autentica a un CLIENTE y guarda su token JWT si el contexto es `cliente`.
  Future<ClienteLoginResponse> loginCliente({
    required String correo,
    required String password,
  }) async {
    _asegurarConfiguracion();

    final LoginRequest request = LoginRequest(
      correo: correo,
      password: password,
    );

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(ApiConfig.clientesLoginUrl),
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
        await _storage.deleteToken();
        throw const AuthException(_invalidSessionMessage);
      }

      await _storage.saveToken(resultado.accessToken);
      return resultado;
    }

    if (response.statusCode == 401) {
      throw const AuthException(_credentialsErrorMessage);
    }

    throw const AuthException(_unexpectedErrorMessage);
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
            Uri.parse(ApiConfig.authMeUrl),
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

  /// Intenta restaurar una sesión guardada.
  ///
  /// Devuelve `true` solo si existe un token válido y el contexto es `cliente`.
  /// Si el token fue rechazado por el backend, se elimina localmente.
  Future<bool> restaurarSesion() async {
    if (!ApiConfig.isConfigured) return false;

    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      return false;
    }
    if (token == null || token.isEmpty) return false;

    try {
      final UsuarioAuth usuario = await obtenerUsuarioActual();
      if (usuario.contexto != 'cliente') {
        await _storage.deleteToken();
        return false;
      }
      return true;
    } on AuthException catch (error) {
      if (error.unauthorized) {
        await _storage.deleteToken();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Elimina el token JWT local (cierre de sesión).
  ///
  /// No existe endpoint de logout en el backend: el JWT se descarta en el
  /// dispositivo.
  Future<void> cerrarSesion() => _storage.deleteToken();

  void _asegurarConfiguracion() {
    if (!ApiConfig.isConfigured) {
      throw const AuthException(ApiConfig.missingBaseUrlHint);
    }
  }
}
