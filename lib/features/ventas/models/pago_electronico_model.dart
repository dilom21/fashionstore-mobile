// Modelos reales del pago electrónico del CLIENTE (CU22).
//
// Copian exactamente los contratos del backend FastAPI:
//
//   POST /pagos/stripe/intencion          -> IntencionPagoResponse
//   GET  /pagos/stripe/ventas/{id}/estado -> EstadoPagoVentaResponse
//
// El JSON del backend viene en snake_case y se traduce a nombres Dart
// idiomáticos (camelCase):
//   venta_id          -> ventaId
//   pago_id           -> pagoId
//   payment_intent_id -> paymentIntentId
//   client_secret     -> clientSecret
//   estado_pago       -> estadoPago
//   estado_venta      -> estadoVenta
//
// El parsing es defensivo (igual que catálogo, carrito, reservas y CU19): los
// Decimal pueden llegar como number o string, los campos opcionales como null
// y los estados como texto. `client_secret` solo vive en memoria: nunca se
// persiste.

/// Formatea un monto en bolivianos (mismo formato que el resto de la app).
String formatearMontoPago(double monto) => 'Bs ${monto.toStringAsFixed(2)}';

/// Códigos reales de `estado_pago` que devuelve el backend (CU22).
abstract final class EstadoPagoCodigo {
  /// El webhook de Stripe aprobó el pago y la venta fue confirmada.
  static const String aprobado = 'APROBADO';

  /// El pago fue rechazado; la venta sigue PENDIENTE.
  static const String rechazado = 'RECHAZADO';

  /// El intento fue cancelado/anulado; la venta sigue PENDIENTE.
  static const String anulado = 'ANULADO';

  /// El webhook todavía no resolvió el pago.
  static const String pendiente = 'PENDIENTE';

  /// Stripe devolvió el dinero de una venta CANCELADA (compensación).
  static const String reembolsado = 'REEMBOLSADO';
}

/// Códigos reales de `estado_venta` que devuelve el backend (CU22).
abstract final class EstadoVentaCodigo {
  /// Venta creada por CU19, todavía sin pago aprobado.
  static const String pendiente = 'PENDIENTE';

  /// Venta confirmada por `sp_confirmar_venta` tras el webhook.
  static const String completada = 'COMPLETADA';

  /// Variante admitida por el backend para una venta final.
  static const String pagada = 'PAGADA';

  /// La venta no pudo completarse (p. ej. stock insuficiente) y su pago
  /// aprobado se está compensando/reembolsando. Nunca debe volver a cobrarse.
  static const String cancelada = 'CANCELADA';
}

/// Estado visual único de la venta + pago. Centraliza la interpretación para
/// que la UI no vuelva a combinar `estado_venta`/`estado_pago` por su cuenta.
///
/// Regla crítica: `pago = APROBADO` NO es éxito si `venta = CANCELADA`.
enum EstadoVisualPago {
  /// Venta final confirmada por el backend.
  exito,

  /// Pago rechazado; la venta sigue PENDIENTE.
  rechazado,

  /// Pago anulado; la venta sigue PENDIENTE.
  anulado,

  /// El webhook todavía no resolvió el pago.
  enConfirmacion,

  /// Venta CANCELADA con el reembolso pendiente/procesándose.
  reembolsoEnProceso,

  /// Venta CANCELADA y pago devuelto: estado terminal.
  reembolsado,

  /// Combinación no reconocida: estado seguro que nunca habilita un cobro.
  desconocido,
}

/// Respuesta de `POST /pagos/stripe/intencion`.
///
/// `clientSecret` solo se conserva en memoria durante el flujo de pago.
class IntencionPago {
  const IntencionPago({
    required this.ventaId,
    required this.pagoId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.monto,
    required this.moneda,
    required this.estadoPago,
  });

  factory IntencionPago.fromJson(Map<String, dynamic> json) => IntencionPago(
    ventaId: _toInt(json['venta_id']),
    pagoId: _toInt(json['pago_id']),
    paymentIntentId: _toString(json['payment_intent_id']),
    clientSecret: _toNullableString(json['client_secret']),
    monto: _toDouble(json['monto']),
    moneda: _toString(json['moneda']),
    estadoPago: _toString(json['estado_pago']),
  );

  final int ventaId;
  final int pagoId;
  final String paymentIntentId;

  /// Secreto del PaymentIntent. Puede ser `null` si Stripe ya no lo entrega.
  final String? clientSecret;

  /// Monto real derivado por el backend desde la venta (autoridad de negocio).
  final double monto;

  final String moneda;
  final String estadoPago;

  /// El PaymentSheet necesita un `client_secret` no vacío.
  bool get tieneClientSecret => (clientSecret ?? '').trim().isNotEmpty;

  String get montoFormateado => formatearMontoPago(monto);

  String get monedaNormalizada => moneda.trim().toUpperCase();
}

/// Respuesta de `GET /pagos/stripe/ventas/{venta_id}/estado`.
///
/// Es la autoridad final del negocio: solo el webhook backend marca el pago
/// como APROBADO y confirma la venta.
class EstadoPagoVenta {
  const EstadoPagoVenta({
    required this.ventaId,
    required this.estadoVenta,
    required this.pagoId,
    required this.estadoPago,
    required this.paymentIntentId,
    this.compensacionEstado,
  });

