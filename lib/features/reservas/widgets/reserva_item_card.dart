import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../catalogo/widgets/producto_media.dart';
import '../models/reserva_model.dart';

/// Tarjeta READ-ONLY de una prenda reservada (o por reservar).
///
/// No incluye controles de cantidad: una reserva es inmutable respecto a su
/// contenido. Reutiliza [ProductImage] del catálogo para la imagen real.
class ReservaItemCard extends StatelessWidget {
  const ReservaItemCard({
    super.key,
    required this.item,
    this.cantidadEtiqueta = 'Cantidad',
  });

  /// Prenda reservada.
  final ReservaItem item;

  /// Etiqueta de la cantidad (por ejemplo `Cantidad`).
  final String cantidadEtiqueta;

  @override
  Widget build(BuildContext context) {
    final List<String> etiquetas = <String>[
      if (item.tallaNombre.trim().isNotEmpty) 'Talla ${item.tallaNombre}',
      if (item.colorNombre.trim().isNotEmpty) item.colorNombre,
    ];
    final List<String> detalles = <String>[
      if (item.sku.trim().isNotEmpty) 'SKU: ${item.sku}',
      if (item.temporadaNombre.trim().isNotEmpty)
        'Temporada: ${item.temporadaNombre}',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            width: 74,
            child: ProductImage(
              url: item.imagenPrincipal,
              semanticLabel: item.productoNombre,
              borderRadius: BorderRadius.circular(12),
              compactFallback: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productoNombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (etiquetas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: etiquetas
                        .map((String texto) => _Etiqueta(texto: texto))
                        .toList(),
                  ),
                ],
                if (detalles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...detalles.map(
                    (String texto) => Text(
                      texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '$cantidadEtiqueta: ${item.cantidad}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip pequeño con un atributo de la variante (talla o color).
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
