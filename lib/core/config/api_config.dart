/// Configuración central de acceso al backend FastAPI de VANTER MEN.
///
/// Toda dirección o ruta del backend se declara aquí y se consume desde este
/// punto. No se hardcodean URLs en páginas, widgets ni servicios.
///
/// La URL base se inyecta en tiempo de compilación, por ejemplo:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class ApiConfig {
  /// Clase de solo constantes: no debe instanciarse.
  const ApiConfig._();

  /// URL base del backend FastAPI (sin barra final).
  ///
  /// Ejemplos de desarrollo:
  /// - Emulador Android: `http://10.0.2.2:8000`
  /// - Teléfono por USB: `http://127.0.0.1:8000` (con `adb reverse tcp:8000 tcp:8000`)
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// Indica si `API_BASE_URL` fue definida al compilar la aplicación.
  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Endpoint de inicio de sesión de CLIENTES.
  ///
  /// Flutter es exclusivamente para clientes; NO se debe usar la ruta de
  /// personal (`/auth/personal/login`).
  static String get clientesLoginUrl => '$baseUrl/auth/clientes/login';

  /// Endpoint para obtener el usuario autenticado actual.
  static String get authMeUrl => '$baseUrl/auth/me';

  /// Ayuda para desarrollo cuando falta configurar la URL base.
  static const String missingBaseUrlHint =
      'Falta configurar API_BASE_URL. Ejecuta la app con '
      '--dart-define=API_BASE_URL=http://10.0.2.2:8000 (emulador) o '
      '--dart-define=API_BASE_URL=http://127.0.0.1:8000 (teléfono con adb reverse).';
}
