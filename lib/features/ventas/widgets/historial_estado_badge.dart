import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/historial_compras_model.dart';

/// Etiqueta de estado de una compra del historial (CU24).
///
/// El texto siempre está visible: el color es apoyo visual, nunca el único
/// indicador. Solo se representan los estados reales del backend
/// (`COMPLETADA`, `CANCELADA`, `REEMBOLSADA`); si llegara un valor distinto se
/// muestra tal cual con un color neutro, sin inventar estados.
class HistorialEstadoBadge extends StatelessWidget {
  /// Crea la etiqueta a partir del estado tal como lo entrega el backend.
  const HistorialEstadoBadge({super.key, required this.estado});

  /// Valor de `estado` recibido del backend.
  final String estado;

  /// Verde de confirmación: `AppColors` no define colores semánticos de éxito,
  /// así que se declara aquí para no alterar la paleta compartida.
  static const Color _verdeCompletada = Color(0xFF34D399);

  @override
  Widget build(BuildContext context) {
    final EstadoHistorial? valor = EstadoHistorial.desdeCodigo(estado);

    final Color color;
    switch (valor) {
      case EstadoHistorial.completada:
        color = _verdeCompletada;
      case EstadoHistorial.cancelada:
        color = AppColors.error;
      case EstadoHistorial.reembolsada:
        color = AppColors.secondary;
      case null:
        color = AppColors.textMuted;
    }

    final String texto = valor?.etiqueta ?? _textoDeRespaldo();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }

  String _textoDeRespaldo() {
    final String limpio = estado.trim();
    return limpio.isEmpty ? 'SIN ESTADO' : limpio.toUpperCase();
  }
}
