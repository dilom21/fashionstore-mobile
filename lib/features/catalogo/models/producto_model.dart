// Modelos del catálogo público de VANTER MEN (CU09).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase):
//   categoria_id -> categoriaId
//   es_principal -> esPrincipal
//   imagen_principal_url -> imagenPrincipalUrl
//
// El parsing es defensivo: descripcion puede ser null, precio puede llegar como
// number o string, y las listas pueden venir vacías.

/// Producto del listado público (`GET /productos`).
///
/// El listado incluye [imagenPrincipalUrl], la URL ya resuelta por el backend
/// del recurso principal general (fotografía del modelo). Flutter NO construye
/// esa URL: se limita a consumir el valor recibido.
///
/// Para el detalle usar [ProductoDetalle], que añade [recursos] y [variantes].
class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    required this.estado,
    required this.categoriaId,
    required this.categoriaNombre,
    this.imagenPrincipalUrl,
  });

  factory Producto.fromJson(Map<String, dynamic> json) => Producto(
        id: _toInt(json['id']),
        nombre: _toString(json['nombre']),
        descripcion: _toNullableString(json['descripcion']),
        precio: _toDouble(json['precio']),
        estado: _toBool(json['estado'], fallback: true),
        categoriaId: _toInt(json['categoria_id']),
        categoriaNombre: _categoriaNombre(json['categoria']),
        imagenPrincipalUrl: _toNullableString(json['imagen_principal_url']),
      );

  final int id;
  final String nombre;
  final String? descripcion;
  final double precio;
  final bool estado;
  final int categoriaId;
  final String categoriaNombre;

  /// URL del recurso principal general del producto, tal como la entrega el
  /// backend (`imagen_principal_url`). Puede ser `null`.
  final String? imagenPrincipalUrl;

  /// Descripción recortada para tarjetas del listado.
  String get descripcionCorta {
    final String texto = descripcion?.trim() ?? '';
    return texto.isEmpty ? 'Sin descripción disponible.' : texto;
  }

  /// Precio formateado en bolivianos.
  String get precioFormateado => 'Bs ${precio.toStringAsFixed(2)}';
}

/// Recurso (imagen) asociado a un producto.
class RecursoProducto {
  const RecursoProducto({
    required this.id,
    required this.tipo,
    required this.url,
    required this.esPrincipal,
    required this.colorNombre,
  });

  factory RecursoProducto.fromJson(Map<String, dynamic> json) =>
      RecursoProducto(
        id: _toInt(json['id']),
        tipo: _toString(json['tipo']),
        url: _toString(json['url']),
        esPrincipal: _toBool(json['es_principal']),
        colorNombre: _colorNombre(json['color']),
      );

  final int id;
  final String tipo;
  final String url;
  final bool esPrincipal;
  final String? colorNombre;

  /// Indica si la URL es utilizable por `Image.network`.
  bool get tieneUrl => url.trim().isNotEmpty;

  /// Indica si el recurso representa una imagen mostrable.
  ///
  /// El backend expone `tipo` como texto libre (por ejemplo `imagen` o
  /// `galeria`). Se acepta cualquier tipo vacío o relacionado con imágenes y se
  /// descartan tipos claramente no visuales (por ejemplo `video`). No se
  /// inspecciona nunca el nombre del archivo.
  bool get esImagen {
    final String normalizado = tipo.trim().toLowerCase();
    if (normalizado.isEmpty) return true;
    return normalizado.contains('imag') ||
        normalizado.contains('image') ||
        normalizado.contains('foto') ||
        normalizado.contains('photo') ||
        normalizado.contains('galer');
  }
}

/// Variante de un producto (talla/color) usada para mostrar opciones.
///
/// Cada variante puede exponer sus [inventarios] reales por sucursal y
/// temporada; de ahí se obtiene el `inventario_id` que exige CU15 para agregar
/// una prenda al carrito.
class VarianteProducto {
  const VarianteProducto({
    required this.id,
    required this.sku,
    required this.estado,
    required this.tallaId,
    required this.tallaNombre,
    required this.colorId,
    required this.colorNombre,
    this.inventarios = const <InventarioProducto>[],
  });

  factory VarianteProducto.fromJson(Map<String, dynamic> json) =>
      VarianteProducto(
        id: _toInt(json['id']),
        sku: _toString(json['sku']),
        estado: _toBool(json['estado'], fallback: true),
        tallaId: _idDe(json['talla']),
        tallaNombre: _nombreDe(json['talla']),
        colorId: _idDe(json['color']),
        colorNombre: _nombreDe(json['color']),
        inventarios: _listaDe(json['inventarios'], InventarioProducto.fromJson),
      );

