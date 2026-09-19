import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';

/// Estado vacío de "Mis reservas" (el cliente no tiene reservas).
class ReservaEmptyState extends StatelessWidget {
  const ReservaEmptyState({super.key, this.onVerCarrito});

  /// Lleva a la pestaña Carrito. Si es `null`, el botón se omite.
  final VoidCallback? onVerCarrito;

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
                Icons.event_available_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Todavía no tienes reservas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Reserva prendas desde uno de tus carritos activos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            if (onVerCarrito != null) ...[
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: BotonGradiente(
                  label: 'VER CARRITO',
                  onPressed: onVerCarrito,
                  icon: Icons.shopping_bag_outlined,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
