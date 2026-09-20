// Modelos de filtros del catálogo público (`GET /catalogo/filtros`).
//
// Todas las opciones provienen del backend: nunca se hardcodean IDs. Incluye
// además [CatalogoFiltrosSeleccion], el estado inmutable de filtros elegidos por
// el cliente.

/// Opción simple de filtro (id + nombre).
class OpcionFiltro {
  const OpcionFiltro({required this.id, required this.nombre});

  factory OpcionFiltro.fromJson(Map<String, dynamic> json) =>
      OpcionFiltro(id: _toInt(json['id']), nombre: _toString(json['nombre']));

  final int id;
  final String nombre;
}

/// Colección de una temporada concreta.
class ColeccionFiltro {
  const ColeccionFiltro({
    required this.id,
    required this.nombre,
    required this.temporadaId,
  });

  factory ColeccionFiltro.fromJson(Map<String, dynamic> json) =>
      ColeccionFiltro(
        id: _toInt(json['id']),
        nombre: _toString(json['nombre']),
        temporadaId: _toInt(json['temporada_id']),
      );

  final int id;
  final String nombre;
  final int temporadaId;
}

/// Sucursal con ciudad opcional.
class SucursalFiltro {
  const SucursalFiltro({
    required this.id,
    required this.nombre,
    required this.ciudad,
  });

  factory SucursalFiltro.fromJson(Map<String, dynamic> json) => SucursalFiltro(
    id: _toInt(json['id']),
    nombre: _toString(json['nombre']),
    ciudad: _toNullableString(json['ciudad']),
  );

  final int id;
  final String nombre;
  final String? ciudad;

  /// Etiqueta amigable para mostrar en el selector.
  String get etiqueta {
    final String ciudadLimpia = ciudad?.trim() ?? '';
    return ciudadLimpia.isEmpty ? nombre : '$nombre · $ciudadLimpia';
  }
}

/// Respuesta completa de `GET /catalogo/filtros`.
class CatalogoFiltros {
  const CatalogoFiltros({
    required this.categorias,
    required this.tallas,
    required this.colores,
    required this.temporadas,
    required this.colecciones,
    required this.sucursales,
  });

  factory CatalogoFiltros.fromJson(Map<String, dynamic> json) =>
      CatalogoFiltros(
        categorias: _listaDe(json['categorias'], OpcionFiltro.fromJson),
        tallas: _listaDe(json['tallas'], OpcionFiltro.fromJson),
        colores: _listaDe(json['colores'], OpcionFiltro.fromJson),
        temporadas: _listaDe(json['temporadas'], OpcionFiltro.fromJson),
        colecciones: _listaDe(json['colecciones'], ColeccionFiltro.fromJson),
        sucursales: _listaDe(json['sucursales'], SucursalFiltro.fromJson),
      );

  final List<OpcionFiltro> categorias;
  final List<OpcionFiltro> tallas;
  final List<OpcionFiltro> colores;
  final List<OpcionFiltro> temporadas;
  final List<ColeccionFiltro> colecciones;
  final List<SucursalFiltro> sucursales;

  /// Colecciones compatibles con una temporada (o todas si es null).
  List<ColeccionFiltro> coleccionesDe(int? temporadaId) {
    if (temporadaId == null) return colecciones;
    return colecciones
        .where(
          (ColeccionFiltro coleccion) => coleccion.temporadaId == temporadaId,
        )
        .toList();
  }

  /// Indica si una colección pertenece a la temporada dada.
  bool coleccionCompatible(int? coleccionId, int? temporadaId) {
    if (coleccionId == null) return true;
    if (temporadaId == null) return true;
    return colecciones.any(
      (ColeccionFiltro coleccion) =>
          coleccion.id == coleccionId && coleccion.temporadaId == temporadaId,
    );
  }

  String nombreOpcion(List<OpcionFiltro> opciones, int? id) {
    if (id == null) return '';
    for (final OpcionFiltro opcion in opciones) {
      if (opcion.id == id) return opcion.nombre;
    }
    return '';
  }
}

/// Estado inmutable de los filtros seleccionados por el cliente.
class CatalogoFiltrosSeleccion {
  const CatalogoFiltrosSeleccion({
    this.categoriaId,
    this.tallaId,
    this.colorId,
    this.temporadaId,
    this.coleccionId,
    this.sucursalId,
    this.soloConStock = false,
  });

  final int? categoriaId;
  final int? tallaId;
  final int? colorId;
  final int? temporadaId;
  final int? coleccionId;
  final int? sucursalId;
  final bool soloConStock;

  /// Cantidad de filtros activos (para el indicador visual).
  int get activos {
    int total = 0;
    if (categoriaId != null) total++;
    if (tallaId != null) total++;
    if (colorId != null) total++;
    if (temporadaId != null) total++;
    if (coleccionId != null) total++;
    if (sucursalId != null) total++;
    if (soloConStock) total++;
    return total;
  }

  bool get estaVacio => activos == 0;

  /// Devuelve una copia sin filtros.
  CatalogoFiltrosSeleccion limpiar() => const CatalogoFiltrosSeleccion();

  /// Copia selectiva. Pasar `null` explícitamente limpia el campo.
  CatalogoFiltrosSeleccion copyWith({
    Object? categoriaId = _sinCambio,
    Object? tallaId = _sinCambio,
    Object? colorId = _sinCambio,
    Object? temporadaId = _sinCambio,
    Object? coleccionId = _sinCambio,
    Object? sucursalId = _sinCambio,
    bool? soloConStock,
  }) {
    return CatalogoFiltrosSeleccion(
      categoriaId: identical(categoriaId, _sinCambio)
          ? this.categoriaId
          : categoriaId as int?,
      tallaId: identical(tallaId, _sinCambio) ? this.tallaId : tallaId as int?,
      colorId: identical(colorId, _sinCambio) ? this.colorId : colorId as int?,
      temporadaId: identical(temporadaId, _sinCambio)
          ? this.temporadaId
          : temporadaId as int?,
      coleccionId: identical(coleccionId, _sinCambio)
          ? this.coleccionId
          : coleccionId as int?,
      sucursalId: identical(sucursalId, _sinCambio)
          ? this.sucursalId
          : sucursalId as int?,
      soloConStock: soloConStock ?? this.soloConStock,
    );
  }
}

const Object _sinCambio = Object();

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

String? _toNullableString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final String limpio = value.trim();
    return limpio.isEmpty ? null : limpio;
  }
  return value.toString();
}
