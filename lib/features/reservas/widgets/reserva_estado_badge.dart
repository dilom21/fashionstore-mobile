import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/reserva_model.dart';

/// Badge de estado de una reserva, coherente con VANTER MEN.
///
/// PENDIENTE ámbar · CONFIRMADA azul · ATENDIDA verde · CANCELADA rojo ·
/// VENCIDA gris. No se inventan estados: [EstadoReserva] refleja el backend.
class ReservaEstadoBadge extends StatelessWidget {
  const ReservaEstadoBadge({
    super.key,
    required this.estado,
    this.compact = false,
  });

  /// Estado tipado de la reserva.
  final EstadoReserva estado;

  /// Versión reducida (tarjetas del listado).
  final bool compact;

  static const Color _ambar = Color(0xFFF5B301);
  static const Color _azul = Color(0xFF4C8DFF);
  static const Color _verde = Color(0xFF32C48D);

  Color get _color {
    switch (estado) {
      case EstadoReserva.pendiente:
        return _ambar;
      case EstadoReserva.confirmada:
        return _azul;
      case EstadoReserva.atendida:
        return _verde;
      case EstadoReserva.cancelada:
        return AppColors.error;
      case EstadoReserva.vencida:
      case EstadoReserva.desconocido:
        return AppColors.inactive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        estado.etiqueta.toUpperCase(),
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
