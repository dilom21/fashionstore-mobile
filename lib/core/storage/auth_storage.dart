import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'tenant_session.dart';

/// Almacenamiento seguro del token JWT del CLIENTE autenticado.
///
/// Usa `flutter_secure_storage` (Keystore en Android, Keychain en iOS).
/// Guarda únicamente el `access_token`: nunca credenciales (correo+contraseña)
/// ni hashes.
class AuthStorage {
  /// Crea el almacenamiento. Permite inyectar una instancia para pruebas.
  AuthStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Clave bajo la que se guarda el token de acceso.
  static const String tokenKey = 'vanter_access_token';
  static const String sessionKey = 'vanter_tenant_session';

  final FlutterSecureStorage _storage;

  /// Guarda el token JWT de la sesión del cliente.
  Future<void> saveToken(String token) =>
      _storage.write(key: tokenKey, value: token);

  /// Lee el token JWT guardado. Devuelve `null` si no hay sesión activa.
  Future<String?> readToken() => _storage.read(key: tokenKey);

  /// Elimina el token JWT guardado (cierre de sesión).
  Future<void> deleteToken() => _storage.delete(key: tokenKey);

  Future<void> saveSession(TenantSession session) => _storage.write(
    key: sessionKey,
    value: jsonEncode(session.toJson()),
  );

  Future<TenantSession?> readSession() async {
    final String? raw = await _storage.read(key: sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TenantSession.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: sessionKey);
  }
}
