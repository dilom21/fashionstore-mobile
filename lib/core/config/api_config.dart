/// Configuración central de acceso al backend FastAPI SaaS de FashionStore.
///
/// Toda dirección o ruta del backend se declara aquí y se consume desde este
/// punto. No se hardcodean URLs en páginas, widgets ni servicios.
///
/// La URL base se inyecta en tiempo de compilación, por ejemplo:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// La empresa activa NO es una constante de compilación: se obtiene de la
/// sesión tenant (`TenantSession.empresaSlug`) elegida por el cliente.
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

  // ---------------------------------------------------------------------------
  // Autenticación / registro SaaS
  // ---------------------------------------------------------------------------

  /// Empresas habilitadas para el selector público de login/registro.
  static String get empresasTenantUrl => '$baseUrl/auth/tenant/empresas';

  /// Login de CLIENTES con `empresa_slug` explícito.
  static String get clientesLoginUrl => '$baseUrl/auth/tenant/login';

  /// Registro SaaS de clientes (público, no emite token).
  static String get clientesRegistroUrl =>
      '$baseUrl/auth/tenant/clientes/registro';

  /// Identidad empresarial del usuario autenticado (contexto CLIENTE).
  static String get authMeUrl => '$baseUrl/auth/tenant/me';

  // ---------------------------------------------------------------------------
  // Catálogo público SaaS (sin autenticación)
  // ---------------------------------------------------------------------------

  /// Listado público paginado de productos de una empresa.
  static String catalogoProductosUrl(String empresaSlug) =>
      catalogoProductosUrlDesde(baseUrl, empresaSlug);

  static String catalogoProductosUrlDesde(String base, String empresaSlug) =>
      '$base/catalogo/public/${Uri.encodeComponent(empresaSlug)}/productos';

  /// Detalle público de un producto (variantes, recursos y disponibilidad).
  static String catalogoProductoDetalleUrl(
    String empresaSlug,
    int productoId,
  ) => catalogoProductoDetalleUrlDesde(baseUrl, empresaSlug, productoId);

  static String catalogoProductoDetalleUrlDesde(
    String base,
    String empresaSlug,
    int productoId,
  ) =>
      '$base/catalogo/public/${Uri.encodeComponent(empresaSlug)}'
      '/productos/$productoId';

  /// Opciones de filtros del catálogo público de una empresa.
  static String catalogoFiltrosUrl(String empresaSlug) =>
      catalogoFiltrosUrlDesde(baseUrl, empresaSlug);

  static String catalogoFiltrosUrlDesde(String base, String empresaSlug) =>
      '$base/catalogo/public/${Uri.encodeComponent(empresaSlug)}/filtros';

  // ---------------------------------------------------------------------------
  // CU15 - Carrito del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  static String get carritoItemsUrl => '$baseUrl/tenant/carritos/items';

  static String get carritosUrl => '$baseUrl/tenant/carritos';

  static String carritoDetalleUrl(int carritoId) =>
      '$baseUrl/tenant/carritos/$carritoId';

  static String carritoItemUrl(int carritoId, int detalleId) =>
      '$baseUrl/tenant/carritos/$carritoId/items/$detalleId';

  // ---------------------------------------------------------------------------
  // Asistencia Inteligente (temporalmente no disponible en la navegación SaaS)
  // ---------------------------------------------------------------------------

  static String get asistenciaRecomendacionesUrl =>
      asistenciaRecomendacionesUrlDesde(baseUrl);

  static String asistenciaRecomendacionesUrlDesde(String base) =>
      '$base/tenant/asistencia-inteligente/recomendaciones';

  // ---------------------------------------------------------------------------
  // CU16 - Reservas online del CLIENTE (requiere JWT de contexto cliente)
  // ---------------------------------------------------------------------------

  /// Listado (`GET`) y creación (`POST`) de reservas online.
  static String get reservasUrl => '$baseUrl/tenant/reservas';
  static String get reservasCrearUrl => '$baseUrl/tenant/reservas';

  /// Detalle real de una reserva del cliente.
  static String reservaDetalleUrl(int reservaId) =>
      '$baseUrl/tenant/reservas/$reservaId';

  /// Cancelación de una reserva.
  static String reservaCancelarUrl(int reservaId) =>
      '$baseUrl/tenant/reservas/$reservaId/cancelar';

  // ---------------------------------------------------------------------------
  // CU14/CU19 - Compra digital del CLIENTE
  // ---------------------------------------------------------------------------

  static String get ventasDigitalUrl => ventasDigitalUrlDesde(baseUrl);

  static String ventasDigitalUrlDesde(String base) =>
      '$base/tenant/ventas/digital';

  /// Ruta interna heredada para venta de contado (no usada por el flujo de
  /// cliente SaaS; se conserva para la infraestructura offline deshabilitada).
  static String get ventaContadoUrl => '$baseUrl/tenant/ventas/contado';

  // ---------------------------------------------------------------------------
  // CU22 - Pago electrónico del CLIENTE con Stripe
  // ---------------------------------------------------------------------------

  static String get stripeIntencionUrl => stripeIntencionUrlDesde(baseUrl);

  static String stripeIntencionUrlDesde(String base) =>
      '$base/tenant/pagos/stripe/intencion';

  static String stripeEstadoVentaUrl(int ventaId) =>
      stripeEstadoVentaUrlDesde(baseUrl, ventaId);

  static String stripeEstadoVentaUrlDesde(String base, int ventaId) =>
      '$base/tenant/pagos/stripe/ventas/$ventaId/estado';

  // ---------------------------------------------------------------------------
  // CU23 - Comprobante de venta del CLIENTE
  // ---------------------------------------------------------------------------

  /// Ruta real SaaS para el comprobante del CLIENTE autenticado.
  ///
  /// `GET /tenant/ventas/{venta_id}/comprobante` pertenece al personal con
  /// permiso GESTIONAR_VENTAS. El cliente debe usar la ruta colgada de su
  /// historial, que valida propiedad y estado.
  static String comprobanteVentaUrl(int ventaId) =>
      comprobanteVentaUrlDesde(baseUrl, ventaId);

  static String comprobanteVentaUrlDesde(String base, int ventaId) =>
      '$base/tenant/ventas/historial/$ventaId/comprobante';

  // ---------------------------------------------------------------------------
  // CU24 - Historial de compras del CLIENTE
  // ---------------------------------------------------------------------------

  static String get historialComprasUrl => historialComprasUrlDesde(baseUrl);

  static String historialComprasUrlDesde(String base) =>
      '$base/tenant/ventas/historial';

  static String historialCompraDetalleUrl(int ventaId) =>
      historialCompraDetalleUrlDesde(baseUrl, ventaId);

  static String historialCompraDetalleUrlDesde(String base, int ventaId) =>
      '$base/tenant/ventas/historial/$ventaId';

  // ---------------------------------------------------------------------------
  // CU26 - Vestidor virtual AR (temporalmente no disponible en la navegación)
  // ---------------------------------------------------------------------------

  static String vestidorConfiguracionesUrl(int productoId) =>
      vestidorConfiguracionesUrlDesde(baseUrl, productoId);

  static String vestidorConfiguracionesUrlDesde(String base, int productoId) =>
      '$base/tenant/vestidor-virtual/productos/$productoId/configuraciones';

  static String get vestidorSesionesUrl => vestidorSesionesUrlDesde(baseUrl);

  static String vestidorSesionesUrlDesde(String base) =>
      '$base/tenant/vestidor-virtual/sesiones';

  static String vestidorSesionPruebasUrl(int sesionId) =>
      vestidorSesionPruebasUrlDesde(baseUrl, sesionId);

  static String vestidorSesionPruebasUrlDesde(String base, int sesionId) =>
      '$base/tenant/vestidor-virtual/sesiones/$sesionId/pruebas';

  static String vestidorPruebaFinalizarUrl(int pruebaId) =>
      vestidorPruebaFinalizarUrlDesde(baseUrl, pruebaId);

  static String vestidorPruebaFinalizarUrlDesde(String base, int pruebaId) =>
      '$base/tenant/vestidor-virtual/pruebas/$pruebaId/finalizar';

  static String vestidorSesionFinalizarUrl(int sesionId) =>
      vestidorSesionFinalizarUrlDesde(baseUrl, sesionId);

  static String vestidorSesionFinalizarUrlDesde(String base, int sesionId) =>
      '$base/tenant/vestidor-virtual/sesiones/$sesionId/finalizar';

  /// Ayuda para desarrollo cuando falta configurar la URL base.
  static const String missingBaseUrlHint =
      'Falta configurar API_BASE_URL. Ejecuta la app con '
      '--dart-define=API_BASE_URL=http://10.0.2.2:8000 (emulador) o '
      '--dart-define=API_BASE_URL=http://127.0.0.1:8000 (teléfono con adb reverse).';
}
