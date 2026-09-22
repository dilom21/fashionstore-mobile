import 'dart:math' as math;

import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';
import '../models/torso_anchor.dart';
import 'pose_validator.dart';

/// Calcula el [TorsoAnchor] (Etapa 5) a partir de un resultado de pose **ya
/// estabilizado** por `PoseSmoothingService`.
///
/// Solo geometría: no lee cámara, no hace HTTP, no consulta backend ni Supabase
/// y no valida la pose por su cuenta (esa decisión ya la tomó `PoseValidator`).
/// Si faltan landmarks o la geometría es degenerada, devuelve `null` en lugar de
/// lanzar excepciones por un frame incompleto.
///
/// **Factores y offsets centralizados aquí** (no dentro del painter): la Etapa 6
/// reutilizará este mismo ancla para colocar la prenda.
///
/// Nota: `VestidorConfig` (rama dev-josias) NO se copia ni se recrea en esta
/// etapa; estos parámetros son locales del motor AR.
class TorsoAnchorService {
  const TorsoAnchorService({
    this.factorAncho = factorAnchoPorDefecto,
    this.factorAlto = factorAltoPorDefecto,
    this.offsetX = offsetXPorDefecto,
    this.offsetY = offsetYPorDefecto,
    this.rotationOffset = rotationOffsetPorDefecto,
    this.inclinacionMaximaRad = inclinacionMaximaPorDefecto,
  });

  /// Ancho del ancla = ancho de hombros × [factorAncho].
  ///
  /// El ancho se toma SOLO de los hombros (no se combina con caderas): para una
  /// prenda superior la línea de hombros es la referencia estable, y las caderas
  /// pueden faltar. 1.15 da un margen para que la futura prenda caiga sobre el
  /// cuerpo y no quede corta en los costados.
  static const double factorAnchoPorDefecto = 1.15;

  /// Alto del ancla = distancia hombros→caderas × [factorAlto].
  ///
  /// 1.15 estira un poco el alto para que la caja cubra hasta la cadera.
  static const double factorAltoPorDefecto = 1.15;

  /// Desplazamiento fino del centro, en coordenadas normalizadas de la imagen.
  static const double offsetXPorDefecto = 0.0;
  static const double offsetYPorDefecto = 0.0;

  /// Corrección de giro (radianes) para calibrar contra el preview.
  static const double rotationOffsetPorDefecto = 0.0;

  /// Inclinación máxima aceptada de la línea de hombros (radianes).
  ///
  /// 1.05 rad ≈ 60°: más que eso significa que los hombros están prácticamente
  /// verticales en la imagen (pose girada/caída) y la caja no aportaría nada.
  static const double inclinacionMaximaPorDefecto = 1.05;

  final double factorAncho;
  final double factorAlto;
  final double offsetX;
  final double offsetY;
  final double rotationOffset;
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
    // desde el lado nativo), así que la caja gira coherente con lo que se ve.
    final double rotacion =
        math.atan2(hombroDer.y - hombroIzq.y, hombroDer.x - hombroIzq.x) +
        rotationOffset;
    if (rotacion.abs() > inclinacionMaximaRad) return null;

    return TorsoAnchor(
      centerX: (shoulderCenterX + hipCenterX) / 2 + offsetX,
      centerY: (shoulderCenterY + hipCenterY) / 2 + offsetY,
      width: shoulderWidth * factorAncho,
      height: altoBase * factorAlto,
      rotationRadians: rotacion,
      shoulderWidth: shoulderWidth,
      hipWidth: anchoCaderas,
    );
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
