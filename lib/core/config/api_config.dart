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

  // ---------------------------------------------------------------------------
  // CU09 - Catálogo público (sin autenticación)
  // ---------------------------------------------------------------------------

  /// Endpoint de listado de productos activos con filtros opcionales.
  static String get productosUrl => '$baseUrl/productos';

  /// Endpoint de detalle de un producto (incluye recursos y variantes).
  static String productoDetalleUrl(int productoId) =>
      '$baseUrl/productos/$productoId';

  /// Endpoint de disponibilidad de un producto por sucursal.
  static String productoDisponibilidadUrl(int productoId) =>
      '$baseUrl/productos/$productoId/disponibilidad';

  /// Endpoint de opciones de filtros del catálogo.
  static String get catalogoFiltrosUrl => '$baseUrl/catalogo/filtros';

  // ---------------------------------------------------------------------------
  // CU15 - Carrito del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  /// Endpoint para agregar una prenda al carrito activo de la sucursal.
  static String get carritoItemsUrl => '$baseUrl/carritos/items';

  /// Endpoint del listado de carritos activos del cliente.
  static String get carritosUrl => '$baseUrl/carritos';

  /// Endpoint del detalle de un carrito.
  static String carritoDetalleUrl(int carritoId) =>
      '$baseUrl/carritos/$carritoId';

  /// Endpoint de una línea concreta del carrito.
  static String carritoItemUrl(int carritoId, int detalleId) =>
      '$baseUrl/carritos/$carritoId/items/$detalleId';

  // ---------------------------------------------------------------------------
  // CU16 - Reserva de prendas del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  /// Endpoint de creación (`POST`) y listado (`GET`) de reservas.
  static String get reservasUrl => '$baseUrl/reservas';

  /// Endpoint del detalle de una reserva.
  static String reservaDetalleUrl(int reservaId) =>
      '$baseUrl/reservas/$reservaId';

  /// Endpoint de cancelación de una reserva.
  static String reservaCancelarUrl(int reservaId) =>
      '$baseUrl/reservas/$reservaId/cancelar';

  /// Ayuda para desarrollo cuando falta configurar la URL base.
  static const String missingBaseUrlHint =
      'Falta configurar API_BASE_URL. Ejecuta la app con '
      '--dart-define=API_BASE_URL=http://10.0.2.2:8000 (emulador) o '
      '--dart-define=API_BASE_URL=http://127.0.0.1:8000 (teléfono con adb reverse).';
}
