// Modelos reales del historial de compras del CLIENTE (CU24).
//
// Copian exactamente el contrato del backend FastAPI:
//
//   GET /ventas/historial              -> HistorialComprasResponse
//   GET /ventas/historial/{venta_id}   -> HistorialCompraDetalleResponse
//
//   app/modules/ventas/schemas/historial.py
//
// El historial NO es una entidad persistida: se construye desde venta +
// detalle_venta + pago + sucursal. No hay imágenes, ni cliente, ni cajero, ni
// estadísticas globales en el listado: por eso aquí tampoco se inventan.
//
// `codigoVenta` y `formatearMontoBs` se reutilizan de CU23 (no se duplican).
//
// El JSON viene en snake_case y se traduce a camelCase:
//   venta_id / fecha_hora / sucursal_id / sucursal_nombre
//   cantidad_total_unidades / cantidad_lineas / tamano_pagina
//   total_registros / total_paginas / precio_unitario / subtotal_linea

import 'comprobante_venta_model.dart' show codigoVenta, formatearMontoBs;

/// Estados que forman parte del historial (CK `venta_estado`).
///
/// `PENDIENTE` y `PAGADA` quedan fuera: todavía no son compras históricas.
enum EstadoHistorial {
  completada('COMPLETADA', 'COMPLETADA'),
  cancelada('CANCELADA', 'CANCELADA'),
  reembolsada('REEMBOLSADA', 'REEMBOLSADA');

  const EstadoHistorial(this.codigo, this.etiqueta);

  /// Valor exacto que espera el backend en `?estado=`.
  final String codigo;

  /// Texto para la interfaz.
  final String etiqueta;

  /// Estado a partir del texto del backend; `null` si no es del historial.
  static EstadoHistorial? desdeCodigo(Object? valor) {
    final String texto = valor is String ? valor.trim().toUpperCase() : '';
    for (final EstadoHistorial estado in EstadoHistorial.values) {
      if (estado.codigo == texto) return estado;
    }
    return null;
  }
}

/// Canales reales de `venta.canal` (CK `venta_canal`).
enum CanalHistorial {
  web('WEB', 'WEB'),
  movil('MOVIL', 'MÓVIL'),
  presencial('PRESENCIAL', 'PRESENCIAL');

  const CanalHistorial(this.codigo, this.etiqueta);

  /// Valor exacto que espera el backend en `?canal=`.
  final String codigo;

  /// Texto para la interfaz.
  final String etiqueta;

  static CanalHistorial? desdeCodigo(Object? valor) {
    final String texto = valor is String ? valor.trim().toUpperCase() : '';
    for (final CanalHistorial canal in CanalHistorial.values) {
      if (canal.codigo == texto) return canal;
    }
    return null;
  }
}

/// Fila del listado: venta + sucursal + agregados de sus líneas.
class HistorialCompraResumen {
  const HistorialCompraResumen({
    required this.ventaId,
    this.fechaHora,
    required this.canal,
    required this.estado,
    required this.total,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.cantidadTotalUnidades,
    required this.cantidadLineas,
  });

  final int ventaId;
  final DateTime? fechaHora;
  final String canal;
  final String estado;
  final double total;
  final int sucursalId;
  final String sucursalNombre;
  final int cantidadTotalUnidades;
  final int cantidadLineas;

  /// Código visual `VTA-00557` (solo presentación).
  String get codigo => codigoVenta(ventaId);

  String get totalFormateado => formatearMontoBs(total);

  /// `true` cuando CU23 puede emitir el comprobante de esta compra.
  bool get permiteComprobante =>
      estado.trim().toUpperCase() == EstadoHistorial.completada.codigo;

  EstadoHistorial? get estadoHistorial => EstadoHistorial.desdeCodigo(estado);

  CanalHistorial? get canalHistorial => CanalHistorial.desdeCodigo(canal);

  /// Texto de canal listo para mostrar (sin inventar valores).
  String get canalEtiqueta {
    final CanalHistorial? valor = canalHistorial;
    if (valor != null) return valor.etiqueta;
    final String limpio = canal.trim();
    return limpio.isEmpty ? 'No disponible' : limpio;
  }

  static HistorialCompraResumen desdeJson(Object? valor) {
    final Map<Object?, Object?> datos =
        valor is Map ? valor : <Object?, Object?>{};
    return HistorialCompraResumen(
      ventaId: _toInt(datos['venta_id']),
      fechaHora: _toNullableDate(datos['fecha_hora']),
      canal: _toString(datos['canal']),
      estado: _toString(datos['estado']),
      total: _toDouble(datos['total']),
      sucursalId: _toInt(datos['sucursal_id']),
      sucursalNombre: _toString(datos['sucursal_nombre']),
      cantidadTotalUnidades: _toInt(datos['cantidad_total_unidades']),
      cantidadLineas: _toInt(datos['cantidad_lineas']),
    );
  }
}

