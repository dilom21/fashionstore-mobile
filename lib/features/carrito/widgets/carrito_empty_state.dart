import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'boton_gradiente.dart';

/// Estado vacío del carrito: el cliente no tiene carritos activos.
class CarritoEmptyState extends StatelessWidget {
  const CarritoEmptyState({super.key, this.onExplorarCatalogo});

  /// Lleva al cliente a la pestaña Catálogo. Si es `null`, el botón se omite.
  final VoidCallback? onExplorarCatalogo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 34,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Tu carrito está vacío',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Explora el catálogo y agrega prendas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            if (onExplorarCatalogo != null) ...[
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: BotonGradiente(
                  label: 'EXPLORAR CATÁLOGO',
                  onPressed: onExplorarCatalogo,
                  icon: Icons.grid_view_rounded,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
