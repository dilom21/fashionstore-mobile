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
/// No pretende decidir si hay un "humano" (no hay IA adicional): solo verifica
/// que los cuatro puntos que necesitan las prendas superiores (hombros 11/12 y
/// caderas 23/24) sean fiables y coherentes.
///
/// Todos los umbrales son constantes documentadas y ajustables desde el
/// constructor; los valores por defecto son deliberadamente permisivos para no
/// perjudicar a personas parcialmente visibles, con poca luz o con cámaras de
/// menor calidad (los thresholds nativos de MediaPipe NO se han tocado).
class PoseValidator {
  const PoseValidator({
    this.minVisibilidad = minVisibilidadPorDefecto,
    this.minPresencia = minPresenciaPorDefecto,
    this.minDistanciaHombros = minDistanciaHombrosPorDefecto,
    this.minDistanciaTorso = minDistanciaTorsoPorDefecto,
    this.minSeparacionHombros = minSeparacionHombrosPorDefecto,
    this.minSeparacionCaderas = minSeparacionCaderasPorDefecto,
  });

  /// Visibilidad mínima de cada punto clave (0..1).
  static const double minVisibilidadPorDefecto = 0.60;

  /// Presencia mínima de cada punto clave (0..1).
  static const double minPresenciaPorDefecto = 0.60;

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

  /// Rango aceptado para x/y (los puntos fuera del cuadro no sirven).
  static const double rangoMinimo = 0.0;
  static const double rangoMaximo = 1.0;

  final double minVisibilidad;
  final double minPresencia;
  final double minDistanciaHombros;
  final double minDistanciaTorso;
  final double minSeparacionHombros;
  final double minSeparacionCaderas;

  /// Valida el frame y devuelve el estado que usará el vestidor.
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

    if (hombroIzq == null ||
        hombroDer == null ||
        caderaIzq == null ||
        caderaDer == null) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Faltan hombros o caderas.',
      );
    }

    final Map<String, PoseLandmark> claves = <String, PoseLandmark>{
      'hombro izquierdo (11)': hombroIzq,
      'hombro derecho (12)': hombroDer,
      'cadera izquierda (23)': caderaIzq,
      'cadera derecha (24)': caderaDer,
    };
    for (final MapEntry<String, PoseLandmark> entrada in claves.entries) {
      final String? problema = _revisarPunto(entrada.value);
      if (problema != null) {
        return PoseValidation(
          EstadoPose.insuficiente,
          motivo: '${entrada.key}: $problema',
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
    if (_distancia(caderaIzq, caderaDer) < minSeparacionCaderas) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Caderas prácticamente en el mismo punto.',
      );
    }

    final double centroHombrosY = (hombroIzq.y + hombroDer.y) / 2;
    final double centroCaderasY = (caderaIzq.y + caderaDer.y) / 2;
    final double alturaTorso = centroCaderasY - centroHombrosY;
    if (alturaTorso < minDistanciaTorso) {
      return const PoseValidation(
        EstadoPose.insuficiente,
        motivo: 'Torso insuficiente (hombros y caderas muy juntos o invertidos).',
      );
    }

    return const PoseValidation(EstadoPose.valida);
  }

  /// Motivo por el que un punto no sirve, o `null` si es aceptable.
  String? _revisarPunto(PoseLandmark punto) {
    if (punto.x < rangoMinimo ||
        punto.x > rangoMaximo ||
        punto.y < rangoMinimo ||
        punto.y > rangoMaximo) {
      return 'fuera del cuadro';
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