/// Historial paginado que devuelve `GET /ventas/historial`.
class HistorialComprasResponse {
  const HistorialComprasResponse({
    required this.items,
    required this.pagina,
    required this.tamanoPagina,
    required this.totalRegistros,
    required this.totalPaginas,
  });

  final List<HistorialCompraResumen> items;
  final int pagina;
  final int tamanoPagina;
  final int totalRegistros;
  final int totalPaginas;

  bool get hayAnterior => pagina > 1;

  bool get haySiguiente => totalPaginas > 0 && pagina < totalPaginas;

  static HistorialComprasResponse desdeJson(Map<String, dynamic> json) {
    final Object? itemsCrudos = json['items'];
    final List<HistorialCompraResumen> items = <HistorialCompraResumen>[
      if (itemsCrudos is List)
        for (final Object? item in itemsCrudos)
          HistorialCompraResumen.desdeJson(item),
    ];

    return HistorialComprasResponse(
      items: items,
      pagina: _toInt(json['pagina']),
      tamanoPagina: _toInt(json['tamano_pagina']),
      totalRegistros: _toInt(json['total_registros']),
      totalPaginas: _toInt(json['total_paginas']),
    );
  }

  /// Estado inicial de la pantalla, antes de la primera consulta real.
  static const HistorialComprasResponse vacio = HistorialComprasResponse(
    items: <HistorialCompraResumen>[],
    pagina: 1,
    tamanoPagina: 20,
    totalRegistros: 0,
    totalPaginas: 0,
  );
}

/// Sucursal que realizó la venta (`sucursal` del detalle).
class HistorialCompraSucursal {
  const HistorialCompraSucursal({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.telefono,
  });

  final int id;
  final String nombre;
  final String direccion;
  final String? telefono;

  static HistorialCompraSucursal desdeJson(Object? valor) {
    final Map<Object?, Object?> datos =
        valor is Map ? valor : <Object?, Object?>{};
    return HistorialCompraSucursal(
      id: _toInt(datos['id']),
      nombre: _toString(datos['nombre']),
      direccion: _toString(datos['direccion']),
      telefono: _toNullableString(datos['telefono']),
    );
  }
}

/// Pago más relevante de la venta (nunca datos de tarjeta).
class HistorialCompraPago {
  const HistorialCompraPago({
    required this.pagoId,
    this.fechaHora,
    required this.monto,
    required this.metodo,
    required this.estado,
    this.referenciaTransaccion,
    this.pasarela,
  });

  final int pagoId;
  final DateTime? fechaHora;
  final double monto;
  final String metodo;
  final String estado;
  final String? referenciaTransaccion;
  final String? pasarela;

  String get montoFormateado => formatearMontoBs(monto);

  /// `null` cuando el backend no informa pago para la venta.
  static HistorialCompraPago? desdeJson(Object? valor) {
    if (valor is! Map) return null;
    return HistorialCompraPago(
      pagoId: _toInt(valor['pago_id']),
      fechaHora: _toNullableDate(valor['fecha_hora']),
      monto: _toDouble(valor['monto']),
      metodo: _toString(valor['metodo']),
      estado: _toString(valor['estado']),
      referenciaTransaccion: _toNullableString(valor['referencia_transaccion']),
      pasarela: _toNullableString(valor['pasarela']),
    );
  }
}

/// Línea del detalle construida desde `detalle_venta`.
class HistorialCompraItem {
  const HistorialCompraItem({
    required this.detalleVentaId,
    required this.inventarioId,
    required this.productoId,
    required this.productoNombre,
    required this.varianteProductoId,
    required this.sku,
    required this.tallaNombre,
    required this.colorNombre,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotalLinea,
  });

  final int detalleVentaId;
  final int inventarioId;
  final int productoId;
  final String productoNombre;
  final int varianteProductoId;
  final String sku;
  final String tallaNombre;
  final String colorNombre;
  final int cantidad;
  final double precioUnitario;
  final double subtotalLinea;

  String get precioUnitarioFormateado => formatearMontoBs(precioUnitario);

  String get subtotalLineaFormateado => formatearMontoBs(subtotalLinea);

  /// `M · Negro`, solo con las partes informadas.
  String get varianteEtiqueta {
    final List<String> partes = <String>[
      if (tallaNombre.trim().isNotEmpty) tallaNombre.trim(),
      if (colorNombre.trim().isNotEmpty) colorNombre.trim(),
    ];
    return partes.join(' · ');
  }

