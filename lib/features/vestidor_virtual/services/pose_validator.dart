import 'dart:math' as math;

import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';

/// Índice del hombro izquierdo de la persona.
const int indiceHombroIzquierdo = 11;

/// Índice del hombro derecho de la persona.
const int indiceHombroDerecho = 12;

/// Índice de la cadera izquierda de la persona.
const int indiceCaderaIzquierda = 23;

/// Índice de la cadera derecha de la persona.
const int indiceCaderaDerecha = 24;

/// Estado de la pose visto por el vestidor (no por MediaPipe).
enum EstadoPose {
  /// MediaPipe no detecta nada (equivale a NO_POSE).
  sinPose,

  /// MediaPipe detecta algo, pero no sirve para el vestidor (POSE_INSUFICIENTE).
  insuficiente,

  /// Hombros y caderas suficientemente fiables (POSE_VALIDA).
  valida,
}

/// Resultado de validar un frame.
class PoseValidation {
  const PoseValidation(this.estado, {this.motivo});

  final EstadoPose estado;

  /// Explicación técnica del rechazo. Es solo para diagnóstico/log: la UI
  /// muestra mensajes simples.
  final String? motivo;

  /// `true` cuando la pose se puede usar para el vestidor.
  bool get esValida => estado == EstadoPose.valida;
}

/// Comprueba que exista una geometría corporal suficiente para el vestidor.
///
/// **Separación de responsabilidades (Etapa 4 corregida):** este validador NO
/// decide si MediaPipe puede dibujar el esqueleto. MediaPipe manda sobre la
/// DETECCIÓN (`poseDetected`) y el esqueleto de diagnóstico se dibuja siempre
/// que haya pose; esto solo decide si la pose es **utilizable para una prenda**
/// (hombros/torso fiables), que es lo que la UI muestra como "Pose lista".
///
/// No pretende decidir si hay un "humano" (no hay IA adicional): usar
/// thresholds para intentar bloquear objetos con geometría humanoide acaba
/// rechazando personas reales. La prioridad es no rechazar personas.
///
/// Todos los umbrales son constantes documentadas y ajustables desde el
/// constructor (los thresholds nativos de MediaPipe NO se han tocado).
class PoseValidator {
  const PoseValidator({
    this.minVisibilidadHombros = minVisibilidadHombrosPorDefecto,
    this.minPresenciaHombros = minPresenciaHombrosPorDefecto,
    this.minVisibilidadCaderas = minVisibilidadCaderasPorDefecto,
    this.minPresenciaCaderas = minPresenciaCaderasPorDefecto,
    this.toleranciaBordeHombros = toleranciaBordeHombrosPorDefecto,
    this.toleranciaBordeCaderas = toleranciaBordeCaderasPorDefecto,
    this.minDistanciaHombros = minDistanciaHombrosPorDefecto,
    this.minDistanciaTorso = minDistanciaTorsoPorDefecto,
    this.minSeparacionHombros = minSeparacionHombrosPorDefecto,
    this.minSeparacionCaderas = minSeparacionCaderasPorDefecto,
  });

  /// Visibilidad mínima de los HOMBROS, que son el anclaje de las prendas
  /// superiores y por tanto el requisito principal.
  ///
  /// Calibrado con log real en teléfono: hombros útiles aparecían entre 0.45 y
  /// 0.59, así que el 0.60 anterior rechazaba personas perfectamente válidas.
  static const double minVisibilidadHombrosPorDefecto = 0.45;

  /// Presencia mínima de los HOMBROS (misma justificación que la visibilidad).
  static const double minPresenciaHombrosPorDefecto = 0.45;

  /// Visibilidad mínima de las CADERAS: son apoyo (encuadre/escala) y suelen
  /// quedar parcialmente visibles, por eso el umbral es más bajo que el de los
  /// hombros y no se exigen ambas.
  static const double minVisibilidadCaderasPorDefecto = 0.25;

  /// Presencia mínima de las CADERAS (misma justificación).
  static const double minPresenciaCaderasPorDefecto = 0.25;

  /// Distancia mínima entre hombros, en coordenadas normalizadas. Si es menor,
  /// la persona está demasiado lejos (o la detección es degenerada).
  static const double minDistanciaHombrosPorDefecto = 0.06;

  /// Altura mínima hombros→caderas, en coordenadas normalizadas (el torso debe
  /// ocupar una porción apreciable del cuadro).
  static const double minDistanciaTorsoPorDefecto = 0.10;

  /// Separación mínima entre hombros para descartar detecciones degeneradas
  /// (ambos hombros prácticamente en el mismo punto).
  static const double minSeparacionHombrosPorDefecto = 0.02;

  /// Separación mínima entre caderas (mismo criterio que los hombros).
  static const double minSeparacionCaderasPorDefecto = 0.02;

  /// Banda tolerante alrededor del cuadro para los HOMBROS.
  ///
  /// MediaPipe estima x/y ligeramente fuera de 0..1 cuando una articulación
  /// está justo en el borde; rechazar la pose completa por eso hacía
  /// desaparecer el esqueleto. 0.10 = 10 % del cuadro a cada lado.
  static const double toleranciaBordeHombrosPorDefecto = 0.10;

  /// Banda tolerante para las CADERAS, más amplia porque pueden estar
  /// parcialmente fuera del cuadro (persona algo cerca) sin invalidar el torso.
  static const double toleranciaBordeCaderasPorDefecto = 0.20;

