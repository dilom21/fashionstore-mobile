import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/prenda_geometry.dart';
import '../models/torso_anchor.dart';
import '../models/vestidor_config_model.dart';
import 'pose_preview_transform.dart';

/// Capa de la PRENDA 2D transparente (CU26 – Etapa 6).
///
/// Dibuja el PNG indicado por `VestidorConfig.assetUrl` sobre el torso usando la
/// geometría BASE del [TorsoAnchor] y los factores/offsets de la configuración
/// (aplicados UNA sola vez: sin doble escalado).
///
/// Responsabilidades:
/// - resolver y **cachear** la imagen por URL (nunca se descarga por frame),
/// - convertir la geometría normalizada con `TransformacionPose` (la misma que
///   el esqueleto y el rectángulo de diagnóstico),
/// - pintar con rotación y opacidad conservando el canal alfa del PNG.
///
/// NO interpreta landmarks, NO valida la pose, NO suaviza y NO conoce endpoints
/// de negocio: la única red es la descarga visual del asset.
class PrendaOverlay extends StatefulWidget {
  /// Crea la capa de prenda.
  const PrendaOverlay({
    super.key,
    required this.anchor,
    required this.configuracion,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Ancla base del torso. `null` ⇒ no dibuja, pero CONSERVA la imagen cacheada
  /// para que al recuperar la pose no haya que volver a descargarla.
  final TorsoAnchor? anchor;

  /// Configuración AR recibida del backend (factores, offsets, opacidad, asset).
  final VestidorConfig configuracion;

  /// Tamaño de la imagen analizada por MediaPipe (igual que el resto de capas).
  final int imageWidth;
  final int imageHeight;

  @override
  State<PrendaOverlay> createState() => _PrendaOverlayState();
}

class _PrendaOverlayState extends State<PrendaOverlay> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Imagen decodificada (con alfa). Se conserva aunque se pierda la pose.
  ui.Image? _imagen;

  /// URL ya resuelta: sirve para no volver a resolver en cada rebuild/frame.
  String? _urlResuelta;

  bool _cargando = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Sin notificar: la primera construcción ocurre justo después de initState.
    _resolverImagen(notificar: false);
  }

  @override
  void didUpdateWidget(covariant PrendaOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo se vuelve a resolver cuando CAMBIA la URL: las decenas de frames de
    // pose no disparan ninguna descarga.
    if (oldWidget.configuracion.assetUrl != widget.configuracion.assetUrl) {
      // Ya hay un rebuild en curso: no se necesita setState aquí.
      _resolverImagen(notificar: false);
    }
  }

  @override
  void dispose() {
    _liberarStream();
    // La imagen pertenece al ImageCache (NetworkImage): no se libera a mano.
    super.dispose();
  }

  void _liberarStream() {
    final ImageStreamListener? listener = _listener;
    final ImageStream? stream = _stream;
    if (listener != null && stream != null) {
      stream.removeListener(listener);
    }
    _listener = null;
    _stream = null;
  }

  /// Resuelve la imagen del `assetUrl` actual (reutilizando la caché de Flutter).
  ///
  /// [notificar] se pone en `false` cuando ya hay un rebuild en curso
  /// (`initState`/`didUpdateWidget`) para no llamar a `setState` durante el
  /// build.
  void _resolverImagen({bool notificar = true}) {
    _liberarStream();

    final String url = widget.configuracion.assetUrl.trim();
    if (url.isEmpty) {
      _urlResuelta = null;
      _imagen = null;
      _cargando = false;
      _error = null;
      if (notificar && mounted) setState(() {});
      return;
    }

    // Misma URL ya resuelta y dibujable: no se toca nada.
    if (url == _urlResuelta && _imagen != null) return;

    _cargando = true;
    _error = null;
    if (notificar && mounted) setState(() {});

    final ImageStream stream = NetworkImage(url)
        .resolve(ImageConfiguration.empty);
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool sincrono) {
        if (!mounted) return;
        setState(() {
          _imagen = info.image;
          _urlResuelta = url;
          _cargando = false;
          _error = null;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) return;
        // La cámara y MediaPipe siguen funcionando: solo se oculta la prenda.
        setState(() {
          _cargando = false;
          _error = error;
        });
      },
    );

    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  /// Reintenta la descarga del PNG (acción del aviso discreto).
  void _reintentar() {
    final String url = widget.configuracion.assetUrl.trim();
    if (url.isNotEmpty) {
      // Descarta un posible fallo cacheado por el ImageCache.
      NetworkImage(url).evict();
    }
    _urlResuelta = null;
    _resolverImagen();
  }

