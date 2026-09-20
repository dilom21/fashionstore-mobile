// Modelos reales del carrito del CLIENTE (CU15).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase):
//   carrito_id          -> carritoId
//   cantidad_lineas     -> cantidadLineas
//   cantidad_unidades   -> cantidadUnidades
//   fecha_actualizacion -> fechaActualizacion
//   detalle_id          -> detalleId
//   producto_nombre     -> productoNombre
//   precio_unitario     -> precioUnitario
//   imagen_principal    -> imagenPrincipal
//   stock_disponible    -> stockDisponible
//   subtotal_linea      -> subtotalLinea
//
// El parsing es defensivo (igual que el catálogo CU09): los Decimal del backend
// pueden llegar como number o string y las listas como null o vacías.

/// Formatea un monto en bolivianos (mismo formato que el catálogo CU09).
String formatearPrecio(double monto) => 'Bs ${monto.toStringAsFixed(2)}';

/// Formatea la última actualización del carrito de forma legible.
String formatearActualizacion(DateTime? fecha) {
  if (fecha == null) return 'sin registro';
  final Duration diferencia = DateTime.now().difference(fecha);
  if (diferencia.isNegative || diferencia.inMinutes < 1) {
    return 'hace instantes';
  }
  if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
  if (diferencia.inDays == 1) return 'ayer';
  if (diferencia.inDays < 7) return 'hace ${diferencia.inDays} días';
  return '${_dosDigitos(fecha.day)}/${_dosDigitos(fecha.month)}/${fecha.year} '
      '· ${_dosDigitos(fecha.hour)}:${_dosDigitos(fecha.minute)}';
}

String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');

/// Carrito activo del cliente en una sucursal (`GET /carritos`).
class CarritoResumen {
  const CarritoResumen({
    required this.carritoId,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.cantidadLineas,
    required this.cantidadUnidades,
    required this.subtotal,
    required this.fechaActualizacion,
  });

  factory CarritoResumen.fromJson(Map<String, dynamic> json) => CarritoResumen(
    carritoId: _toInt(json['carrito_id']),
    sucursalId: _toInt(json['sucursal_id']),
    sucursalNombre: _toString(json['sucursal_nombre']),
    cantidadLineas: _toInt(json['cantidad_lineas']),
    cantidadUnidades: _toInt(json['cantidad_unidades']),
    subtotal: _toDouble(json['subtotal']),
    fechaActualizacion: _toDateTime(json['fecha_actualizacion']),
  );

  final int carritoId;
  final int sucursalId;
  final String sucursalNombre;
  final int cantidadLineas;
  final int cantidadUnidades;
  final double subtotal;
  final DateTime? fechaActualizacion;

  /// Nombre de sucursal listo para mostrar.
  String get sucursalEtiqueta => sucursalNombre.trim().isEmpty
      ? 'Sucursal $sucursalId'
      : sucursalNombre.trim();

  String get subtotalFormateado => formatearPrecio(subtotal);

  String get actualizacionTexto => formatearActualizacion(fechaActualizacion);
}

/// Respuesta de `GET /carritos`.
class CarritoListaResponse {
  const CarritoListaResponse({
    required this.items,
    required this.totalCarritosActivos,
  });

  factory CarritoListaResponse.fromJson(Map<String, dynamic> json) =>
      CarritoListaResponse(
        items: _listaDe(json['items'], CarritoResumen.fromJson),
        totalCarritosActivos: _toInt(json['total_carritos_activos']),
      );

  final List<CarritoResumen> items;

  /// Total de carritos activos reportado por el backend (fuente de verdad).
  final int totalCarritosActivos;

  bool get estaVacio => items.isEmpty;
}

/// Una línea (prenda) del carrito (`CarritoItem` del backend).
class CarritoItem {
  const CarritoItem({
    required this.detalleId,
    required this.inventarioId,
    required this.productoId,
    required this.productoNombre,
    required this.precioUnitario,
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
    required this.stockDisponible,
    required this.subtotalLinea,
  });

  factory CarritoItem.fromJson(Map<String, dynamic> json) => CarritoItem(
    detalleId: _toInt(json['detalle_id']),
    inventarioId: _toInt(json['inventario_id']),
    productoId: _toInt(json['producto_id']),
    productoNombre: _toString(json['producto_nombre']),
    precioUnitario: _toDouble(json['precio_unitario']),
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
    stockDisponible: _toInt(json['stock_disponible']),
    subtotalLinea: _toDouble(json['subtotal_linea']),
  );

  final int detalleId;
  final int inventarioId;
  final int productoId;
  final String productoNombre;
  final double precioUnitario;

  /// URL de la imagen principal entregada por el backend. Puede ser `null`.
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

  /// Stock disponible reportado por el backend (nunca se recalcula en la app).
  final int stockDisponible;

  final double subtotalLinea;

  String get precioUnitarioFormateado => formatearPrecio(precioUnitario);

  String get subtotalFormateado => formatearPrecio(subtotalLinea);

  /// El backend es la autoridad final del stock, pero se evita enviar
  /// cantidades obviamente por encima de lo disponible.
  bool get puedeIncrementar => cantidad < stockDisponible;

  /// Para quitar la última unidad se usa DELETE, nunca cantidad 0.
  bool get puedeDecrementar => cantidad > 1;

  bool get tieneStock => stockDisponible > 0;
}

/// Detalle completo del carrito (`GET /carritos/{carrito_id}`).
class CarritoDetalle {
  const CarritoDetalle({
    required this.carritoId,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    required this.items,
    required this.cantidadTotalUnidades,
    required this.subtotalCarrito,
  });

  factory CarritoDetalle.fromJson(Map<String, dynamic> json) => CarritoDetalle(
    carritoId: _toInt(json['carrito_id']),
    sucursalId: _toInt(json['sucursal_id']),
    sucursalNombre: _toString(json['sucursal_nombre']),
    estado: _toString(json['estado']),
    fechaCreacion: _toDateTime(json['fecha_creacion']),
    fechaActualizacion: _toDateTime(json['fecha_actualizacion']),
    items: _listaDe(json['items'], CarritoItem.fromJson),
    cantidadTotalUnidades: _toInt(json['cantidad_total_unidades']),
    subtotalCarrito: _toDouble(json['subtotal_carrito']),
  );

  /// Detalle vacío: al eliminar un carrito el backend puede responder
  /// `204 No Content`, caso en el que no hay cuerpo que parsear.
  factory CarritoDetalle.vacio(int carritoId) => CarritoDetalle(
    carritoId: carritoId,
    sucursalId: 0,
    sucursalNombre: '',
    estado: '',
    fechaCreacion: null,
    fechaActualizacion: null,
    items: const <CarritoItem>[],
    cantidadTotalUnidades: 0,
    subtotalCarrito: 0,
  );

  final int carritoId;
  final int sucursalId;
  final String sucursalNombre;
  final String estado;
  final DateTime? fechaCreacion;
  final DateTime? fechaActualizacion;
  final List<CarritoItem> items;

  /// Unidades totales reportadas por el backend (fuente de verdad).
  final int cantidadTotalUnidades;

  /// Subtotal reportado por el backend (fuente de verdad).
  final double subtotalCarrito;

  bool get tieneItems => items.isNotEmpty;

  /// El backend solo mantiene carritos con estado `ACTIVO`.
  bool get estaActivo => estado.trim().toUpperCase() == 'ACTIVO';

  /// Cantidad de líneas distintas del carrito.
  int get cantidadLineas => items.length;

  String get subtotalFormateado => formatearPrecio(subtotalCarrito);

  String get actualizacionTexto => formatearActualizacion(fechaActualizacion);

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