  final double minVisibilidadHombros;
  final double minPresenciaHombros;
  final double minVisibilidadCaderas;
  final double minPresenciaCaderas;
  final double toleranciaBordeHombros;
  final double toleranciaBordeCaderas;
  final double minDistanciaHombros;
  final double minDistanciaTorso;
  final double minSeparacionHombros;
  final double minSeparacionCaderas;

  /// Valida el frame y devuelve el estado que usará el vestidor.
  ///
  /// NO decide si MediaPipe puede dibujar el esqueleto: eso depende solo de
  /// `poseDetected`. Aquí se decide únicamente si la pose sirve para colocar
  /// una prenda ("Pose lista").
  PoseValidation validar(PoseDetectionResult resultado) {
    if (!resultado.poseDetected) {
      return const PoseValidation(
        EstadoPose.sinPose,
        motivo: 'MediaPipe no detectó pose.',
      );
    }

    final PoseLandmark? hombroIzq = resultado.porIndice(indiceHombroIzquierdo);
    final PoseLandmark? hombroDer = resultado.porIndice(indiceHombroDerecho);
    final PoseLandmark? caderaIzq = resultado.porIndice(indiceCaderaIzquierda);
    final PoseLandmark? caderaDer = resultado.porIndice(indiceCaderaDerecha);

    // Los HOMBROS son el anclaje de las prendas superiores: se exigen ambos.
    if (hombroIzq == null || hombroDer == null) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Faltan los hombros.',
      );
    }
    for (final MapEntry<String, PoseLandmark> entrada in <String, PoseLandmark>{
      'hombro izquierdo (11)': hombroIzq,
      'hombro derecho (12)': hombroDer,
    }.entries) {
      final String? problema = _revisarPunto(
        entrada.value,
        tolerancia: toleranciaBordeHombros,
        minVisibilidad: minVisibilidadHombros,
        minPresencia: minPresenciaHombros,
      );
      if (problema != null) {
        return PoseValidation(
          EstadoPose.insuficiente,
          motivo: '${entrada.key}: $problema',
        );
      }
    }

    // Las CADERAS son apoyo (encuadre/escala): basta con UNA, porque suelen
    // quedar parcialmente fuera del cuadro si la persona está algo cerca.
    final List<PoseLandmark> caderas = <PoseLandmark>[?caderaIzq, ?caderaDer];
    if (caderas.isEmpty) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Faltan las caderas.',
      );
    }
    for (final PoseLandmark cadera in caderas) {
      final String? problema = _revisarPunto(
        cadera,
        tolerancia: toleranciaBordeCaderas,
        minVisibilidad: minVisibilidadCaderas,
        minPresencia: minPresenciaCaderas,
      );
      if (problema != null) {
        return PoseValidation(
          EstadoPose.insuficiente,
          motivo: 'cadera (${cadera.index}): $problema',
        );
      }
    }

    final double distanciaHombros = _distancia(hombroIzq, hombroDer);
    if (distanciaHombros < minSeparacionHombros) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Hombros prácticamente en el mismo punto.',
      );
    }
    if (distanciaHombros < minDistanciaHombros) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Hombros demasiado juntos (persona muy lejos).',
      );
    }
    if (caderaIzq != null &&
        caderaDer != null &&
        _distancia(caderaIzq, caderaDer) < minSeparacionCaderas) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Caderas prácticamente en el mismo punto.',
      );
    }

    final double centroHombrosY = (hombroIzq.y + hombroDer.y) / 2;
    double sumaCaderasY = 0;
    for (final PoseLandmark cadera in caderas) {
      sumaCaderasY += cadera.y;
    }
    final double centroCaderasY = sumaCaderasY / caderas.length;
    final double alturaTorso = centroCaderasY - centroHombrosY;
    if (alturaTorso < minDistanciaTorso) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo:
            'Torso insuficiente (hombros y caderas muy juntos o invertidos).',
      );
    }

    return const PoseValidation(EstadoPose.valida);
  }

  /// Motivo por el que un punto no sirve, o `null` si es aceptable.
  ///
  /// [tolerancia] es la banda alrededor del cuadro: un punto puede estar
  /// ligeramente fuera de 0..1 y seguir siendo válido (nunca se ajusta su
  /// posición, solo se permite).
  String? _revisarPunto(
    PoseLandmark punto, {
    required double tolerancia,
    required double minVisibilidad,
    required double minPresencia,
  }) {
    if (punto.x < -tolerancia ||
        punto.x > 1 + tolerancia ||
        punto.y < -tolerancia ||
        punto.y > 1 + tolerancia) {
      return 'fuera del cuadro (banda ±${tolerancia.toStringAsFixed(2)})';
    }

    // Si MediaPipe no informa visibilidad/presencia, el punto no se descarta por
    // eso: la comprobación geométrica posterior sigue siendo obligatoria.
    final double? visibilidad = punto.visibility;
    if (visibilidad != null && visibilidad < minVisibilidad) {
      return 'visibilidad ${visibilidad.toStringAsFixed(2)} < $minVisibilidad';
    }
    final double? presencia = punto.presence;
    if (presencia != null && presencia < minPresencia) {
      return 'presencia ${presencia.toStringAsFixed(2)} < $minPresencia';
    }
    return null;
  }

  /// Distancia euclídea entre dos landmarks en coordenadas normalizadas.
  double _distancia(PoseLandmark a, PoseLandmark b) {
    final double dx = a.x - b.x;
    final double dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