  @override
  Widget build(BuildContext context) {
    final PrendaGeometry? geometria = PrendaGeometry.desde(
      anchor: widget.anchor,
      configuracion: widget.configuracion,
    );
    final ui.Image? imagen = _imagen;
    final bool dibujar = geometria != null && imagen != null;

    return Stack(
      children: <Widget>[
        if (dibujar)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: PrendaPainter(
                  geometria: geometria,
                  imagen: imagen,
                  imageWidth: widget.imageWidth,
                  imageHeight: widget.imageHeight,
                ),
              ),
            ),
          ),
        // Avisos discretos: no interceptan la cámara ni bloquean MediaPipe.
        if (_cargando)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 92,
            child: _AvisoPrenda(mensaje: 'Cargando prenda...', cargando: true),
          ),
        if (_error != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 92,
            child: _AvisoPrenda(
              mensaje: 'No se pudo cargar la prenda.',
              onReintentar: _reintentar,
            ),
          ),
      ],
    );
  }
}

// ==CU26_PRENDA_PARTE_B==

/// Pintor de la prenda: SOLO render.
///
/// No interpreta landmarks ni calcula geometría: recibe la [PrendaGeometry] ya
/// resuelta (ancla base + configuración) y la dibuja con la MISMA transformación
/// de preview que el esqueleto y el rectángulo de diagnóstico.
class PrendaPainter extends CustomPainter {
  /// Crea el pintor de la prenda.
  PrendaPainter({
    required this.geometria,
    required this.imagen,
    required this.imageWidth,
    required this.imageHeight,
  });

  final PrendaGeometry geometria;
  final ui.Image imagen;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (!geometria.esVisible) return;
    if (imageWidth <= 0 || imageHeight <= 0) return;
    if (size.width <= 0 || size.height <= 0) return;

    final TransformacionPose transformacion = TransformacionPose.calcular(
      tamanoVista: size,
      anchoImagen: imageWidth,
      altoImagen: imageHeight,
    );

    final Offset centro = transformacion.aPantalla(
      geometria.centerX,
      geometria.centerY,
    );
    final double ancho = transformacion.anchoPantalla(geometria.width);
    final double alto = transformacion.altoPantalla(geometria.height);
    if (ancho <= 0 || alto <= 0) return;

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    // Mismo sentido de giro que el cálculo del ancla: no se invierte el signo.
    canvas.rotate(geometria.rotationRadians);

    final Rect origen = Rect.fromLTWH(
      0,
      0,
      imagen.width.toDouble(),
      imagen.height.toDouble(),
    );
    final Rect destino = Rect.fromCenter(
      center: Offset.zero,
      width: ancho,
      height: alto,
    );

    // La opacidad se aplica en el alfa del Paint, así se conserva la
    // transparencia real del PNG (blendMode srcOver por defecto).
    final Paint lapiz = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, geometria.opacidad);

    canvas.drawImageRect(imagen, origen, destino, lapiz);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PrendaPainter oldDelegate) {
    return oldDelegate.imagen != imagen ||
        oldDelegate.geometria != geometria ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}

/// Aviso discreto de carga/error de la prenda.
///
/// No bloquea la cámara ni MediaPipe: solo informa en la parte inferior.
class _AvisoPrenda extends StatelessWidget {
  const _AvisoPrenda({
    required this.mensaje,
    this.cargando = false,
    this.onReintentar,
  });

  final String mensaje;
  final bool cargando;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (cargando)
              const SizedBox(
                height: 13,
                width: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            else
              const Icon(
                Icons.broken_image_outlined,
                size: 14,
                color: AppColors.error,
              ),
            const SizedBox(width: 8),
            Text(
              mensaje,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            if (onReintentar != null) ...<Widget>[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onReintentar,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'REINTENTAR',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
