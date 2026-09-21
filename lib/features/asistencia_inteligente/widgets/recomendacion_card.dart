import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/asistencia_models.dart';

/// Tarjeta de una recomendación real de Asistencia Inteligente.
///
/// Todos los datos mostrados (imagen, nombre, precio, color, talla, temporada,
/// stock) provienen del backend, que los reconstruye desde PostgreSQL. La
/// tarjeta nunca inventa ni recalcula valores comerciales.
class RecomendacionCard extends StatelessWidget {
  const RecomendacionCard({
    super.key,
    required this.recomendacion,
    required this.onAgregar,
    required this.onVerDetalle,
    required this.onProbarVestidor,
    this.agregando = false,
  });

  final RecomendacionProducto recomendacion;
  final VoidCallback onAgregar;
  final VoidCallback onVerDetalle;
  final VoidCallback onProbarVestidor;
  final bool agregando;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Imagen(recomendacion: recomendacion),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recomendacion.categoria.trim().isNotEmpty)
                  Text(
                    recomendacion.categoria.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  recomendacion.nombre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  recomendacion.precioFormateado,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if ((recomendacion.color ?? '').isNotEmpty)
                      _Etiqueta(
                        icono: Icons.palette_outlined,
                        texto: recomendacion.color!,
                      ),
                    if ((recomendacion.talla ?? '').isNotEmpty)
                      _Etiqueta(
                        icono: Icons.straighten_rounded,
                        texto: 'Talla ${recomendacion.talla}',
                      ),
                    if ((recomendacion.temporada ?? '').isNotEmpty)
                      _Etiqueta(
                        icono: Icons.wb_sunny_outlined,
                        texto: recomendacion.temporada!,
                      ),
                    _Etiqueta(
                      icono: Icons.inventory_2_outlined,
                      texto: recomendacion.stockEtiqueta,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  recomendacion.motivoTexto,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textMuted,
                  ),
                ),
                if (recomendacion.requiereSeleccion) ...[
                  const SizedBox(height: 10),
                  const _AvisoSeleccion(),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: agregando ? null : onAgregar,
                        icon: agregando
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(
                                recomendacion.requiereSeleccion
                                    ? Icons.tune_rounded
                                    : Icons.add_shopping_cart_rounded,
                                size: 18,
                              ),
                        label: Text(
                          recomendacion.requiereSeleccion
                              ? 'Elegir talla'
                              : 'Agregar',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onVerDetalle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Ver detalle',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onProbarVestidor,
                    icon: const Icon(
                      Icons.checkroom_rounded,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    label: const Text(
                      'Probar en vestidor',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondary,
                      ),
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

class _Imagen extends StatelessWidget {
  const _Imagen({required this.recomendacion});

  final RecomendacionProducto recomendacion;

  @override
  Widget build(BuildContext context) {
    if (!recomendacion.tieneImagen) {
      return const _Placeholder();
    }
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Image.network(
        recomendacion.imagenUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _Placeholder(),
        loadingBuilder: (context, child, progreso) {
          if (progreso == null) return child;
          return const _Placeholder(cargando: true);
        },
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.cargando = false});

  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: cargando
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            : const Icon(
                Icons.checkroom_rounded,
                color: AppColors.inactive,
                size: 34,
              ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoSeleccion extends StatelessWidget {
  const _AvisoSeleccion();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Elige tu talla en el detalle para agregarla al carrito.',
              style: TextStyle(
                fontSize: 11.5,
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
