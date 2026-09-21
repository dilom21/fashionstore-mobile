// Modelos de Asistencia Inteligente (recomendaciones con IA).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase). El parsing es defensivo: precio puede llegar como
// number o string, las listas pueden venir vacías y los campos de variante
// (talla, color, inventario, sucursal, temporada) pueden ser null cuando el
// backend marca `requiere_seleccion` (talla no resuelta).
//
// IMPORTANTE: el backend reconstruye todos los datos comerciales desde
// PostgreSQL. La app NUNCA calcula precio, stock ni inventario por su cuenta.

/// Recomendación de una prenda devuelta por el backend.
class RecomendacionProducto {
  const RecomendacionProducto({
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.categoria,
    required this.stockDisponible,
    required this.motivo,
    required this.requiereSeleccion,
    this.imagenUrl,
    this.varianteId,
    this.talla,
    this.color,
    this.inventarioId,
    this.sucursalId,
    this.sucursal,
    this.temporada,
  });

  factory RecomendacionProducto.fromJson(Map<String, dynamic> json) =>
      RecomendacionProducto(
        productoId: _toInt(json['producto_id']),
        nombre: _toString(json['nombre']),
        precio: _toDouble(json['precio']),
        imagenUrl: _toNullableString(json['imagen_url']),
        categoria: _toString(json['categoria']),
        varianteId: _toNullableInt(json['variante_id']),
        talla: _toNullableString(json['talla']),
        color: _toNullableString(json['color']),
        inventarioId: _toNullableInt(json['inventario_id']),
        sucursalId: _toNullableInt(json['sucursal_id']),
        sucursal: _toNullableString(json['sucursal']),
        temporada: _toNullableString(json['temporada']),
        stockDisponible: _toInt(json['stock_disponible']),
        motivo: _toString(json['motivo']),
        requiereSeleccion: _toBool(json['requiere_seleccion'], fallback: true),
      );

  final int productoId;
  final String nombre;
  final double precio;
  final String? imagenUrl;
  final String categoria;
  final int? varianteId;
  final String? talla;
  final String? color;
  final int? inventarioId;
  final int? sucursalId;
  final String? sucursal;
  final String? temporada;
  final int stockDisponible;
  final String motivo;

  /// `true` cuando la talla/variante no está resuelta y debe elegirse en el
  /// detalle del producto (nunca se elige una talla arbitraria).
  final bool requiereSeleccion;

  /// Imagen real entregada por el backend, si existe.
  bool get tieneImagen => (imagenUrl ?? '').trim().isNotEmpty;

  /// Indica si puede agregarse directo al carrito (CU15) sin abrir el detalle.
  bool get puedeAgregarDirecto =>
      !requiereSeleccion && (inventarioId ?? 0) > 0 && (sucursalId ?? 0) > 0;

  String get precioFormateado => 'Bs ${precio.toStringAsFixed(2)}';

  String get stockEtiqueta => 'Stock: $stockDisponible';

  String get motivoTexto =>
      motivo.trim().isEmpty ? 'Recomendado para ti.' : motivo.trim();
}

/// Respuesta completa del endpoint de recomendaciones.
class RecomendacionesResponse {
  const RecomendacionesResponse({
    required this.titulo,
    required this.descripcion,
    required this.recomendaciones,
  });

  factory RecomendacionesResponse.fromJson(Map<String, dynamic> json) =>
      RecomendacionesResponse(
        titulo: _toString(json['titulo']),
        descripcion: _toString(json['descripcion']),
        recomendaciones: _listaDe(
          json['recomendaciones'],
          RecomendacionProducto.fromJson,
        ),
      );

  final String titulo;
  final String descripcion;
  final List<RecomendacionProducto> recomendaciones;

  bool get estaVacio => recomendaciones.isEmpty;
}

// -----------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// -----------------------------------------------------------------------------

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

bool _toBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String normalizado = value.toLowerCase().trim();
    if (normalizado == 'true' || normalizado == '1') return true;
    if (normalizado == 'false' || normalizado == '0') return false;
  }
  return fallback;
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
