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
  // Asistencia Inteligente (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  /// Endpoint de recomendaciones basadas en el catálogo e inventario reales.
  ///
  /// La IA (OpenAI/DeepSeek) solo selecciona/rankea candidatos reales: la app
  /// nunca envía ni recibe claves de IA. La `API key` vive solo en el backend.
  static String get asistenciaRecomendacionesUrl =>
      asistenciaRecomendacionesUrlDesde(baseUrl);

  /// Endpoint de recomendaciones para una URL base dada (inyección en pruebas).
  static String asistenciaRecomendacionesUrlDesde(String base) =>
      '$base/asistencia-inteligente/recomendaciones';

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

  // ---------------------------------------------------------------------------
  // CU19 - Compra digital del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  /// Endpoint de creación de la venta digital (`POST`).
  ///
  /// Convierte un carrito ACTIVO en una venta PENDIENTE. El cliente solo envía
  /// `carrito_id` y `canal`; el resto lo deriva el backend del carrito.
  static String get ventasDigitalUrl => ventasDigitalUrlDesde(baseUrl);

  /// Endpoint de creación de la venta digital para una URL base dada.
  ///
  /// Se parametriza para poder probar el servicio sin depender de
  /// `--dart-define=API_BASE_URL`.
  static String ventasDigitalUrlDesde(String base) => '$base/ventas/digital';

  // ---------------------------------------------------------------------------
  // CU22 - Pago electrónico del CLIENTE con Stripe (requiere JWT de cliente)
  // ---------------------------------------------------------------------------

  /// Endpoint de creación/reutilización del PaymentIntent (`POST`).
  ///
  /// El cliente solo envía `venta_id`; el monto, la moneda y la metadata los
  /// deriva el backend de la venta.
  static String get stripeIntencionUrl => stripeIntencionUrlDesde(baseUrl);

  /// Endpoint de creación de la intención para una URL base dada.
  ///
  /// Se parametriza para poder probar el servicio sin depender de
  /// `--dart-define=API_BASE_URL`.
  static String stripeIntencionUrlDesde(String base) =>
      '$base/pagos/stripe/intencion';

  /// Endpoint del estado backend de la venta y su pago electrónico (`GET`).
  static String stripeEstadoVentaUrl(int ventaId) =>
      stripeEstadoVentaUrlDesde(baseUrl, ventaId);

  /// Endpoint de consulta de estado para una URL base dada.
  static String stripeEstadoVentaUrlDesde(String base, int ventaId) =>
      '$base/pagos/stripe/ventas/$ventaId/estado';

  // ---------------------------------------------------------------------------
  // CU26 - Vestidor virtual AR del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------
  //
  // El backend solo entrega metadatos (asset PNG transparente, factores y
  // offsets de anclaje al torso). La detección corporal ocurre 100% local en el
  // teléfono (motor CameraX + MediaPipe de Harold); estas rutas no procesan
  // frames ni imágenes de cámara.

  /// Configuraciones AR compatibles de un producto (`GET`).
  static String vestidorConfiguracionesUrl(int productoId) =>
      vestidorConfiguracionesUrlDesde(baseUrl, productoId);

  /// Configuraciones AR de un producto para una URL base dada.
  static String vestidorConfiguracionesUrlDesde(String base, int productoId) =>
      '$base/vestidor-virtual/productos/$productoId/configuraciones';

  /// Creación de sesión de vestidor (`POST`).
  static String get vestidorSesionesUrl => vestidorSesionesUrlDesde(baseUrl);

  /// Creación de sesión para una URL base dada.
  static String vestidorSesionesUrlDesde(String base) =>
      '$base/vestidor-virtual/sesiones';

  /// Registro de inicio de prueba dentro de una sesión (`POST`).
  static String vestidorSesionPruebasUrl(int sesionId) =>
      vestidorSesionPruebasUrlDesde(baseUrl, sesionId);

  /// Registro de inicio de prueba para una URL base dada.
  static String vestidorSesionPruebasUrlDesde(String base, int sesionId) =>
      '$base/vestidor-virtual/sesiones/$sesionId/pruebas';

  /// Finalización de una prueba (`PATCH`).
  static String vestidorPruebaFinalizarUrl(int pruebaId) =>
      vestidorPruebaFinalizarUrlDesde(baseUrl, pruebaId);

  /// Finalización de una prueba para una URL base dada.
  static String vestidorPruebaFinalizarUrlDesde(String base, int pruebaId) =>
      '$base/vestidor-virtual/pruebas/$pruebaId/finalizar';

  /// Finalización de una sesión (`PATCH`).
  static String vestidorSesionFinalizarUrl(int sesionId) =>
      vestidorSesionFinalizarUrlDesde(baseUrl, sesionId);

  /// Finalización de una sesión para una URL base dada.
  static String vestidorSesionFinalizarUrlDesde(String base, int sesionId) =>
      '$base/vestidor-virtual/sesiones/$sesionId/finalizar';

  /// Ayuda para desarrollo cuando falta configurar la URL base.
  static const String missingBaseUrlHint =
      'Falta configurar API_BASE_URL. Ejecuta la app con '
      '--dart-define=API_BASE_URL=http://10.0.2.2:8000 (emulador) o '
      '--dart-define=API_BASE_URL=http://127.0.0.1:8000 (teléfono con adb reverse).';
}
