// Modelos de disponibilidad por sucursal (CU09).
//
// El stock mostrado proviene del backend como `stock_disponible`; la app NUNCA
// lo recalcula ni lo deriva de otras operaciones.

/// Disponibilidad completa de un producto (`GET /productos/{id}/disponibilidad`).
class DisponibilidadProducto {
  const DisponibilidadProducto({
    required this.productoId,
    required this.producto,
    required this.sucursales,
  });

  factory DisponibilidadProducto.fromJson(Map<String, dynamic> json) =>
      DisponibilidadProducto(
        productoId: _toInt(json['producto_id']),
        producto: _toString(json['producto']),
        sucursales: _listaDe(
          json['sucursales'],
          DisponibilidadSucursal.fromJson,
        ),
      );

  final int productoId;
  final String producto;
  final List<DisponibilidadSucursal> sucursales;

  /// Total de variantes con stock disponible mayor a cero.
  int get totalVariantesConStock {
    int total = 0;
    for (final DisponibilidadSucursal sucursal in sucursales) {
      total += sucursal.variantes
          .where(
            (DisponibilidadVariante variante) => variante.stockDisponible > 0,
          )
          .length;
    }
    return total;
  }

  bool get estaVacio => sucursales.isEmpty;
}

/// Disponibilidad agrupada por sucursal.
class DisponibilidadSucursal {
  const DisponibilidadSucursal({
    required this.sucursalId,
    required this.sucursal,
    required this.variantes,
  });

  factory DisponibilidadSucursal.fromJson(Map<String, dynamic> json) =>
      DisponibilidadSucursal(
        sucursalId: _toInt(json['sucursal_id']),
        sucursal: _toString(json['sucursal']),
        variantes: _listaDe(json['variantes'], DisponibilidadVariante.fromJson),
      );

  final int sucursalId;
  final String sucursal;
  final List<DisponibilidadVariante> variantes;

  /// Variantes con stock mayor a cero.
  int get variantesConStock => variantes
      .where((DisponibilidadVariante variante) => variante.stockDisponible > 0)
      .length;
}

/// Variante concreta con su stock disponible.
class DisponibilidadVariante {
  const DisponibilidadVariante({
    required this.varianteId,
    required this.sku,
    required this.talla,
    required this.color,
    required this.temporada,
    required this.stockDisponible,
  });

  factory DisponibilidadVariante.fromJson(Map<String, dynamic> json) =>
      DisponibilidadVariante(
        varianteId: _toInt(json['variante_id']),
        sku: _toString(json['sku']),
        talla: _toString(json['talla']),
        color: _toString(json['color']),
        temporada: _toString(json['temporada']),
        stockDisponible: _toInt(json['stock_disponible']),
      );

  final int varianteId;
  final String sku;
  final String talla;
  final String color;
  final String temporada;

  /// Stock tal como lo entrega el backend.
  final int stockDisponible;

  bool get tieneStock => stockDisponible > 0;
}

// -----------------------------------------------------------------------------
// Helpers de parsing
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

String _toString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}
