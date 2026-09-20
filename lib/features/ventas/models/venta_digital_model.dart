// Modelos reales de la venta digital del CLIENTE (CU19).
//
// Copian exactamente el contrato `VentaDigitalResponse` del backend FastAPI
// (snake_case) y lo traducen a nombres Dart idiomáticos (camelCase):
//   venta_id                 -> ventaId
//   carrito_id               -> carritoId
//   cliente_id               -> clienteId
//   sucursal_id              -> sucursalId
//   sucursal_nombre          -> sucursalNombre
//   fecha_hora               -> fechaHora
//   cantidad_total_unidades  -> cantidadTotalUnidades
//   detalle_id               -> detalleId
//   inventario_id            -> inventarioId
//   producto_id              -> productoId
//   producto_nombre          -> productoNombre
//   imagen_principal         -> imagenPrincipal
//   variante_producto_id     -> varianteProductoId
//   talla_id / talla_nombre  -> tallaId / tallaNombre
//   color_id / color_nombre  -> colorId / colorNombre
//   temporada_id / _nombre   -> temporadaId / temporadaNombre
//   precio_unitario          -> precioUnitario
//   subtotal_linea           -> subtotalLinea
//
// El parsing es defensivo (igual que catálogo, carrito y reservas): los Decimal
// pueden llegar como number o string, las listas como null o vacías y las
// fechas como ISO. CU19 no procesa pago: la venta nace PENDIENTE.

/// Formatea un monto en bolivianos (mismo formato que el resto de la app).
String _formatearPrecio(double monto) => 'Bs ${monto.toStringAsFixed(2)}';

/// Código visual de la venta: `45` -> `VEN-00045`.
///
/// Es solo presentación: nunca se envía al backend.
String codigoVenta(int ventaId) => 'VEN-${ventaId.toString().padLeft(5, '0')}';

/// Línea de la venta digital (snapshot del checkout).
class VentaItem {
  const VentaItem({
    required this.detalleId,
    required this.inventarioId,
    required this.productoId,
    required this.productoNombre,
    required this.imagenPrincipal,
    required this.varianteProductoId,
    required this.sku,
    required this.tallaId,
    required this.tallaNombre,
    required this.colorId,
    required this.colorNombre,
    required this.temporadaId,
    required this.temporadaNombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotalLinea,
  });

  factory VentaItem.fromJson(Map<String, dynamic> json) => VentaItem(
    detalleId: _toInt(json['detalle_id']),
    inventarioId: _toInt(json['inventario_id']),
    productoId: _toInt(json['producto_id']),
    productoNombre: _toString(json['producto_nombre']),
    imagenPrincipal: _toNullableString(json['imagen_principal']),
    varianteProductoId: _toNullableInt(json['variante_producto_id']),
    sku: _toString(json['sku']),
    tallaId: _toNullableInt(json['talla_id']),
    tallaNombre: _toString(json['talla_nombre']),
    colorId: _toNullableInt(json['color_id']),
    colorNombre: _toString(json['color_nombre']),
    temporadaId: _toNullableInt(json['temporada_id']),
    temporadaNombre: _toString(json['temporada_nombre']),
    cantidad: _toInt(json['cantidad']),
    precioUnitario: _toDouble(json['precio_unitario']),
    subtotalLinea: _toDouble(json['subtotal_linea']),
  );

  final int detalleId;
  final int inventarioId;
  final int productoId;
  final String productoNombre;

  /// URL de la imagen entregada por el backend (puede ser `null`).
  final String? imagenPrincipal;

  final int? varianteProductoId;
  final String sku;
  final int? tallaId;
  final String tallaNombre;
  final int? colorId;
  final String colorNombre;
  final int? temporadaId;
  final String temporadaNombre;
  final int cantidad;
  final double precioUnitario;
  final double subtotalLinea;

  String get precioUnitarioFormateado => _formatearPrecio(precioUnitario);

  String get subtotalFormateado => _formatearPrecio(subtotalLinea);
}

/// Venta digital PENDIENTE (`POST /ventas/digital`).
class VentaDigital {
  const VentaDigital({
    required this.ventaId,
    required this.carritoId,
    required this.clienteId,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.canal,
    required this.estado,
    required this.fechaHora,
    required this.total,
    required this.items,
    required this.cantidadTotalUnidades,
  });

  factory VentaDigital.fromJson(Map<String, dynamic> json) => VentaDigital(
    ventaId: _toInt(json['venta_id']),
    carritoId: _toNullableInt(json['carrito_id']),
    clienteId: _toInt(json['cliente_id']),
    sucursalId: _toInt(json['sucursal_id']),
    sucursalNombre: _toString(json['sucursal_nombre']),
    canal: _toString(json['canal']),
    estado: _toString(json['estado']),
    fechaHora: _toDateTime(json['fecha_hora']),
    total: _toDouble(json['total']),
    items: _listaDe(json['items'], VentaItem.fromJson),
    cantidadTotalUnidades: _toInt(json['cantidad_total_unidades']),
  );

  final int ventaId;

  /// El backend lo devuelve `null` en ventas que no provienen de un carrito.
  final int? carritoId;

  final int clienteId;
  final int sucursalId;
  final String sucursalNombre;

  /// Canal de la venta: CU19 siempre envía `MOVIL`.
  final String canal;

  /// Estado real del backend. CU19 crea la venta en `PENDIENTE`.
  final String estado;

  final DateTime? fechaHora;
  final double total;
  final List<VentaItem> items;

  /// Unidades totales reportadas por el backend (fuente de verdad).
  final int cantidadTotalUnidades;

  /// Código visual (solo presentación).
  String get codigo => codigoVenta(ventaId);

  /// La venta fue creada pero todavía no está pagada.
  bool get estaPendiente => estado.trim().toUpperCase() == 'PENDIENTE';

  bool get tieneItems => items.isNotEmpty;

  /// Cantidad de prendas (líneas) distintas.
  int get cantidadLineas => items.length;

  String get totalFormateado => _formatearPrecio(total);

  String get sucursalEtiqueta => sucursalNombre.trim().isEmpty
      ? 'Sucursal $sucursalId'
      : sucursalNombre.trim();
}

// ---------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// ---------------------------------------------------------------------------

List<T> _listaDe<T>(Object? value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return <T>[];
  final List<T> resultado = <T>[];
  for (final Object? item in value) {
    if (item is Map<String, dynamic>) {
      resultado.add(fromJson(item));
    } else if (item is Map) {
      resultado.add(fromJson(item.cast<String, dynamic>()));
    }
  }
  return resultado;
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _toNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _toDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String _toString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

String? _toNullableString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final String limpio = value.trim();
    return limpio.isEmpty ? null : limpio;
  }
  return value.toString();
}

DateTime? _toDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final String texto = value.toString().trim();
  if (texto.isEmpty) return null;
  return DateTime.tryParse(texto)?.toLocal();
}
