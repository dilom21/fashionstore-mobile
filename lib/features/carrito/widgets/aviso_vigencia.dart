import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Aviso informativo de vigencia del carrito.
///
/// La expiración la controla el backend; la app solo informa al cliente. Se
/// reutiliza en el listado de carritos y en el detalle.
class AvisoVigencia extends StatelessWidget {
  const AvisoVigencia({super.key});

  /// Texto único del aviso.
  static const String mensaje = 'Los carritos pueden expirar por inactividad.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
