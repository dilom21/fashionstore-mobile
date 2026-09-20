import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../catalogo/widgets/producto_media.dart';
import '../models/carrito_model.dart';
import 'cantidad_stepper.dart';

/// Tarjeta de una prenda dentro del detalle del carrito.
///
/// Consume datos reales del backend: imagen principal, SKU, talla, color,
/// temporada, precio unitario, cantidad y `stock_disponible`.
class CarritoItemCard extends StatelessWidget {
  const CarritoItemCard({
    super.key,
    required this.item,
    required this.onIncrementar,
    required this.onDecrementar,
    required this.onEliminar,
    this.actualizando = false,
    this.eliminando = false,
  });

  /// Línea real del carrito.
  final CarritoItem item;

  /// Aumenta la cantidad en una unidad (PATCH real).
  final VoidCallback onIncrementar;

  /// Disminuye la cantidad en una unidad (PATCH real).
  final VoidCallback onDecrementar;

  /// Elimina la prenda del carrito (DELETE real).
  final VoidCallback onEliminar;

  /// Hay una petición en curso para esta línea.
  final bool actualizando;

  /// Hay un DELETE en curso para esta línea.
  final bool eliminando;

  bool get _ocupado => actualizando || eliminando;

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                width: 88,
                child: ProductImage(
                  url: item.imagenPrincipal,
                  semanticLabel: item.productoNombre,
                  borderRadius: BorderRadius.circular(14),
                  compactFallback: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _DetallePrenda(
                  item: item,
                  onEliminar: onEliminar,
                  eliminando: eliminando,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              CantidadStepper(
                cantidad: item.cantidad,
                cargando: actualizando,
                habilitado: !_ocupado,
                maximo: item.tieneStock ? item.stockDisponible : null,
                onIncrementar: onIncrementar,
                onDecrementar: onDecrementar,
              ),
              const Spacer(),
              _SubtotalLinea(item: item),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nombre, variante, SKU, temporada, precio unitario y stock de la prenda.
class _DetallePrenda extends StatelessWidget {
  const _DetallePrenda({
    required this.item,
    required this.onEliminar,
    required this.eliminando,
  });

  final CarritoItem item;
  final VoidCallback onEliminar;
  final bool eliminando;

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
      'Precio unitario: ${item.precioUnitarioFormateado}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.productoNombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (eliminando)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.textMuted,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: onEliminar,
                tooltip: 'Eliminar prenda',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                color: AppColors.textMuted,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        if (etiquetas.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: etiquetas
                .map((String texto) => _EtiquetaVariante(texto: texto))
                .toList(),
          ),
        ],
        const SizedBox(height: 10),
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
        const SizedBox(height: 8),
        _StockBadge(item: item),
      ],
    );
  }
}

/// Stock disponible reportado por el backend para la línea.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.item});

  final CarritoItem item;

  @override
  Widget build(BuildContext context) {
    final bool hayStock = item.tieneStock;
    final Color color = hayStock ? AppColors.primary : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        hayStock
            ? 'Stock disponible: ${item.stockDisponible}'
            : 'Sin stock disponible',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Chip pequeño con un atributo real de la variante (talla o color).
class _EtiquetaVariante extends StatelessWidget {
  const _EtiquetaVariante({required this.texto});

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

/// Subtotal de la línea, tal como lo reporta el backend.
class _SubtotalLinea extends StatelessWidget {
  const _SubtotalLinea({required this.item});

  final CarritoItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'Subtotal',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.4,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.subtotalFormateado,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
