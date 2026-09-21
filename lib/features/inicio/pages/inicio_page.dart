import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../carrito/widgets/boton_gradiente.dart';

/// Portada personal del CLIENTE autenticado (pestaña Inicio).
///
/// Ya no es una pantalla temporal: concentra accesos REALES a funcionalidades
/// existentes (Catálogo, Carrito, Reservas e historial de compras) y un bloque
/// editorial de marca.
///
/// No consulta el backend, no inventa métricas ni contadores y se ve bien sin
/// conexión: todo lo decorativo es vectorial.
class InicioPage extends StatelessWidget {
  /// Crea la portada de Inicio.
  const InicioPage({
    super.key,
    required this.onExplorarCatalogo,
    required this.onVerCarrito,
    required this.onVerReservas,
    required this.onVerCompras,
  });

  /// Cambia a la pestaña Catálogo.
  final VoidCallback onExplorarCatalogo;

  /// Cambia a la pestaña Carrito.
  final VoidCallback onVerCarrito;

  /// Abre el historial de reservas del cliente.
  final VoidCallback onVerReservas;

  /// Abre el historial de compras del cliente.
  final VoidCallback onVerCompras;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: <Widget>[
              const _MarcaInicio(),
              const SizedBox(height: 22),
              _HeroInicio(onExplorarCatalogo: onExplorarCatalogo),
              const SizedBox(height: 26),
              const Text(
                'TU EXPERIENCIA',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              _AccionesInicio(
                onExplorarCatalogo: onExplorarCatalogo,
                onVerCarrito: onVerCarrito,
                onVerReservas: onVerReservas,
                onVerCompras: onVerCompras,
              ),
              const SizedBox(height: 28),
              const _BloqueMarca(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Encabezado compacto de la portada.
class _MarcaInicio extends StatelessWidget {
  const _MarcaInicio();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.32),
                blurRadius: 16,
              ),
            ],
          ),
          child: const Icon(
            Icons.checkroom_rounded,
            color: Colors.white,
            size: 19,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'VANTER MEN',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'ESTILO • DISCIPLINA • RESULTADOS',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
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

// ==CU24INICIO_PARTE_B==

/// Bloque principal: mensaje de marca y acceso al catálogo.
class _HeroInicio extends StatelessWidget {
  const _HeroInicio({required this.onExplorarCatalogo});

  final VoidCallback onExplorarCatalogo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.primary.withValues(alpha: 0.26),
            AppColors.secondary.withValues(alpha: 0.10),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: <Widget>[
            // Detalle decorativo vectorial (sin imágenes remotas).
            Positioned(
              right: -28,
              top: -34,
              child: Icon(
                Icons.checkroom_rounded,
                size: 168,
                color: AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text(
                      'NUEVA EXPERIENCIA',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tu estilo.\nTu momento.',
                    style: TextStyle(
                      fontSize: 27,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Descubre prendas diseñadas para acompañar cada versión '
                    'de ti.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  BotonGradiente(
                    label: 'EXPLORAR CATÁLOGO',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: onExplorarCatalogo,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==CU24INICIO_PARTE_C==

/// Cuatro accesos reales: 2x2 cuando hay ancho, apilados si no cabe.
class _AccionesInicio extends StatelessWidget {
  const _AccionesInicio({
    required this.onExplorarCatalogo,
    required this.onVerCarrito,
    required this.onVerReservas,
    required this.onVerCompras,
  });

  final VoidCallback onExplorarCatalogo;
  final VoidCallback onVerCarrito;
  final VoidCallback onVerReservas;
  final VoidCallback onVerCompras;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tarjetas = <Widget>[
      _AccionInicio(
        icono: Icons.storefront_rounded,
        titulo: 'Catálogo',
        subtitulo: 'Encuentra tu próximo look.',
        onTap: onExplorarCatalogo,
      ),
      _AccionInicio(
        icono: Icons.shopping_bag_rounded,
        titulo: 'Mi carrito',
        subtitulo: 'Continúa con tus prendas.',
        onTap: onVerCarrito,
      ),
      _AccionInicio(
        icono: Icons.event_available_rounded,
        titulo: 'Mis reservas',
        subtitulo: 'Consulta tus prendas reservadas.',
        onTap: onVerReservas,
      ),
      _AccionInicio(
        icono: Icons.receipt_long_rounded,
        titulo: 'Mis compras',
        subtitulo: 'Revisa tu historial y comprobantes.',
        onTap: onVerCompras,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // En pantallas muy angostas las tarjetas van en una sola columna.
        if (constraints.maxWidth < 330) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tarjetas.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                tarjetas[i],
              ],
            ],
          );
        }

        Widget par(int izquierda, int derecha) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: tarjetas[izquierda]),
                const SizedBox(width: 12),
                Expanded(child: tarjetas[derecha]),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            par(0, 1),
            const SizedBox(height: 12),
            par(2, 3),
          ],
        );
      },
    );
  }
}

/// Tarjeta premium de acceso a una sección real de la app.
class _AccionInicio extends StatelessWidget {
  const _AccionInicio({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      height: 34,
                      width: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(icono, size: 17, color: AppColors.primary),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==CU24INICIO_PARTE_D==

/// Bloque editorial de marca (cierre de la portada).
class _BloqueMarca extends StatelessWidget {
  const _BloqueMarca();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 3,
                width: 26,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'VANTER MEN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'ESTILO • DISCIPLINA • RESULTADOS',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Compra, reserva y consulta tus compras desde una experiencia '
            'diseñada para ti.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