  final int id;
  final String sku;
  final bool estado;
  final int? tallaId;
  final String tallaNombre;
  final int? colorId;
  final String colorNombre;

  /// Inventarios reales de la variante (uno por sucursal/temporada).
  final List<InventarioProducto> inventarios;

  /// Inventarios con stock disponible mayor a cero.
  List<InventarioProducto> get inventariosConStock => inventarios
      .where((InventarioProducto inventario) => inventario.stockDisponible > 0)
      .toList();

  bool get tieneStock => inventariosConStock.isNotEmpty;
}

/// Inventario real de una variante en una sucursal y temporada.
///
/// Es la fuente del `inventario_id` que consume `POST /carritos/items`: el
/// backend deriva producto, variante, talla y color a partir de ese id.
class InventarioProducto {
  const InventarioProducto({
    required this.id,
    required this.stockActual,
    required this.stockReservado,
    required this.stockDisponible,
    required this.fechaActualizacion,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.sucursalDireccion,
    required this.temporadaId,
    required this.temporadaNombre,
  });

  factory InventarioProducto.fromJson(Map<String, dynamic> json) {
    final Object? sucursal = json['sucursal'];
    final Object? temporada = json['temporada'];

    return InventarioProducto(
      id: _toInt(json['id']),
      stockActual: _toInt(json['stock_actual']),
      stockReservado: _toInt(json['stock_reservado']),
      stockDisponible: _toInt(json['stock_disponible']),
      fechaActualizacion: _toNullableString(json['fecha_actualizacion']),
      sucursalId: _idDe(sucursal) ?? _toNullableInt(json['sucursal_id']),
      sucursalNombre: _nombreOTexto(sucursal),
      sucursalDireccion: _direccionDe(sucursal),
      temporadaId: _idDe(temporada) ?? _toNullableInt(json['temporada_id']),
      temporadaNombre: _nombreOTexto(temporada),
    );
  }

  final int id;

  /// Stock físico actual reportado por el backend.
  final int stockActual;

  /// Unidades reservadas por el backend.
  final int stockReservado;

  /// Unidades realmente disponibles (nunca se recalcula en la app).
  final int stockDisponible;

  /// Fecha de actualización del inventario, tal como la entrega el backend.
  final String? fechaActualizacion;

  final int? sucursalId;
  final String sucursalNombre;
  final String sucursalDireccion;
  final int? temporadaId;
  final String temporadaNombre;

  bool get tieneStock => stockDisponible > 0;

  String get sucursalEtiqueta => sucursalNombre.trim().isEmpty
      ? 'Sucursal ${sucursalId ?? id}'
      : sucursalNombre.trim();
}


/// Detalle de producto (`GET /productos/{id}`), con recursos y variantes.
class ProductoDetalle extends Producto {
  const ProductoDetalle({
    required super.id,
    required super.nombre,
    required super.descripcion,
    required super.precio,
    required super.estado,
    required super.categoriaId,
    required super.categoriaNombre,
    super.imagenPrincipalUrl,
    required this.recursos,
    required this.variantes,
  });

  factory ProductoDetalle.fromJson(Map<String, dynamic> json) {
    final List<RecursoProducto> recursos = _listaDe(
      json['recursos'],
      RecursoProducto.fromJson,
    );
    final List<VarianteProducto> variantes = _listaDe(
      json['variantes'],
      VarianteProducto.fromJson,
    );

    return ProductoDetalle(
      id: _toInt(json['id']),
      nombre: _toString(json['nombre']),
      descripcion: _toNullableString(json['descripcion']),
      precio: _toDouble(json['precio']),
      estado: _toBool(json['estado'], fallback: true),
      categoriaId: _toInt(json['categoria_id']),
      categoriaNombre: _categoriaNombre(json['categoria']),
      imagenPrincipalUrl: _toNullableString(json['imagen_principal_url']),
      recursos: recursos,
      variantes: variantes,
    );
  }

  final List<RecursoProducto> recursos;
  final List<VarianteProducto> variantes;

  /// Recursos utilizables como imágenes, con el principal primero.
  ///
  /// Se filtran recursos sin URL y recursos que no representan imágenes (según
  /// [RecursoProducto.esImagen]). El orden relativo del backend se conserva
  /// dentro de cada grupo (principales y secundarios), por lo que el detalle
  /// puede soportar 0, 1, 2 o N recursos sin depender del nombre del archivo.
  List<RecursoProducto> get recursosUtilizables {
    final List<RecursoProducto> principales = <RecursoProducto>[];
    final List<RecursoProducto> secundarios = <RecursoProducto>[];
    for (final RecursoProducto recurso in recursos) {
      if (!recurso.tieneUrl || !recurso.esImagen) continue;
      if (recurso.esPrincipal) {
        principales.add(recurso);
      } else {
        secundarios.add(recurso);
      }
    }
    return <RecursoProducto>[...principales, ...secundarios];
  }

