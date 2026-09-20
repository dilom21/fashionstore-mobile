import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/carrito_model.dart';
import 'boton_gradiente.dart';

/// Tarjeta de un carrito activo en la pantalla "Tus carritos".
///
/// Muestra la sucursal, sus métricas reales (líneas, unidades y subtotal) y las
/// acciones principales: ver el detalle o eliminar el carrito.
class CarritoCard extends StatelessWidget {
  const CarritoCard({
    super.key,
    required this.carrito,
    required this.onVerCarrito,
    required this.onEliminar,
    this.eliminando = false,
  });

  /// Carrito a mostrar (datos reales de `GET /carritos`).
  final CarritoResumen carrito;

  /// Abre el detalle del carrito.
  final VoidCallback onVerCarrito;

  /// Elimina el carrito.
  final VoidCallback onEliminar;

  /// Indica que hay un DELETE en curso para este carrito.
  final bool eliminando;

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
          _CabeceraCarrito(carrito: carrito),
          const SizedBox(height: 16),
          _MetricasCarrito(carrito: carrito),
          const SizedBox(height: 16),
          _AccionesCarrito(
            onVerCarrito: onVerCarrito,
            onEliminar: onEliminar,
            eliminando: eliminando,
          ),
        ],
      ),
    );
  }
}

/// Sucursal del carrito y su última actualización.
class _CabeceraCarrito extends StatelessWidget {
  const _CabeceraCarrito({required this.carrito});

  final CarritoResumen carrito;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.32),
            ),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                carrito.sucursalEtiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Última actualización: ${carrito.actualizacionTexto}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Métricas del carrito: líneas, unidades y subtotal.
class _MetricasCarrito extends StatelessWidget {
  const _MetricasCarrito({required this.carrito});

  final CarritoResumen carrito;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Metrica(
            valor: '${carrito.cantidadLineas}',
            etiqueta: carrito.cantidadLineas == 1 ? 'Línea' : 'Líneas',
          ),
          const _SeparadorMetrica(),
          _Metrica(
            valor: '${carrito.cantidadUnidades}',
            etiqueta: carrito.cantidadUnidades == 1 ? 'Unidad' : 'Unidades',
          ),
          const _SeparadorMetrica(),
          _Metrica(
            valor: carrito.subtotalFormateado,
            etiqueta: 'Subtotal',
            destacado: true,
          ),
        ],
      ),
    );
  }
}

/// Columna de una métrica del carrito.
class _Metrica extends StatelessWidget {
  const _Metrica({
    required this.valor,
    required this.etiqueta,
    this.destacado = false,
  });

  final String valor;
  final String etiqueta;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valor,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: destacado ? 15 : 14.5,
              fontWeight: FontWeight.w800,
              color: destacado ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            etiqueta,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Línea divisoria vertical entre métricas.
class _SeparadorMetrica extends StatelessWidget {
  const _SeparadorMetrica();

  @override
  Widget build(BuildContext context) {
    return Container(height: 32, width: 1, color: AppColors.border);
  }
}

/// Acciones de la tarjeta: ver carrito o eliminarlo.
///
/// En pantallas muy angostas los botones se apilan para evitar desbordes.
class _AccionesCarrito extends StatelessWidget {
  const _AccionesCarrito({
    required this.onVerCarrito,
    required this.onEliminar,
    required this.eliminando,
  });

  final VoidCallback onVerCarrito;
  final VoidCallback onEliminar;
  final bool eliminando;

  @override
  Widget build(BuildContext context) {
    final Widget verCarrito = BotonGradiente(
      label: 'Ver carrito',
      onPressed: eliminando ? null : onVerCarrito,
    );
    final Widget eliminar = _BotonEliminarCarrito(
      onPressed: onEliminar,
      eliminando: eliminando,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 270) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [verCarrito, const SizedBox(height: 10), eliminar],
          );
        }

        return Row(
          children: [
            Expanded(child: verCarrito),
            const SizedBox(width: 12),
            eliminar,
          ],
        );
      },
    );
  }
}

/// Botón secundario para eliminar un carrito.
class _BotonEliminarCarrito extends StatelessWidget {
  const _BotonEliminarCarrito({
    required this.onPressed,
    required this.eliminando,
  });

  final VoidCallback onPressed;
  final bool eliminando;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: eliminando ? null : onPressed,
      icon: eliminando
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.textMuted),
              ),
            )
          : const Icon(Icons.delete_outline_rounded, size: 18),
      label: const Text('Eliminar'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textMuted,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
