import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Transformación de coordenadas normalizadas (frame de MediaPipe) → píxeles de
/// pantalla para las capas que se dibujan encima del preview de cámara.
///
/// Equivale a `BoxFit.cover` / `PreviewView.ScaleType.FILL_CENTER`:
/// `scale = max(viewW / imageW, viewH / imageH)` y la imagen escalada se centra
/// en la vista (el sobrante se recorta por igual a ambos lados).
///
/// Vive en su propio archivo para que `PoseOverlay` (Etapa 4) y
/// `TorsoAnchorOverlay` (Etapa 5) usen EXACTAMENTE la misma matemática: no debe
/// haber dos fórmulas de transformación distintas.
///
/// Nota para el futuro: esto es exacto siempre que el stream de análisis y el de
/// preview compartan relación de aspecto (en CameraX ambos son 4:3 por defecto).
/// Si no coincidieran, la solución correcta sería exponer desde el lado nativo
/// la resolución real del preview; NO acumular offsets manuales aquí.
class TransformacionPose {
  const TransformacionPose({
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

  static TransformacionPose calcular({
    required Size tamanoVista,
    required int anchoImagen,
    required int altoImagen,
  }) {
    final double escalaX = tamanoVista.width / anchoImagen;
    final double escalaY = tamanoVista.height / altoImagen;
    final double escala = math.max(escalaX, escalaY);
    final double anchoEscalado = anchoImagen * escala;
    final double altoEscalado = altoImagen * escala;

    return TransformacionPose(
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

  /// Distancia normalizada en X → píxeles de pantalla.
  double anchoPantalla(double anchoNormalizado) =>
      anchoNormalizado * anchoImagen * escala;

  /// Distancia normalizada en Y → píxeles de pantalla.
  double altoPantalla(double altoNormalizado) =>
      altoNormalizado * altoImagen * escala;
}
