// Modelos reales de la reserva de prendas (CU16).
//
// Mapean el contrato JSON del backend FastAPI (snake_case) a nombres Dart
// idiomáticos (camelCase):
//   reserva_id              -> reservaId
//   carrito_id              -> carritoId
//   sucursal_nombre         -> sucursalNombre
//   fecha_reserva           -> fechaReserva
//   fecha_atencion          -> fechaAtencion
//   cantidad_total_unidades -> cantidadTotalUnidades
//   imagen_principal        -> imagenPrincipal
//
// El parsing es defensivo (igual que catálogo y carrito): los Decimal pueden
// llegar como number o string y las listas como null o vacías.

/// Estados reales que entrega el backend.
///
/// CU16 crea [pendiente] y solo permite cancelar [pendiente] o [confirmada].
/// La expiración ([vencida]) la controla el backend: la app no simula nada.
enum EstadoReserva {
  pendiente('PENDIENTE', 'Pendiente'),
  confirmada('CONFIRMADA', 'Confirmada'),
  atendida('ATENDIDA', 'Atendida'),
  cancelada('CANCELADA', 'Cancelada'),
  vencida('VENCIDA', 'Vencida'),
  desconocido('', 'Sin estado');

  const EstadoReserva(this.codigo, this.etiqueta);

  /// Valor tal como lo envía/espera el backend.
  final String codigo;

  /// Texto para mostrar al cliente.
  final String etiqueta;

  /// Convierte el texto del backend al estado tipado.
  static EstadoReserva desde(String? valor) {
    final String normalizado = (valor ?? '').trim().toUpperCase();
    for (final EstadoReserva estado in values) {
      if (estado.codigo.isNotEmpty && estado.codigo == normalizado) {
        return estado;
      }
    }
    return desconocido;
  }

  /// Solo PENDIENTE y CONFIRMADA pueden cancelarse (CU16).
  bool get esCancelable => this == pendiente || this == confirmada;
}

/// Código visual de la reserva: `44` → `RES-00044`.
///
/// Es solo presentación: nunca se envía al backend.
String codigoReserva(int reservaId) =>
    'RES-${reservaId.toString().padLeft(5, '0')}';

/// Prenda reservada (`ReservaItem` del backend).
class ReservaItem {
  const ReservaItem({
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
  });

  factory ReservaItem.fromJson(Map<String, dynamic> json) => ReservaItem(
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
}

/// Detalle completo de una reserva (`GET /reservas/{reserva_id}`).
class ReservaDetalle {
  const ReservaDetalle({
    required this.reservaId,
    required this.carritoId,
    required this.clienteId,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.fechaReserva,
    required this.fechaAtencion,
    required this.estado,
    required this.observacion,
    required this.items,
    required this.cantidadTotalUnidades,
  });

  factory ReservaDetalle.fromJson(Map<String, dynamic> json) => ReservaDetalle(
    reservaId: _toInt(json['reserva_id']),
    carritoId: _toInt(json['carrito_id']),
    clienteId: _toInt(json['cliente_id']),
    sucursalId: _toInt(json['sucursal_id']),
    sucursalNombre: _toString(json['sucursal_nombre']),
    fechaReserva: _toDateTime(json['fecha_reserva']),
    fechaAtencion: _toDateTime(json['fecha_atencion']),
    estado: _toString(json['estado']),
    observacion: _toNullableString(json['observacion']),
    items: _listaDe(json['items'], ReservaItem.fromJson),
    cantidadTotalUnidades: _toInt(json['cantidad_total_unidades']),
  );

  final int reservaId;
  final int carritoId;
  final int clienteId;
  final int sucursalId;
  final String sucursalNombre;
  final DateTime? fechaReserva;
  final DateTime? fechaAtencion;

  /// Estado tal como lo entrega el backend (`PENDIENTE`, `CONFIRMADA`, ...).
  final String estado;

  final String? observacion;
  final List<ReservaItem> items;
  final int cantidadTotalUnidades;

  /// Código visual (solo presentación).
  String get codigo => codigoReserva(reservaId);

  /// Estado tipado.
  EstadoReserva get estadoReserva => EstadoReserva.desde(estado);

  /// Solo PENDIENTE/CONFIRMADA pueden cancelarse (el backend es la autoridad).
  bool get esCancelable => estadoReserva.esCancelable;

  /// Cantidad de prendas (líneas) distintas.
  int get cantidadLineas => items.length;

  bool get tieneItems => items.isNotEmpty;

  String get sucursalEtiqueta => _etiquetaSucursal(sucursalNombre, sucursalId);
}

/// Reserva del listado (`GET /reservas`).
class ReservaResumen {
  const ReservaResumen({
    required this.reservaId,
    required this.carritoId,
    required this.clienteId,
    required this.sucursalId,
    required this.sucursalNombre,
    required this.fechaReserva,
    required this.fechaAtencion,
    required this.estado,
    required this.observacion,
    required this.cantidadLineas,
    required this.cantidadUnidades,
  });

  factory ReservaResumen.fromJson(Map<String, dynamic> json) => ReservaResumen(
    reservaId: _toInt(json['reserva_id']),
    carritoId: _toInt(json['carrito_id']),
    clienteId: _toInt(json['cliente_id']),
    sucursalId: _toInt(json['sucursal_id']),
    sucursalNombre: _toString(json['sucursal_nombre']),
    fechaReserva: _toDateTime(json['fecha_reserva']),
    fechaAtencion: _toDateTime(json['fecha_atencion']),
    estado: _toString(json['estado']),
    observacion: _toNullableString(json['observacion']),
    cantidadLineas: _toInt(json['cantidad_lineas']),
    cantidadUnidades: _toInt(json['cantidad_unidades']),
  );

  final int reservaId;
  final int carritoId;
  final int clienteId;
  final int sucursalId;
  final String sucursalNombre;
  final DateTime? fechaReserva;
  final DateTime? fechaAtencion;
  final String estado;
  final String? observacion;
  final int cantidadLineas;
  final int cantidadUnidades;

  String get codigo => codigoReserva(reservaId);

  EstadoReserva get estadoReserva => EstadoReserva.desde(estado);

  bool get esCancelable => estadoReserva.esCancelable;

  String get sucursalEtiqueta => _etiquetaSucursal(sucursalNombre, sucursalId);

  /// Observación recortada para las tarjetas del listado.
  String? get observacionCorta {
    final String texto = observacion?.trim() ?? '';
    if (texto.isEmpty) return null;
    return texto.length <= 90 ? texto : '${texto.substring(0, 87)}...';
  }
}

/// Etiqueta de sucursal lista para mostrar.
String _etiquetaSucursal(String nombre, int sucursalId) {
  final String limpio = nombre.trim();
  return limpio.isEmpty ? 'Sucursal $sucursalId' : limpio;
}

/// Respuesta de `GET /reservas`.
class ReservaListaResponse {
  const ReservaListaResponse({
    required this.items,
    required this.totalReservas,
  });

  factory ReservaListaResponse.fromJson(Map<String, dynamic> json) =>
      ReservaListaResponse(
        items: _listaDe(json['items'], ReservaResumen.fromJson),
        totalReservas: _toInt(json['total_reservas']),
      );

  final List<ReservaResumen> items;

  /// Total de reservas reportado por el backend (fuente de verdad).
  final int totalReservas;

  bool get estaVacio => items.isEmpty;
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