  /// Recurso principal (o el primero disponible) si existe.
  RecursoProducto? get recursoPrincipal {
    final List<RecursoProducto> usables = recursosUtilizables;
    return usables.isEmpty ? null : usables.first;
  }

  /// Nombres de tallas únicos y no vacíos.
  List<String> get tallas => _nombresUnicos(
        variantes.map((VarianteProducto variante) => variante.tallaNombre),
      );

  /// Nombres de colores únicos y no vacíos.
  List<String> get colores => _nombresUnicos(
        variantes.map((VarianteProducto variante) => variante.colorNombre),
      );

  /// Tallas (id + nombre) únicas para filtros de disponibilidad.
  List<OpcionVariante> get tallasOpciones => _opcionesUnicas(
        variantes,
        (VarianteProducto variante) => variante.tallaId,
        (VarianteProducto variante) => variante.tallaNombre,
      );

  /// Colores (id + nombre) únicos para filtros de disponibilidad.
  List<OpcionVariante> get coloresOpciones => _opcionesUnicas(
        variantes,
        (VarianteProducto variante) => variante.colorId,
        (VarianteProducto variante) => variante.colorNombre,
      );

  /// Variantes que exponen al menos un inventario real.
  List<VarianteProducto> get variantesConInventario => variantes
      .where((VarianteProducto variante) => variante.inventarios.isNotEmpty)
      .toList();

  /// Indica si existe alguna combinación real con stock disponible.
  ///
  /// Es la condición para poder agregar el producto al carrito (CU15).
  bool get tieneInventarioConStock =>
      variantes.any((VarianteProducto variante) => variante.tieneStock);
}

/// Opción id + nombre derivada de las variantes de un producto.
class OpcionVariante {
  const OpcionVariante({required this.id, required this.nombre});

  final int id;
  final String nombre;
}

// -----------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// -----------------------------------------------------------------------------

String _categoriaNombre(Object? value) => _nombreDe(value);

String _nombreDe(Object? value) {
  if (value is Map<String, dynamic>) return _toString(value['nombre']);
  if (value is Map) return _toString(value['nombre']);
  return '';
}

/// Nombre de un objeto anidado (`{nombre: ...}`) o el texto tal cual.
///
/// El backend puede exponer `sucursal`/`temporada` como objeto o como texto;
/// ambos casos se resuelven aquí.
String _nombreOTexto(Object? value) {
  if (value == null) return '';
  if (value is Map<String, dynamic>) return _toString(value['nombre']);
  if (value is Map) return _toString(value['nombre']);
  if (value is String) return value.trim();
  return '';
}

/// Dirección de una sucursal anidada, si viene presente.
String _direccionDe(Object? value) {
  if (value is Map<String, dynamic>) return _toString(value['direccion']);
  if (value is Map) return _toString(value['direccion']);
  return '';
}

int? _idDe(Object? value) {
  if (value is Map<String, dynamic>) return _toNullableInt(value['id']);
  if (value is Map) return _toNullableInt(value['id']);
  return null;
}

String? _colorNombre(Object? value) {
  final String nombre = _nombreDe(value);
  return nombre.isEmpty ? null : nombre;
}

List<String> _nombresUnicos(Iterable<String> valores) {
  final Set<String> vistos = <String>{};
  final List<String> resultado = <String>[];
  for (final String valor in valores) {
    final String limpio = valor.trim();
    if (limpio.isEmpty) continue;
    if (vistos.add(limpio)) resultado.add(limpio);
  }
  return resultado;
}

List<OpcionVariante> _opcionesUnicas(
  List<VarianteProducto> variantes,
  int? Function(VarianteProducto) idDe,
  String Function(VarianteProducto) nombreDe,
) {
  final Map<int, String> porId = <int, String>{};
  for (final VarianteProducto variante in variantes) {
    final int? id = idDe(variante);
    final String nombre = nombreDe(variante).trim();
    if (id == null || nombre.isEmpty) continue;
    porId.putIfAbsent(id, () => nombre);
  }
  return porId.entries
      .map((MapEntry<int, String> entry) =>
          OpcionVariante(id: entry.key, nombre: entry.value))
      .toList();
}

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