  factory EstadoPagoVenta.fromJson(Map<String, dynamic> json) =>
      EstadoPagoVenta(
        ventaId: _toInt(json['venta_id']),
        estadoVenta: _toString(json['estado_venta']),
        pagoId: _toNullableInt(json['pago_id']),
        estadoPago: _toNullableString(json['estado_pago']),
        paymentIntentId: _toNullableString(json['payment_intent_id']),
        compensacionEstado: _toNullableString(json['compensacion_estado']),
      );

  final int ventaId;
  final String estadoVenta;
  final int? pagoId;
  final String? estadoPago;
  final String? paymentIntentId;

  /// Campo ADITIVO/opcional del backend para la compensación de Stripe. Nunca
  /// es la fuente principal: `estadoVenta` + `estadoPago` mandan. Puede faltar.
  final String? compensacionEstado;

  String get estadoVentaNormalizado => estadoVenta.trim().toUpperCase();

  String get estadoPagoNormalizado => (estadoPago ?? '').trim().toUpperCase();

  String get compensacionEstadoNormalizado =>
      (compensacionEstado ?? '').trim().toUpperCase();

  /// El backend aprobó el pago (webhook `payment_intent.succeeded`).
  bool get pagoAprobado => estadoPagoNormalizado == EstadoPagoCodigo.aprobado;

  /// El backend rechazó el pago; la venta sigue PENDIENTE.
  bool get pagoRechazado => estadoPagoNormalizado == EstadoPagoCodigo.rechazado;

  /// El intento fue anulado; la venta sigue PENDIENTE y admite reintento.
  bool get pagoAnulado => estadoPagoNormalizado == EstadoPagoCodigo.anulado;

  /// Stripe ya devolvió el dinero de una venta CANCELADA.
  bool get pagoReembolsado =>
      estadoPagoNormalizado == EstadoPagoCodigo.reembolsado;

  /// Sin pago todavía o explícitamente PENDIENTE: el webhook no resolvió.
  bool get pagoPendiente =>
      estadoPagoNormalizado.isEmpty ||
      estadoPagoNormalizado == EstadoPagoCodigo.pendiente;

  /// La venta alcanzó un estado final (`COMPLETADA` / `PAGADA`).
  bool get ventaFinalizada =>
      estadoVentaNormalizado == EstadoVentaCodigo.completada ||
      estadoVentaNormalizado == EstadoVentaCodigo.pagada;

  /// La venta fue CANCELADA (compensación/reembolso). No debe cobrarse.
  bool get ventaCancelada =>
      estadoVentaNormalizado == EstadoVentaCodigo.cancelada;

  /// `compensacion_estado` reporta el reembolso como completado (ayuda).
  bool get compensacionReembolsada =>
      compensacionEstadoNormalizado == 'REEMBOLSADO' ||
      compensacionEstadoNormalizado == 'REEMBOLSO_COMPLETADO';

  /// Mapper central (única autoridad de interpretación en el cliente).
  ///
  /// Prioridad:
  ///   1. CANCELADA + REEMBOLSADO          -> reembolsado
  ///   2. CANCELADA + APROBADO             -> reembolsoEnProceso
  ///   3. CANCELADA (cualquier otro pago)  -> reembolsoEnProceso (seguro)
  ///   4. COMPLETADA/PAGADA                -> exito
  ///   5. pago RECHAZADO                   -> rechazado
  ///   6. pago ANULADO                     -> anulado
  ///   7. PENDIENTE + PENDIENTE            -> enConfirmacion
  ///   8. combinación desconocida          -> desconocido (seguro)
  EstadoVisualPago get estadoVisual {
    if (ventaCancelada && (pagoReembolsado || compensacionReembolsada)) {
      return EstadoVisualPago.reembolsado;
    }
    if (ventaCancelada) {
      return EstadoVisualPago.reembolsoEnProceso;
    }
    if (ventaFinalizada) {
      return EstadoVisualPago.exito;
    }
    // Pago aprobado pero venta aún no finalizada (`sp_confirmar_venta` en
    // curso): todavía no es éxito y el webhook puede seguir trabajando.
    if (pagoAprobado) {
      return EstadoVisualPago.enConfirmacion;
    }
    if (pagoRechazado) {
      return EstadoVisualPago.rechazado;
    }
    if (pagoAnulado) {
      return EstadoVisualPago.anulado;
    }
    if (estadoVentaNormalizado == EstadoVentaCodigo.pendiente &&
        (pagoPendiente)) {
      return EstadoVisualPago.enConfirmacion;
    }
    return EstadoVisualPago.desconocido;
  }

  /// Única condición válida para mostrar "Compra completada".
  bool get compraCompletada => estadoVisual == EstadoVisualPago.exito;

  /// Estado terminal que detiene el polling. Solo la espera normal sigue.
  bool get esTerminal => estadoVisual != EstadoVisualPago.enConfirmacion;
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
