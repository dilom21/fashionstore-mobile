import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/producto_model.dart';

/// Fallback gráfico de marca VANTER MEN.
///
/// Se usa cuando un producto no tiene recursos (imágenes), cuando la URL llega
/// `null`/vacía o cuando una imagen falla al cargar. No realiza ninguna petición
/// de red y nunca muestra el icono de imagen rota del sistema.
class VanterFallback extends StatelessWidget {
  const VanterFallback({super.key, this.nombre = '', this.compact = false});

  final String nombre;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String inicial = nombre.trim().isEmpty
        ? 'V'
        : nombre.trim().substring(0, 1).toUpperCase();
    final double icono = compact ? 22 : 34;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppColors.surfaceVariant,
            AppColors.primary.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: compact ? -6 : -12,
            bottom: compact ? -14 : -22,
            child: Text(
              inicial,
              style: TextStyle(
                fontSize: compact ? 92 : 150,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(compact ? 6 : 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: compact ? 46 : 66,
                      width: compact ? 46 : 66,
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(
                        Icons.checkroom_rounded,
                        color: AppColors.textPrimary,
                        size: icono,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    Text(
                      'VANTER MEN',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: compact ? 9 : 11,
                        letterSpacing: compact ? 2 : 3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Imagen reutilizable de un producto.
///
/// Consume exactamente la URL recibida (nunca la construye ni la deriva de
/// Supabase, del id o del nombre del archivo). Si [url] es `null` o está vacía,
/// o si la descarga falla, muestra el fallback de marca [VanterFallback].
///
/// Por defecto mantiene una proporción 4:5 con `BoxFit.cover` para no deformar
/// las fotografías. Pasar [aspectRatio] como `null` hace que ocupe todo el
/// espacio disponible (útil dentro de una card o de un `PageView`).
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    this.semanticLabel,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.compactFallback = false,
    this.aspectRatio,
  });

  /// URL remota (HTTPS) entregada por el backend. Puede ser `null`.
  final String? url;

  /// Texto para accesibilidad, normalmente el nombre del producto.
  final String? semanticLabel;

  /// Ajuste de la imagen. Por defecto `BoxFit.cover`.
  final BoxFit fit;

  /// Radio de recorte. Usar [BorderRadius.zero] cuando el contenedor ya recorta.
  final BorderRadius borderRadius;

  /// Fallback compacto (cards y miniaturas).
  final bool compactFallback;

  /// Si se indica, envuelve la imagen en un `AspectRatio` (4:5 recomendado).
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final String limpia = url?.trim() ?? '';
    final String etiqueta = semanticLabel?.trim() ?? '';

    final Widget contenido = limpia.isEmpty
        ? _FallbackConSemantica(
            nombre: etiqueta,
            compact: compactFallback,
            etiqueta: etiqueta,
          )
        : Image.network(
            limpia,
            fit: fit,
            semanticLabel: etiqueta.isEmpty ? null : etiqueta,
            loadingBuilder: (
              BuildContext context,
              Widget child,
              ImageChunkEvent? progress,
            ) {
              if (progress == null) return child;
              return _CargandoImagen(compact: compactFallback);
            },
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stack) =>
                    _FallbackConSemantica(
              nombre: etiqueta,
              compact: compactFallback,
              etiqueta: etiqueta,
            ),
          );

    final Widget recortado = borderRadius == BorderRadius.zero
        ? contenido
        : ClipRRect(borderRadius: borderRadius, child: contenido);

    if (aspectRatio == null) return recortado;
    return AspectRatio(aspectRatio: aspectRatio!, child: recortado);
  }
}

/// Fallback accesible: anuncia la imagen y silencia el texto decorativo interno.
class _FallbackConSemantica extends StatelessWidget {
  const _FallbackConSemantica({
    required this.nombre,
    required this.compact,
    required this.etiqueta,
  });

  final String nombre;
  final bool compact;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: etiqueta.isEmpty ? 'Imagen no disponible' : etiqueta,
      child: ExcludeSemantics(
        child: VanterFallback(nombre: nombre, compact: compact),
      ),
    );
  }
}

