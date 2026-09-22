// Modelos reales del comprobante de venta del CLIENTE (CU23).
//
// Copian exactamente el contrato del backend FastAPI:
//
//   GET /ventas/{venta_id}/comprobante -> ComprobanteVentaResponse
//
//   app/modules/ventas/schemas/comprobante.py
//
// El comprobante NO es una entidad persistida: es el DTO que resulta de
// consultar venta + detalle_venta + pago + cliente + empleado + sucursal. No
// existe tabla `comprobante`/`factura`, ni numero_factura, ni NIT de empresa,
// ni impuestos/IVA/descuentos: por eso aquí tampoco se inventan.
//
// El JSON viene en snake_case y se traduce a camelCase:
//   venta_id                -> ventaId
//   fecha_hora              -> fechaHora
//   estado_venta            -> estadoVenta
//   carrito_id / reserva_id -> carritoId / reservaId
//   cantidad_total_unidades -> cantidadTotalUnidades
//   precio_unitario         -> precioUnitario
//   subtotal_linea          -> subtotalLinea
//
// El parsing es defensivo (igual que catálogo, carrito, reservas, CU19 y CU22):
// los Decimal llegan como number o string y los campos opcionales como null.

/// Código visual de la venta para presentación: `VTA-00535`.
///
/// Es SOLO presentación: el backend devuelve `venta_id` y no existe otro
/// identificador de venta.
String codigoVenta(int ventaId) => 'VTA-${ventaId.toString().padLeft(5, '0')}';

/// Formatea un monto en bolivianos (mismo formato que el resto de la app).
String formatearMontoBs(double monto) => 'Bs ${monto.toStringAsFixed(2)}';

/// Cliente de la venta. `null` cuando la venta es anónima (presencial).
class ComprobanteCliente {
  const ComprobanteCliente({
    required this.id,
    required this.nombre,
    required this.apellido,
    this.ci,
    this.telefono,
  });

  final int id;
  final String nombre;
  final String apellido;
  final String? ci;
  final String? telefono;

  /// Nombre y apellido tal como los devuelve el backend (sin inventar nada).
  String get nombreCompleto => '$nombre $apellido'.trim();

  static ComprobanteCliente? desdeJson(Object? valor) {
    if (valor is! Map) return null;
    return ComprobanteCliente(
      id: _toInt(valor['id']),
      nombre: _toString(valor['nombre']),
      apellido: _toString(valor['apellido']),
      ci: _toNullableString(valor['ci']),
      telefono: _toNullableString(valor['telefono']),
    );
  }
}

/// Empleado que registró la venta. `null` en las ventas WEB/MOVIL.
class ComprobanteEmpleado {
  const ComprobanteEmpleado({
    required this.id,
    required this.nombres,
    required this.apellidos,
  });

  final int id;
  final String nombres;
  final String apellidos;

  String get nombreCompleto => '$nombres $apellidos'.trim();

  static ComprobanteEmpleado? desdeJson(Object? valor) {
    if (valor is! Map) return null;
    return ComprobanteEmpleado(
      id: _toInt(valor['id']),
      nombres: _toString(valor['nombres']),
      apellidos: _toString(valor['apellidos']),
    );
  }
}

/// Sucursal donde se registró la venta.
class ComprobanteSucursal {
  const ComprobanteSucursal({
    required this.id,
    required this.nombre,
    required this.direccion,
    this.telefono,
  });

  final int id;
  final String nombre;
  final String direccion;
  final String? telefono;

  /// Instancia vacía: si el backend no enviara la sucursal, la UI omite las
  /// filas vacías en lugar de mostrar datos inventados.
  static const ComprobanteSucursal vacia = ComprobanteSucursal(
    id: 0,
    nombre: '',
    direccion: '',
  );

  static ComprobanteSucursal desdeJson(Object? valor) {
    if (valor is! Map) return vacia;
    return ComprobanteSucursal(
      id: _toInt(valor['id']),
      nombre: _toString(valor['nombre']),
      direccion: _toString(valor['direccion']),
      telefono: _toNullableString(valor['telefono']),
    );
  }
}

