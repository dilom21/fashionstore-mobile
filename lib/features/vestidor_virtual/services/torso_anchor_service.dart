import 'dart:math' as math;

import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';
import '../models/torso_anchor.dart';
import 'pose_validator.dart';

/// Calcula el [TorsoAnchor] **base** (Etapa 5) a partir de un resultado de pose
/// **ya estabilizado** por `PoseSmoothingService`.
///
/// Devuelve SOLO geometría base (centro, ancho de hombros, alto del torso y
/// giro), sin calibración de ninguna prenda: los factores, offsets y la
/// opacidad vienen de `VestidorConfig` en la Etapa 6, y el margen del rectángulo
/// de diagnóstico vive en `TorsoAnchorOverlay`. Así se evita el doble escalado.
///
/// No lee cámara, no hace HTTP, no consulta backend ni Supabase y no valida la
/// pose por su cuenta (esa decisión ya la tomó `PoseValidator`). Si faltan
/// landmarks o la geometría es degenerada devuelve `null`, nunca lanza
/// excepciones por un frame incompleto.
class TorsoAnchorService {
  const TorsoAnchorService({
    this.inclinacionMaximaRad = inclinacionMaximaPorDefecto,
  });

  /// Inclinación máxima aceptada de la línea de hombros (radianes).
  ///
  /// 1.05 rad ≈ 60°: más que eso significa que los hombros están prácticamente
  /// verticales en la imagen (pose girada/caída) y el ancla no aportaría nada.
  static const double inclinacionMaximaPorDefecto = 1.05;

  final double inclinacionMaximaRad;

  /// Devuelve el ancla del torso, o `null` si no hay geometría utilizable.
  TorsoAnchor? calcular(PoseDetectionResult resultado) {
    if (!resultado.poseDetected) return null;

    final PoseLandmark? hombroIzq = resultado.porIndice(indiceHombroIzquierdo);
    final PoseLandmark? hombroDer = resultado.porIndice(indiceHombroDerecho);
    final PoseLandmark? caderaIzq = resultado.porIndice(indiceCaderaIzquierda);
    final PoseLandmark? caderaDer = resultado.porIndice(indiceCaderaDerecha);

    // Los hombros son imprescindibles (anclaje de la prenda superior).
    if (hombroIzq == null || hombroDer == null) return null;

    final double shoulderCenterX = (hombroIzq.x + hombroDer.x) / 2;
    final double shoulderCenterY = (hombroIzq.y + hombroDer.y) / 2;

    // La Etapa 4 admite que falte una cadera: el centro inferior se calcula con
    // las disponibles y el ancho de caderas solo se informa si están las dos.
    final List<PoseLandmark> caderas = <PoseLandmark>[?caderaIzq, ?caderaDer];
    if (caderas.isEmpty) return null;

    double sumaCaderasX = 0;
    double sumaCaderasY = 0;
    for (final PoseLandmark cadera in caderas) {
      sumaCaderasX += cadera.x;
      sumaCaderasY += cadera.y;
    }
    final double hipCenterX = sumaCaderasX / caderas.length;
    final double hipCenterY = sumaCaderasY / caderas.length;

    final double shoulderWidth = _distancia(hombroIzq, hombroDer);
    final double anchoCaderas = (caderaIzq != null && caderaDer != null)
        ? _distancia(caderaIzq, caderaDer)
        : 0.0;

    // Alto base: distancia entre el centro de hombros y el centro de caderas.
    final double altoBase = _distanciaEntre(
      shoulderCenterX,
      shoulderCenterY,
      hipCenterX,
      hipCenterY,
    );

    // Geometría degenerada: no se genera ancla (nunca se lanza excepción).
    if (shoulderWidth <= 0 || altoBase <= 0) return null;

    // Rotación: inclinación de la línea de hombros (11 → 12).
    //
    // El ángulo se calcula en el MISMO sistema de coordenadas que ya usa
    // `PoseOverlay` para dibujar el esqueleto (la imagen viene rotada/espejada
    // desde el lado nativo).
    //
    // IMPORTANTE: la línea de hombros es una orientación NO DIRIGIDA. Al girar
    // el cuerpo (de espaldas → de frente) el vector 11→12 invierte su sentido y
    // `atan2` devolvería un ángulo cercano a ±π aunque los hombros sigan
    // visualmente horizontales. Por eso el ángulo se normaliza a (−π/2, π/2],
    // que representa la MISMA inclinación visual con o sin inversión.
    final double rotacion = _normalizarOrientacion(
      math.atan2(hombroDer.y - hombroIzq.y, hombroDer.x - hombroIzq.x),
    );
    if (rotacion.abs() > inclinacionMaximaRad) return null;

    // Geometría BASE: sin factores ni offsets (los aplica la prenda con la
    // configuración, y el rectángulo con su propio margen de diagnóstico).
    return TorsoAnchor(
      centerX: (shoulderCenterX + hipCenterX) / 2,
      centerY: (shoulderCenterY + hipCenterY) / 2,
      shoulderWidth: shoulderWidth,
      torsoHeight: altoBase,
      rotationRadians: rotacion,
      hipWidth: anchoCaderas,
    );
  }

  /// Normaliza el ángulo de una RECTA (orientación no dirigida) a (−π/2, π/2].
  ///
  /// `atan2` mide una dirección CON sentido: si el vector 11→12 apunta al lado
  /// opuesto (persona de frente en lugar de espaldas), devuelve ±π para una
  /// línea visualmente horizontal. Restar o sumar π da el ángulo equivalente de
  /// la MISMA recta, de modo que el resultado no depende del orden
  /// izquierda/derecha con que MediaPipe entregue los hombros.
  static double _normalizarOrientacion(double angulo) {
    if (angulo > math.pi / 2) return angulo - math.pi;
    if (angulo < -math.pi / 2) return angulo + math.pi;
    return angulo;
  }

  /// Distancia euclídea entre dos landmarks normalizados.
  double _distancia(PoseLandmark a, PoseLandmark b) =>
      _distanciaEntre(a.x, a.y, b.x, b.y);

  /// Distancia euclídea entre dos puntos normalizados.
  double _distanciaEntre(double x1, double y1, double x2, double y2) {
    final double dx = x2 - x1;
    final double dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
}
