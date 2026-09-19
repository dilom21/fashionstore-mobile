import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Botón principal con el gradiente de acento de VANTER MEN.
///
/// Se mantiene dentro de `carrito` porque es la primera feature que lo usa;
/// puede promoverse a `core/widgets` cuando otra la necesite.
class BotonGradiente extends StatelessWidget {
  const BotonGradiente({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  /// Texto del botón.
  final String label;

  /// Acción. Si es `null`, el botón queda deshabilitado.
  final VoidCallback? onPressed;

  /// Icono final. Por defecto una flecha.
  final IconData? icon;

  /// Muestra un indicador de carga y deshabilita el botón.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool habilitado = onPressed != null && !isLoading;

    return Opacity(
      opacity: habilitado ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: habilitado ? onPressed : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            icon ?? Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
