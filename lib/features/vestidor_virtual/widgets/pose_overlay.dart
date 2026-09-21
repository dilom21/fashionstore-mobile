import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';

/// Conexiones del esqueleto: pares de índices de los 33 landmarks de MediaPipe.
///
/// Cubren cara (básica), torso, brazos y piernas.
const List<List<int>> conexionesPose = <List<int>>[
  // Cara (básica)
  <int>[0, 1], <int>[1, 2], <int>[2, 3], <int>[3, 7],
  <int>[0, 4], <int>[4, 5], <int>[5, 6], <int>[6, 8], <int>[9, 10],
  // Torso
  <int>[11, 12], <int>[11, 23], <int>[12, 24], <int>[23, 24],
  // Brazo izquierdo
  <int>[11, 13], <int>[13, 15], <int>[15, 17], <int>[15, 19],
  <int>[15, 21], <int>[17, 19],
  // Brazo derecho
  <int>[12, 14], <int>[14, 16], <int>[16, 18], <int>[16, 20],
  <int>[16, 22], <int>[18, 20],
  // Pierna izquierda
  <int>[23, 25], <int>[25, 27], <int>[27, 29], <int>[29, 31], <int>[27, 31],
  // Pierna derecha
  <int>[24, 26], <int>[26, 28], <int>[28, 30], <int>[30, 32], <int>[28, 32],
];

/// Overlay que dibuja los 33 landmarks y el esqueleto sobre el preview de cámara.
///
/// Se coloca encima de `PoseCameraView` ocupando exactamente su misma área. Las
/// coordenadas llegan normalizadas respecto de la imagen que analizó MediaPipe
/// (`imageWidth` × `imageHeight`) y se transforman con la misma matemática que
/// `PreviewView.ScaleType.FILL_CENTER`: escalar con `max`, centrar y recortar.
///
/// NO dibuja nada si no hay pose. No aplica suavizado ni filtros.
class PoseOverlay extends StatelessWidget {
  const PoseOverlay({
    super.key,
    required this.resultado,
    this.umbralVisibilidad = 0.5,
    this.mostrarIndices = false,
  });

  /// Resultado actual de MediaPipe.
  final PoseDetectionResult resultado;

  /// Visibilidad mínima para dibujar un punto o una conexión.
  final double umbralVisibilidad;

  /// Modo debug opcional: dibuja el índice de cada landmark junto al punto.
  final bool mostrarIndices;

  @override
  Widget build(BuildContext context) {
    // El overlay nunca debe interceptar gestos de la cámara.
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: PoseOverlayPainter(
          resultado: resultado,
          umbralVisibilidad: umbralVisibilidad,
          mostrarIndices: mostrarIndices,
        ),
      ),
    );
  }
}

/// Pintor de landmarks + esqueleto.
class PoseOverlayPainter extends CustomPainter {
  PoseOverlayPainter({
    required this.resultado,
    this.umbralVisibilidad = 0.5,
    this.mostrarIndices = false,
  });

  final PoseDetectionResult resultado;
  final double umbralVisibilidad;
  final bool mostrarIndices;

  /// Color del esqueleto (mismo verde que el indicador de detección).
  static const Color _colorEsqueleto = Color(0xFF32C48D);

  /// Color del relleno de los puntos (contrasta sobre cualquier imagen).
  static const Color _colorPunto = Color(0xFFF5F5FA);

  static const double _radioPunto = 3.4;
  static const double _anchoLinea = 2.0;
  static const double _anchoBorde = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (!resultado.poseDetected) return;

    final int anchoImagen = resultado.imageWidth;
    final int altoImagen = resultado.imageHeight;
    if (anchoImagen <= 0 || altoImagen <= 0) return;
    if (size.width <= 0 || size.height <= 0) return;

    final _TransformacionPose transformacion = _TransformacionPose.calcular(
      tamanoVista: size,
      anchoImagen: anchoImagen,
      altoImagen: altoImagen,
    );

    // Posiciones en pantalla solo de los puntos que se pueden dibujar.
    final Map<int, Offset> puntos = <int, Offset>{};
    for (final PoseLandmark punto in resultado.landmarks) {
      if (!_esDibujable(punto)) continue;
      puntos[punto.index] = transformacion.aPantalla(punto.x, punto.y);
    }
    if (puntos.isEmpty) return;

