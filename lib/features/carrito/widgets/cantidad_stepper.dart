import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Control para aumentar o disminuir la cantidad de una prenda del carrito.
class CantidadStepper extends StatelessWidget {
  const CantidadStepper({
    super.key,
    required this.cantidad,
    required this.onIncrementar,
    required this.onDecrementar,
    this.minimo = 1,
    this.maximo,
    this.habilitado = true,
    this.cargando = false,
  });

  /// Cantidad actual.
  final int cantidad;

  /// Acción al presionar `+`.
  final VoidCallback onIncrementar;

  /// Acción al presionar `–`.
  final VoidCallback onDecrementar;

  /// Cantidad mínima permitida (debajo de ella, `–` se deshabilita).
  final int minimo;

  /// Cantidad máxima sugerida por el `stock_disponible`.
  ///
  /// El backend sigue siendo la autoridad final del stock: esto solo evita
  /// enviar cantidades obviamente inválidas.
  final int? maximo;

  /// Deshabilita ambos botones (por ejemplo, mientras hay una petición en curso).
  final bool habilitado;

  /// Muestra un indicador discreto en lugar del número.
  final bool cargando;

  bool get _puedeRestar => habilitado && cantidad > minimo;

  bool get _puedeSumar => habilitado && (maximo == null || cantidad < maximo!);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BotonStepper(
            icon: Icons.remove_rounded,
            tooltip: 'Quitar una unidad',
            onTap: _puedeRestar ? onDecrementar : null,
          ),
          SizedBox(
            width: 34,
            child: Center(
              child: cargando
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    )
                  : Text(
                      '$cantidad',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
            ),
          ),
          _BotonStepper(
            icon: Icons.add_rounded,
            tooltip: 'Agregar una unidad',
            onTap: _puedeSumar ? onIncrementar : null,
          ),
        ],
      ),
    );
  }
}

/// Botón cuadrado del stepper (`+` / `–`).
class _BotonStepper extends StatelessWidget {
  const _BotonStepper({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool habilitado = onTap != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          button: true,
          enabled: habilitado,
          label: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: habilitado ? AppColors.textPrimary : AppColors.inactive,
            ),
          ),
        ),
      ),
    );
  }
}
