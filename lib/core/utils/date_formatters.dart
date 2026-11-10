// Helpers reutilizables de formato de fecha/hora de VANTER MEN.
//
// Centralizan la presentación de los `datetime` ISO que entrega el backend
// (`dd/MM/yyyy` y `dd/MM/yyyy HH:mm`) para no mostrar ISO crudo, y la
// construcción del ISO local que espera la API en `fecha_atencion`.

/// Formatea una fecha como `dd/MM/yyyy`.
String formatearFecha(DateTime? fecha) {
  if (fecha == null) return 'sin registro';
  final DateTime local = fecha.toLocal();
  return '${_dosDigitos(local.day)}/${_dosDigitos(local.month)}/${local.year}';
}

/// Formatea fecha y hora como `dd/MM/yyyy HH:mm`.
String formatearFechaHora(DateTime? fecha) {
  if (fecha == null) return 'sin registro';
  return '${formatearFecha(fecha)} ${formatearHora(fecha)}';
}

/// Formatea solo la hora como `HH:mm`.
String formatearHora(DateTime? fecha) {
  if (fecha == null) return '--:--';
  final DateTime local = fecha.toLocal();
  return '${_dosDigitos(local.hour)}:${_dosDigitos(local.minute)}';
}

/// Construye el ISO 8601 local que consume el backend.
///
/// Se arma desde los componentes locales (sin zona horaria) porque la fecha de
/// atención es una hora de sucursal. Ejemplo: `2026-09-25T15:30:00`.
String formatearIsoLocal(DateTime fecha) {
  final DateTime local = fecha.toLocal();
  return '${local.year.toString().padLeft(4, '0')}'
      '-${_dosDigitos(local.month)}'
      '-${_dosDigitos(local.day)}'
      'T${_dosDigitos(local.hour)}'
      ':${_dosDigitos(local.minute)}'
      ':${_dosDigitos(local.second)}';
}

/// Construye el ISO 8601 con zona horaria explícita.
///
/// El contrato SaaS de reservas exige un `datetime` aware; Pydantic rechaza
/// (422) un valor sin zona. Se envía el offset local, por ejemplo
/// `2026-11-10T10:30:00-04:00`.
String formatearIsoConZona(DateTime fecha) {
  final DateTime local = fecha.toLocal();
  final Duration offset = local.timeZoneOffset;
  final String signo = offset.isNegative ? '-' : '+';
  final int minutos = offset.inMinutes.abs();
  final String zona =
      '$signo${_dosDigitos(minutos ~/ 60)}:${_dosDigitos(minutos % 60)}';
  return '${formatearIsoLocal(local)}$zona';
}

String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');