    final Paint lapizLinea = Paint()
      ..color = _colorEsqueleto
      ..strokeWidth = _anchoLinea
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final List<int> conexion in conexionesPose) {
      final Offset? inicio = puntos[conexion[0]];
      final Offset? fin = puntos[conexion[1]];
      // La conexión solo se dibuja si existen ambos extremos dibujables.
      if (inicio == null || fin == null) continue;
      canvas.drawLine(inicio, fin, lapizLinea);
    }

    final Paint lapizRelleno = Paint()
      ..color = _colorPunto
      ..style = PaintingStyle.fill;
    final Paint lapizBorde = Paint()
      ..color = _colorEsqueleto
      ..strokeWidth = _anchoBorde
      ..style = PaintingStyle.stroke;

    for (final MapEntry<int, Offset> entrada in puntos.entries) {
      canvas.drawCircle(entrada.value, _radioPunto, lapizRelleno);
      canvas.drawCircle(entrada.value, _radioPunto, lapizBorde);
      if (mostrarIndices) {
        _dibujarIndice(canvas, entrada.value, entrada.key);
      }
    }
  }

  /// Un punto se dibuja si cae dentro del frame y tiene visibilidad suficiente.
  ///
  /// Si `visibility` viene en `null` NO se asume invisible. Los puntos fuera de
  /// la imagen se descartan (no se ajustan a los bordes de la pantalla).
  bool _esDibujable(PoseLandmark punto) {
    if (punto.x < 0 || punto.x > 1 || punto.y < 0 || punto.y > 1) return false;
    final double? visibilidad = punto.visibility;
    if (visibilidad == null) return true;
    return visibilidad >= umbralVisibilidad;
  }

  /// Modo debug: número del índice junto al punto.
  void _dibujarIndice(Canvas canvas, Offset centro, int indice) {
    final TextPainter texto = TextPainter(
      text: TextSpan(
        text: '$indice',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _colorEsqueleto,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    texto.paint(canvas, centro + const Offset(5, -12));
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.resultado != resultado ||
        oldDelegate.umbralVisibilidad != umbralVisibilidad ||
        oldDelegate.mostrarIndices != mostrarIndices;
  }
}

/// Transformación de coordenadas normalizadas (frame) → píxeles de pantalla.
///
/// Equivale a `BoxFit.cover` / `PreviewView.ScaleType.FILL_CENTER`:
/// `scale = max(viewW / imageW, viewH / imageH)` y la imagen escalada se centra
/// en la vista (el sobrante se recorta por igual a ambos lados).
///
/// Nota para el futuro: esto es exacto siempre que el stream de análisis y el de
/// preview compartan relación de aspecto (en CameraX ambos son 4:3 por defecto).
/// Si no coincidieran, la solución correcta sería exponer desde el lado nativo
/// la resolución real del preview; NO acumular offsets manuales aquí.
class _TransformacionPose {
  const _TransformacionPose({
    required this.escala,
    required this.desplazamientoX,
    required this.desplazamientoY,
    required this.anchoImagen,
    required this.altoImagen,
  });

  final double escala;
  final double desplazamientoX;
  final double desplazamientoY;
  final int anchoImagen;
  final int altoImagen;

  static _TransformacionPose calcular({
    required Size tamanoVista,
    required int anchoImagen,
    required int altoImagen,
  }) {
    final double escalaX = tamanoVista.width / anchoImagen;
    final double escalaY = tamanoVista.height / altoImagen;
    final double escala = math.max(escalaX, escalaY);
    final double anchoEscalado = anchoImagen * escala;
    final double altoEscalado = altoImagen * escala;

    return _TransformacionPose(
      escala: escala,
      desplazamientoX: (tamanoVista.width - anchoEscalado) / 2,
      desplazamientoY: (tamanoVista.height - altoEscalado) / 2,
      anchoImagen: anchoImagen,
      altoImagen: altoImagen,
    );
  }

  /// `screenX = offsetX + (x * imageWidth) * scale` (y análogamente en Y).
  ///
  /// Las coordenadas llegan tal cual de MediaPipe: la imagen ya fue rotada y
  /// espejada (solo cámara frontal) en el lado nativo, así que aquí NO se vuelve
  /// a espejar (`x = 1 - x`).
  Offset aPantalla(double x, double y) {
    return Offset(
      desplazamientoX + x * anchoImagen * escala,
      desplazamientoY + y * altoImagen * escala,
    );
  }
}