/// Pago APROBADO que respalda el comprobante.
///
/// Nunca contiene datos de tarjeta: Stripe no almacena PAN/CVC y CU23 no los
/// recupera.
class ComprobantePago {
  const ComprobantePago({
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

  static ComprobantePago desdeJson(Object? valor) {
    final Map<Object?, Object?> datos = valor is Map
        ? valor
        : <Object?, Object?>{};
    return ComprobantePago(
      pagoId: _toInt(datos['pago_id']),
      fechaHora: _toNullableDate(datos['fecha_hora']),
      monto: _toDouble(datos['monto']),
      metodo: _toString(datos['metodo']),
      estado: _toString(datos['estado']),
      referenciaTransaccion: _toNullableString(datos['referencia_transaccion']),
      pasarela: _toNullableString(datos['pasarela']),
    );
  }
}

/// Línea del comprobante (una por `detalle_venta`).
class ComprobanteVentaItem {
  const ComprobanteVentaItem({
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
  String get subtotalFormateado => formatearMontoBs(subtotalLinea);

  /// Variante legible: `M · Negro` (omite lo que no exista).
  String get varianteTexto {
    final List<String> partes = <String>[
      if (tallaNombre.trim().isNotEmpty) tallaNombre.trim(),
      if (colorNombre.trim().isNotEmpty) colorNombre.trim(),
    ];
    return partes.join(' · ');
  }

  static ComprobanteVentaItem desdeJson(Object? valor) {
    final Map<Object?, Object?> datos = valor is Map
        ? valor
        : <Object?, Object?>{};
    return ComprobanteVentaItem(
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

/// Comprobante de venta completo (DTO de solo lectura, sin persistencia).
class ComprobanteVenta {
  const ComprobanteVenta({
    required this.ventaId,
    this.fechaHora,
    required this.canal,
    required this.estadoVenta,
    required this.total,
    this.carritoId,
    this.reservaId,
    this.cliente,
    this.empleado,
    required this.sucursal,
    required this.pago,
    required this.items,
    required this.cantidadTotalUnidades,
  });

  final int ventaId;
  final DateTime? fechaHora;
  final String canal;
  final String estadoVenta;
  final double total;
  final int? carritoId;
  final int? reservaId;
  final ComprobanteCliente? cliente;
  final ComprobanteEmpleado? empleado;
  final ComprobanteSucursal sucursal;
  final ComprobantePago pago;
  final List<ComprobanteVentaItem> items;
  final int cantidadTotalUnidades;

  /// Código visual `VTA-00535` (solo presentación).
  String get codigo => codigoVenta(ventaId);

  /// Total tal como lo devuelve el backend (autoridad del monto).
  String get totalFormateado => formatearMontoBs(total);

  /// Suma de las líneas: solo para verificación visual, NO reemplaza `total`.
  double get sumaLineas => items.fold<double>(
    0,
    (double acumulado, ComprobanteVentaItem item) =>
        acumulado + item.subtotalLinea,
  );

  static ComprobanteVenta desdeJson(Map<String, dynamic> json) {
    final Object? itemsCrudos = json['items'];
    final List<ComprobanteVentaItem> items = <ComprobanteVentaItem>[
      if (itemsCrudos is List)
        for (final Object? item in itemsCrudos)
          ComprobanteVentaItem.desdeJson(item),
    ];

    return ComprobanteVenta(
      ventaId: _toInt(json['venta_id']),
      fechaHora: _toNullableDate(json['fecha_hora']),
      canal: _toString(json['canal']),
      estadoVenta: _toString(json['estado_venta']),
      total: _toDouble(json['total']),
      carritoId: _toNullableInt(json['carrito_id']),
      reservaId: _toNullableInt(json['reserva_id']),
      cliente: ComprobanteCliente.desdeJson(json['cliente']),
      empleado: ComprobanteEmpleado.desdeJson(json['empleado']),
      sucursal: ComprobanteSucursal.desdeJson(json['sucursal']),
      pago: ComprobantePago.desdeJson(json['pago']),
      items: items,
      cantidadTotalUnidades: _toInt(json['cantidad_total_unidades']),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// ---------------------------------------------------------------------------

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

/// Acepta el ISO que envía FastAPI (`datetime` naive o con offset horario).
DateTime? _toNullableDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) {
    final String limpio = value.trim();
    if (limpio.isEmpty) return null;
    return DateTime.tryParse(limpio);
  }
  return null;
}
