import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatters.dart';
import '../../carrito/widgets/boton_gradiente.dart';
import '../models/historial_compras_model.dart';
import 'historial_estado_badge.dart';

/// Tarjeta del listado de historial de compras (CU24) para móvil.
///
/// Solo muestra los campos reales del listado del backend:
/// `venta_id`, `fecha_hora`, `canal`, `estado`, `total`, `sucursal_nombre`,
/// `cantidad_total_unidades` y `cantidad_lineas`. El listado de CU24 no
/// devuelve imágenes, ni método de pago, ni cliente, ni estadísticas.
class HistorialCompraCard extends StatelessWidget {
  /// Crea la tarjeta de una compra del historial.
  const HistorialCompraCard({
    super.key,
    required this.compra,
    this.onVerDetalle,
    this.onVerComprobante,
  });

  /// Fila del listado que devuelve el backend.
  final HistorialCompraResumen compra;

  /// Acción para abrir el detalle. `null` deshabilita el botón.
  final VoidCallback? onVerDetalle;

  /// Acción para abrir el comprobante (CU23). `null` oculta el botón: solo las
  /// compras COMPLETADA tienen comprobante (regla de CU23, no de CU24).
  final VoidCallback? onVerComprobante;

  @override
  Widget build(BuildContext context) {
    final bool mostrarComprobante =
        compra.permiteComprobante && onVerComprobante != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onVerDetalle,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        compra.codigo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    HistorialEstadoBadge(estado: compra.estado),
                  ],
                ),
                const SizedBox(height: 12),
                _FilaDato(
                  icono: Icons.event_rounded,
                  texto: formatearFecha(compra.fechaHora),
                ),
                const SizedBox(height: 6),
                _FilaDato(
                  icono: _iconoCanal(compra.canalHistorial),
                  texto: compra.canalEtiqueta,
                ),
                const SizedBox(height: 6),
                _FilaDato(
                  icono: Icons.storefront_rounded,
                  texto: compra.sucursalNombre.trim().isEmpty
                      ? 'Sucursal no disponible'
                      : compra.sucursalNombre,
                ),
                const SizedBox(height: 6),
                _FilaDato(
                  icono: Icons.inventory_2_rounded,
                  texto: _resumenUnidades,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(height: 1, color: AppColors.border),
                ),
                Row(
                  children: <Widget>[
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        compra.totalFormateado,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (mostrarComprobante) ...<Widget>[
                  BotonGradiente(
                    label: 'VER COMPROBANTE',
                    icon: Icons.receipt_long_rounded,
                    onPressed: onVerComprobante,
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: onVerDetalle,
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    'VER DETALLE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `N productos · M unidades` con el singular correcto.
  String get _resumenUnidades {
    final int lineas = compra.cantidadLineas;
    final int unidades = compra.cantidadTotalUnidades;
    if (lineas <= 0 && unidades <= 0) return 'Sin productos registrados';

    final String producto = lineas == 1 ? 'producto' : 'productos';
    final String unidad = unidades == 1 ? 'unidad' : 'unidades';
    return '$lineas $producto · $unidades $unidad';
  }

  /// Icono del canal cuando el backend entrega un valor conocido.
  static IconData _iconoCanal(CanalHistorial? canal) {
    switch (canal) {
      case CanalHistorial.web:
        return Icons.language_rounded;
      case CanalHistorial.movil:
        return Icons.smartphone_rounded;
      case CanalHistorial.presencial:
        return Icons.store_rounded;
      case null:
        return Icons.devices_rounded;
    }
  }
}

/// Línea compacta `icono + texto` usada dentro de las tarjetas del historial.
class _FilaDato extends StatelessWidget {
  const _FilaDato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icono, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
