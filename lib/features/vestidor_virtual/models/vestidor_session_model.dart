// Modelos de sesión y prueba del Vestidor virtual AR (CU26, parte Josias).
//
// Independientes del motor AR: describen el ciclo de vida de negocio
// (sesión ACTIVA -> FINALIZADA/CANCELADA; prueba INICIADA ->
// COMPLETADA/CANCELADA/ERROR) reportado por el backend FastAPI.
//
// Mapeo JSON snake_case -> Dart camelCase:
//   sesion_id -> sesionId
//   cliente_id -> clienteId
//   fecha_inicio -> fechaInicio
//   fecha_fin -> fechaFin
//   prueba_id -> pruebaId
//   sesion_vestidor_ar_id -> sesionVestidorArId
//   configuracion_id -> configuracionId
//   variante_producto_id -> varianteProductoId

/// Estados válidos de una sesión de vestidor.
abstract final class VestidorSesionEstado {
  static const String activa = 'ACTIVA';
  static const String finalizada = 'FINALIZADA';
  static const String cancelada = 'CANCELADA';

  /// Estados finales aceptados por el backend al finalizar una sesión.
  static const List<String> finales = <String>[finalizada, cancelada];
}

/// Estados válidos de una prueba de prenda.
abstract final class VestidorPruebaEstado {
  static const String iniciada = 'INICIADA';
  static const String completada = 'COMPLETADA';
  static const String cancelada = 'CANCELADA';
  static const String error = 'ERROR';

  /// Estados finales aceptados por el backend al finalizar una prueba.
  static const List<String> finales = <String>[
    completada,
    cancelada,
    error,
  ];
}

/// Sesión de vestidor del CLIENTE autenticado.
class VestidorSesion {
  const VestidorSesion({
    required this.sesionId,
    required this.clienteId,
    required this.estado,
    this.fechaInicio,
    this.fechaFin,
  });

  factory VestidorSesion.fromJson(Map<String, dynamic> json) => VestidorSesion(
    sesionId: _toInt(json['sesion_id']),
    clienteId: _toInt(json['cliente_id']),
    estado: _toString(json['estado']),
    fechaInicio: _toDateTime(json['fecha_inicio']),
    fechaFin: _toDateTime(json['fecha_fin']),
  );

  final int sesionId;
  final int clienteId;
  final String estado;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  bool get estaActiva => estado.toUpperCase() == VestidorSesionEstado.activa;
  bool get estaFinalizada => !estaActiva;
}

/// Prueba de una prenda dentro de una sesión de vestidor.
class VestidorPrueba {
  const VestidorPrueba({
    required this.pruebaId,
    required this.sesionVestidorArId,
    required this.configuracionId,
    required this.estado,
    this.varianteProductoId,
    this.fechaInicio,
    this.fechaFin,
  });

  factory VestidorPrueba.fromJson(Map<String, dynamic> json) => VestidorPrueba(
    pruebaId: _toInt(json['prueba_id']),
    sesionVestidorArId: _toInt(json['sesion_vestidor_ar_id']),
    configuracionId: _toInt(json['configuracion_id']),
    varianteProductoId: _toNullableInt(json['variante_producto_id']),
    estado: _toString(json['estado']),
    fechaInicio: _toDateTime(json['fecha_inicio']),
    fechaFin: _toDateTime(json['fecha_fin']),
  );

  final int pruebaId;
  final int sesionVestidorArId;
  final int configuracionId;
  final int? varianteProductoId;
  final String estado;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  bool get estaIniciada =>
      estado.toUpperCase() == VestidorPruebaEstado.iniciada;
  bool get estaFinalizada => !estaIniciada;
}

// -----------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// -----------------------------------------------------------------------------

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

DateTime? _toDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final String texto = value.toString().trim();
  if (texto.isEmpty) return null;
  return DateTime.tryParse(texto)?.toLocal();
}
