import 'dart:math' as math;

/// Ancla geométrica del torso calculada a partir de los landmarks 11, 12, 23 y
/// 24 de MediaPipe (CU26 – Etapa 5).
///
/// Es un modelo de **solo geometría**, en coordenadas normalizadas de la imagen
/// (0..1, el mismo sistema que entrega MediaPipe al overlay):
/// - [centerX]/[centerY]: centro del torso.
/// - [width]: ancho de referencia (derivado de la línea de hombros).
/// - [height]: alto de referencia (hombros → caderas).
/// - [rotationRadians]: inclinación de la línea de hombros.
///
/// NO contiene `Widget`, `Canvas`, `BuildContext` ni nada de UI: lo consumen el
/// pintor de diagnóstico de la Etapa 5 y, en la Etapa 6, la prenda.
class TorsoAnchor {
  const TorsoAnchor({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotationRadians,
    this.shoulderWidth = 0,
    this.hipWidth = 0,
  });

  /// Centro del torso, en coordenadas normalizadas de la imagen.
  final double centerX;
  final double centerY;

  /// Ancho del ancla (normalizado). Sale del ancho de hombros por [factorAncho].
  final double width;

  /// Alto del ancla (normalizado). Sale de la distancia hombros→caderas.
  final double height;

  /// Giro del ancla en radianes (inclinación de la línea de hombros).
  final double rotationRadians;

  /// Distancia real entre hombros (11–12), sin factores. Informativo.
  final double shoulderWidth;

  /// Distancia real entre caderas (23–24); 0.0 si solo se detectó una cadera.
  final double hipWidth;

  /// `true` cuando el ancla tiene geometría utilizable.
  bool get esValido => width > 0 && height > 0;

  /// Rotación en grados (solo para diagnóstico).
  double get rotationGrados => rotationRadians * 180 / math.pi;

  @override
  String toString() =>
      'TorsoAnchor(center=(${centerX.toStringAsFixed(3)}, '
      '${centerY.toStringAsFixed(3)}), width=${width.toStringAsFixed(3)}, '
      'height=${height.toStringAsFixed(3)}, '
      'rot=${rotationGrados.toStringAsFixed(1)}°)';
}