  static HistorialCompraItem desdeJson(Object? valor) {
    final Map<Object?, Object?> datos =
        valor is Map ? valor : <Object?, Object?>{};
    return HistorialCompraItem(
      detalleVentaId: _toInt(datos['detalle_venta_id']),
      inventarioId: _toInt(datos['inventario_id']),
      productoId: _toInt(datos['producto_id']),
      productoNombre: _toString(datos['producto_nombre']),
      varianteProductoId: _toInt(datos['variante_producto_id']),
      sku: _toString(datos['sku']),
      tallaNombre: _toString(datos['talla_nombre']),
      colorNombre: _toString(datos['color_nombre']),
      cantidad: _toInt(datos['cantidad']),
      precioUnitario: _toDouble(datos['precio_unitario']),
      subtotalLinea: _toDouble(datos['subtotal_linea']),
    );
  }
}

/// Detalle completo de una compra del cliente autenticado.
class HistorialCompraDetalle {
  const HistorialCompraDetalle({
    required this.ventaId,
    this.fechaHora,
    required this.canal,
    required this.estado,
    required this.total,
    this.carritoId,
    this.reservaId,
    required this.sucursal,
    this.pago,
    required this.items,
    required this.cantidadTotalUnidades,
  });

  final int ventaId;
  final DateTime? fechaHora;
  final String canal;
  final String estado;
  final double total;
  final int? carritoId;
  final int? reservaId;
  final HistorialCompraSucursal sucursal;
  final HistorialCompraPago? pago;
  final List<HistorialCompraItem> items;
  final int cantidadTotalUnidades;

  /// Código visual `VTA-00557` (solo presentación).
  String get codigo => codigoVenta(ventaId);

  String get totalFormateado => formatearMontoBs(total);

  /// `true` cuando CU23 puede emitir el comprobante de esta compra.
  bool get permiteComprobante =>
      estado.trim().toUpperCase() == EstadoHistorial.completada.codigo;

  EstadoHistorial? get estadoHistorial => EstadoHistorial.desdeCodigo(estado);

  String get canalEtiqueta {
    final CanalHistorial? valor = CanalHistorial.desdeCodigo(canal);
    if (valor != null) return valor.etiqueta;
    final String limpio = canal.trim();
    return limpio.isEmpty ? 'No disponible' : limpio;
  }

  static HistorialCompraDetalle desdeJson(Map<String, dynamic> json) {
    final Object? itemsCrudos = json['items'];
    final List<HistorialCompraItem> items = <HistorialCompraItem>[
      if (itemsCrudos is List)
        for (final Object? item in itemsCrudos)
          HistorialCompraItem.desdeJson(item),
    ];

    return HistorialCompraDetalle(
      ventaId: _toInt(json['venta_id']),
      fechaHora: _toNullableDate(json['fecha_hora']),
      canal: _toString(json['canal']),
      estado: _toString(json['estado']),
      total: _toDouble(json['total']),
      carritoId: _toNullableInt(json['carrito_id']),
      reservaId: _toNullableInt(json['reserva_id']),
      sucursal: HistorialCompraSucursal.desdeJson(json['sucursal']),
      pago: HistorialCompraPago.desdeJson(json['pago']),
      items: items,
      cantidadTotalUnidades: _toInt(json['cantidad_total_unidades']),
    );
  }
}

// ---------------------------------------------------------------------------
// Parsing defensivo: el backend usa Decimal y puede entregar num o string.
// ---------------------------------------------------------------------------

/// Convierte a `int` cualquier valor numérico o texto del backend.
int _toInt(Object? valor) => _toNullableInt(valor) ?? 0;

int? _toNullableInt(Object? valor) {
  if (valor == null) return null;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  if (valor is String) {
    final num? parseado = num.tryParse(valor.trim());
    return parseado?.toInt();
  }
  return null;
}

/// Convierte a `double` cualquier valor numérico o texto del backend.
double _toDouble(Object? valor) {
  if (valor == null) return 0;
  if (valor is double) return valor;
  if (valor is num) return valor.toDouble();
  if (valor is String) {
    final num? parseado = num.tryParse(valor.trim());
    return parseado?.toDouble() ?? 0;
  }
  return 0;
}

String _toString(Object? valor) {
  if (valor == null) return '';
  if (valor is String) return valor;
  return valor.toString();
}

/// Texto opcional: `null` cuando el backend informa `null` o vacío.
String? _toNullableString(Object? valor) {
  if (valor == null) return null;
  final String texto = valor is String ? valor : valor.toString();
  return texto.trim().isEmpty ? null : texto;
}

/// Fecha ISO del backend; `null` si no se puede interpretar.
DateTime? _toNullableDate(Object? valor) {
  if (valor is DateTime) return valor;
  if (valor is String) {
    final String limpio = valor.trim();
    if (limpio.isEmpty) return null;
    return DateTime.tryParse(limpio);
  }
  return null;
}
