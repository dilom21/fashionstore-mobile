import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/reserva_model.dart';
import 'reserva_estado_badge.dart';

/// Tarjeta de una reserva en "Mis reservas".
class ReservaCard extends StatelessWidget {
  const ReservaCard({
    super.key,
    required this.reserva,
    required this.onVerDetalle,
  });

  /// Reserva del listado (datos reales de `GET /reservas`).
  final ReservaResumen reserva;

  /// Abre el detalle de la reserva.
  final VoidCallback onVerDetalle;

  @override
  Widget build(BuildContext context) {
    final String? observacion = reserva.observacionCorta;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reserva.codigo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ReservaEstadoBadge(estado: reserva.estadoReserva, compact: true),
            ],
          ),
          const SizedBox(height: 14),
          _FilaDato(
            icon: Icons.storefront_rounded,
            texto: reserva.sucursalEtiqueta,
          ),
          const SizedBox(height: 8),
          _FilaDato(
            icon: Icons.event_available_rounded,
            texto: 'Reservada el ${formatearFecha(reserva.fechaReserva)}',
          ),
          const SizedBox(height: 8),
          _FilaDato(
            icon: Icons.schedule_rounded,
            texto: 'Atención: ${formatearFechaHora(reserva.fechaAtencion)}',
          ),
          const SizedBox(height: 14),
          _Metricas(
            cantidadLineas: reserva.cantidadLineas,
            cantidadUnidades: reserva.cantidadUnidades,
          ),
          if (observacion != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    observacion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          BotonGradiente(label: 'VER DETALLE', onPressed: onVerDetalle),
        ],
      ),
    );
  }
}

/// Fila con icono + texto dentro de la tarjeta.
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Métricas de prendas y unidades de la reserva.
class _Metricas extends StatelessWidget {
  const _Metricas({
    required this.cantidadLineas,
    required this.cantidadUnidades,
  });

  final int cantidadLineas;
  final int cantidadUnidades;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChipMetrica(
          valor: '$cantidadLineas',
          etiqueta: cantidadLineas == 1 ? 'prenda' : 'prendas',
        ),
        _ChipMetrica(
          valor: '$cantidadUnidades',
          etiqueta: cantidadUnidades == 1 ? 'unidad' : 'unidades',
        ),
      ],
    );
  }
}

/// Chip de métrica (valor + etiqueta).
class _ChipMetrica extends StatelessWidget {
  const _ChipMetrica({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: valor,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            TextSpan(
              text: ' $etiqueta',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
