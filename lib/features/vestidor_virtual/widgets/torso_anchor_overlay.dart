import 'package:flutter/material.dart';

import '../models/torso_anchor.dart';
import 'pose_preview_transform.dart';

/// Rectángulo de DIAGNÓSTICO del torso (CU26 – Etapa 5).
///
/// Dibuja el [TorsoAnchor] ya calculado con los landmarks **suavizados**. NO es
/// una prenda: sirve para validar visualmente posición, ancho, alto, rotación y
/// estabilidad antes de la Etapa 6.
///
/// Reutiliza EXACTAMENTE la misma transformación que `PoseOverlay`
/// ([TransformacionPose]), así que la caja y el esqueleto quedan alineados con
/// el preview de cámara.
class TorsoAnchorOverlay extends StatelessWidget {
  /// Crea la capa de diagnóstico del torso.
  const TorsoAnchorOverlay({
    super.key,
    required this.anchor,
    required this.imageWidth,
    required this.imageHeight,
    this.factorAnchoDiagnostico = factorAnchoDiagnosticoPorDefecto,
    this.factorAltoDiagnostico = factorAltoDiagnosticoPorDefecto,
  });

  /// Margen del rectángulo **solo de diagnóstico** (Etapa 5).
  ///
  /// Vive aquí a propósito: el [TorsoAnchor] se mantiene en geometría BASE y la
  /// prenda aplica `VestidorConfig.factorAncho`/`factorAlto`. Si el margen
  /// estuviera dentro del ancla, la prenda multiplicaría dos veces
  /// (1.15 × factorAncho de la configuración).
  static const double factorAnchoDiagnosticoPorDefecto = 1.15;
  static const double factorAltoDiagnosticoPorDefecto = 1.15;

  /// Ancla del torso (geometría base).
  final TorsoAnchor anchor;

  /// Margen de ancho que usa SOLO este rectángulo de diagnóstico.
  final double factorAnchoDiagnostico;

  /// Margen de alto que usa SOLO este rectángulo de diagnóstico.
  final double factorAltoDiagnostico;

  /// Tamaño de la imagen analizada por MediaPipe (el mismo que usa el overlay
  /// del esqueleto para transformar coordenadas).
  final int imageWidth;
  final int imageHeight;

  @override
  Widget build(BuildContext context) {
    // Igual que el esqueleto: nunca debe interceptar gestos de la cámara.
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: TorsoAnchorPainter(
          anchor: anchor,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          factorAncho: factorAnchoDiagnostico,
          factorAlto: factorAltoDiagnostico,
        ),
      ),
    );
  }
}

/// Pintor del rectángulo del torso: SOLO render.
///
/// No interpreta landmarks: toda la geometría viene ya resuelta en el
/// [TorsoAnchor] (modelo) calculado por `TorsoAnchorService`.
class TorsoAnchorPainter extends CustomPainter {
  /// Crea el pintor del ancla.
  TorsoAnchorPainter({
    required this.anchor,
    required this.imageWidth,
    required this.imageHeight,
    required this.factorAncho,
    required this.factorAlto,
  });

  final TorsoAnchor anchor;
  final int imageWidth;
  final int imageHeight;

  /// Margen de diagnóstico aplicado a la geometría base del ancla.
  final double factorAncho;
  final double factorAlto;

  /// Relleno muy transparente: el torso real debe seguir viéndose debajo.
  static const Color _colorRelleno = Color(0x338B5CF6);

  /// Borde de acento (magenta) para comparar con el esqueleto verde.
  static const Color _colorBorde = Color(0xFFD946EF);

  static const double _grosorBorde = 2.0;
  static const double _radioEsquinas = 10;
  static const double _grosorLineaHombros = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (!anchor.esValido) return;
    if (imageWidth <= 0 || imageHeight <= 0) return;
    if (size.width <= 0 || size.height <= 0) return;

    final TransformacionPose transformacion = TransformacionPose.calcular(
      tamanoVista: size,
      anchoImagen: imageWidth,
      altoImagen: imageHeight,
    );

    final Offset centro = transformacion.aPantalla(
      anchor.centerX,
      anchor.centerY,
    );
    final double ancho = transformacion.anchoPantalla(
      anchor.shoulderWidth * factorAncho,
    );
    final double alto = transformacion.altoPantalla(
      anchor.torsoHeight * factorAlto,
    );
    if (ancho <= 0 || alto <= 0) return;

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    // El ángulo se aplica en el MISMO sentido en que se calculó (`atan2` sobre
    // las coordenadas que ya vienen rotadas/espejadas del lado nativo): no se
    // invierte el signo.
    canvas.rotate(anchor.rotationRadians);

    final RRect caja = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: ancho, height: alto),
      const Radius.circular(_radioEsquinas),
    );

    canvas.drawRRect(
      caja,
      Paint()
        ..color = _colorRelleno
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      caja,
      Paint()
        ..color = _colorBorde
        ..strokeWidth = _grosorBorde
        ..style = PaintingStyle.stroke,
    );

    // Línea de hombros: referencia del anclaje superior de la futura prenda.
    final double yHombros = -alto / 2;
    canvas.drawLine(
      Offset(-ancho / 2, yHombros),
      Offset(ancho / 2, yHombros),
      Paint()
        ..color = _colorBorde.withValues(alpha: 0.65)
        ..strokeWidth = _grosorLineaHombros,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TorsoAnchorPainter oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.factorAncho != factorAncho ||
        oldDelegate.factorAlto != factorAlto;
  }
}
