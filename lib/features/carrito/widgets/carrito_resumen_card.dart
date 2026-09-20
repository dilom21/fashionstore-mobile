import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/carrito_model.dart';
import 'boton_gradiente.dart';

/// Tarjeta de resumen del carrito (sección inferior del detalle).
///
/// Usa los totales que devuelve el backend (`cantidad_total_unidades` y
/// `subtotal_carrito`) como fuente de verdad: la app no los recalcula.
///
/// CU16 (Reservar prendas): la zona de acciones está separada en
/// [_AccionesResumen] para poder insertar ahí la nueva acción reutilizando el
/// mismo estilo de botón, sin tocar el resto de la tarjeta.
class CarritoResumenCard extends StatelessWidget {
  const CarritoResumenCard({
    super.key,
    required this.carrito,
    required this.onIrAPagar,
    required this.onBuscarMas,
    this.onReservar,
  });

  /// Carrito resumido (detalle real del backend).
  final CarritoDetalle carrito;

  /// Acción principal: ir a pagar (CU19 abre el checkout digital).
  final VoidCallback onIrAPagar;

  /// Acción secundaria: seguir explorando el catálogo.
  final VoidCallback onBuscarMas;

  /// CU16: reservar las prendas del carrito.
  ///
  /// Es `null` cuando el carrito no está ACTIVO o no tiene unidades, por lo que
  /// la acción no se muestra en esos casos.
  final VoidCallback? onReservar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 26,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 34,
                width: 4,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Resumen',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _FilaResumen(
            etiqueta: 'Unidades',
            valor: '${carrito.cantidadTotalUnidades}',
          ),
          const SizedBox(height: 10),
          _FilaResumen(
            etiqueta: carrito.cantidadLineas == 1 ? 'Prenda' : 'Prendas',
            valor: '${carrito.cantidadLineas}',
          ),
          const SizedBox(height: 10),
          _FilaResumen(etiqueta: 'Sucursal', valor: carrito.sucursalEtiqueta),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          _FilaResumen(
            etiqueta: 'Total',
            valor: carrito.subtotalFormateado,
            destacado: true,
          ),
          const SizedBox(height: 22),
          _AccionesResumen(
            onIrAPagar: onIrAPagar,
            onBuscarMas: onBuscarMas,
            onReservar: onReservar,
          ),
        ],
      ),
    );
  }
}

/// Fila etiqueta/valor del resumen.
class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.etiqueta,
    required this.valor,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: destacado ? 14 : 13,
            fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
            color: destacado ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: destacado ? 20 : 13.5,
              fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Acciones del resumen.
///
/// CU16: `RESERVAR PRENDAS` solo aparece cuando el carrito está ACTIVO y tiene
/// unidades. El pago sigue pendiente (no se implementa en CU15/CU16).
class _AccionesResumen extends StatelessWidget {
  const _AccionesResumen({
    required this.onIrAPagar,
    required this.onBuscarMas,
    required this.onReservar,
  });

  final VoidCallback onIrAPagar;
  final VoidCallback onBuscarMas;
  final VoidCallback? onReservar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onReservar != null) ...[
          BotonGradiente(
            label: 'RESERVAR PRENDAS',
            onPressed: onReservar,
            icon: Icons.event_available_rounded,
          ),
          const SizedBox(height: 12),
        ],
        BotonGradiente(
          label: 'IR A PAGAR',
          onPressed: onIrAPagar,
          icon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onBuscarMas,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Buscar más productos',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}
