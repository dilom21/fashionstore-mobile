import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  final FlutterSecureStorage _storage;

  /// Guarda el token JWT de la sesión del cliente.
  Future<void> saveToken(String token) =>
      _storage.write(key: tokenKey, value: token);

  /// Lee el token JWT guardado. Devuelve `null` si no hay sesión activa.
  Future<String?> readToken() => _storage.read(key: tokenKey);

  /// Elimina el token JWT guardado (cierre de sesión).
  Future<void> deleteToken() => _storage.delete(key: tokenKey);
}