/// Placeholder de carga discreto mientras se descarga la imagen.
class _CargandoImagen extends StatelessWidget {
  const _CargandoImagen({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const ColoredBox(color: AppColors.surfaceVariant);
    }
    return const ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
    );
  }
}

/// Galería de imágenes de un producto (detalle).
///
/// Muestra la imagen principal a tamaño grande (proporción 4:5) y permite
/// deslizar entre el resto de recursos con `PageView` + `PageController`.
/// Incluye indicadores de puntos y miniaturas táctiles cuando hay más de una
/// imagen. Soporta 0, 1, 2 o N recursos sin lanzar excepciones.
class ProductoMedia extends StatefulWidget {
  const ProductoMedia({super.key, required this.recursos, this.nombre});

  /// Recursos ya filtrados y ordenados por [ProductoDetalle.recursosUtilizables].
  final List<RecursoProducto> recursos;

  /// Nombre del producto (para accesibilidad).
  final String? nombre;

  @override
  State<ProductoMedia> createState() => _ProductoMediaState();
}

class _ProductoMediaState extends State<ProductoMedia> {
  final PageController _controller = PageController();
  int _paginaActual = 0;

  @override
  void didUpdateWidget(ProductoMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recursos.length != widget.recursos.length) {
      _ajustarPagina();
    }
  }

  /// Evita un índice fuera de rango si la lista de recursos cambia de tamaño.
  void _ajustarPagina() {
    final int total = widget.recursos.length;
    if (total == 0) {
      _paginaActual = 0;
      return;
    }
    final int maximo = total - 1;
    if (_paginaActual > maximo) {
      _paginaActual = maximo;
      if (_controller.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.hasClients) return;
          _controller.jumpToPage(_paginaActual);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _irAPagina(int index) {
    if (index < 0 || index >= widget.recursos.length) return;
    if (_controller.hasClients) {
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (index != _paginaActual) {
      setState(() => _paginaActual = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<RecursoProducto> recursos = widget.recursos;
    final String nombre = widget.nombre?.trim() ?? '';

    if (recursos.isEmpty) {
      return const AspectRatio(
        aspectRatio: 4 / 5,
        child: VanterFallback(),
      );
    }

    final int total = recursos.length;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: PageView.builder(
            controller: _controller,
            itemCount: total,
            onPageChanged: (int index) {
              if (mounted) setState(() => _paginaActual = index);
            },
            itemBuilder: (BuildContext context, int index) {
              final String etiqueta = nombre.isEmpty
                  ? 'Imagen ${index + 1} de $total'
                  : 'Imagen ${index + 1} de $total de $nombre';
              return ProductImage(
                url: recursos[index].url,
                semanticLabel: etiqueta,
              );
            },
          ),
        ),
        if (total > 1) ...[
          const SizedBox(height: 12),
          _Indicadores(total: total, actual: _paginaActual),
          const SizedBox(height: 12),
          _Miniaturas(
            recursos: recursos,
            actual: _paginaActual,
            onTap: _irAPagina,
          ),
        ],
      ],
    );
  }
}

/// Indicadores de puntos del carrusel.
class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.total, required this.actual});

  final int total;
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(
        total,
        (int index) => AnimatedContainer(
          key: ValueKey<String>('producto-media-punto-$index'),
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          height: 6,
          width: actual == index ? 18 : 6,
          decoration: BoxDecoration(
            color: actual == index ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// Miniaturas táctiles: al tocar una se cambia la página activa.
class _Miniaturas extends StatelessWidget {
  const _Miniaturas({
    required this.recursos,
    required this.actual,
    required this.onTap,
  });

  final List<RecursoProducto> recursos;
  final int actual;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final int total = recursos.length;

    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final bool activo = index == actual;
          return Semantics(
            key: ValueKey<String>('producto-media-thumb-$index'),
            button: true,
            selected: activo,
            label: 'Ver imagen ${index + 1} de $total',
            child: GestureDetector(
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activo ? AppColors.primary : AppColors.border,
                    width: activo ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ExcludeSemantics(
                    child: ProductImage(
                      url: recursos[index].url,
                      borderRadius: BorderRadius.zero,
                      compactFallback: true,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
