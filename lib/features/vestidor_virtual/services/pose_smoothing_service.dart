import '../models/pose_detection_result.dart';
import '../models/pose_landmark.dart';

/// Filtro EMA (Exponential Moving Average) aplicado por índice de landmark.
///
/// Fórmula por punto:
/// `filtrado = alpha * actual + (1 - alpha) * anterior`
///
/// Cómo elegir `alpha` (se calibrará físicamente en teléfono):
/// - **alpha alto** (p. ej. 0.8): sigue el movimiento casi sin retraso, suaviza poco.
/// - **alpha bajo** (p. ej. 0.2): muy suave, pero produce "arrastre" (el
///   esqueleto llega tarde al mover el brazo).
/// El valor por defecto ([alphaPorDefecto]) busca reducir vibración/jitter sin
/// un retraso perceptible.
///
/// `visibility` y `presence` NO se suavizan: se conservan del frame actual.
class PoseSmoothingService {
  PoseSmoothingService({
    this.alpha = alphaPorDefecto,
    this.framesParaReset = framesParaResetPorDefecto,
  }) : assert(alpha > 0 && alpha <= 1, 'alpha debe estar en (0, 1]'),
       assert(framesParaReset > 0, 'framesParaReset debe ser positivo');

  /// Peso del frame actual (calibrable).
  static const double alphaPorDefecto = 0.35;

  /// Frames consecutivos NO utilizables antes de borrar el estado del filtro.
  static const int framesParaResetPorDefecto = 8;

  final double alpha;
  final int framesParaReset;

  /// Últimos valores filtrados, por índice de landmark (nunca se mezclan índices).
  final Map<int, _PuntoFiltrado> _estado = <int, _PuntoFiltrado>{};

  int _framesSinPose = 0;

  /// `true` si el filtro tiene valores previos.
  bool get tieneEstado => _estado.isNotEmpty;

  /// Devuelve una copia del resultado con x/y/z suavizados.
  ///
  /// Los índices que aparecen por primera vez arrancan con su valor actual.
  /// Los worldLandmarks se devuelven sin suavizar.
  PoseDetectionResult filtrar(PoseDetectionResult crudo) {
    if (!crudo.poseDetected || crudo.landmarks.isEmpty) {
      // Sin pose utilizable: se cuenta para el reset y se devuelve tal cual.
      perderPose();
      return crudo;
    }

    _framesSinPose = 0;
    final List<PoseLandmark> suavizados = <PoseLandmark>[];

    for (final PoseLandmark actual in crudo.landmarks) {
      final _PuntoFiltrado? previo = _estado[actual.index];
      final _PuntoFiltrado filtrado = previo == null
          ? _PuntoFiltrado(x: actual.x, y: actual.y, z: actual.z)
          : _PuntoFiltrado(
              x: alpha * actual.x + (1 - alpha) * previo.x,
              y: alpha * actual.y + (1 - alpha) * previo.y,
              z: alpha * actual.z + (1 - alpha) * previo.z,
            );
      _estado[actual.index] = filtrado;

      suavizados.add(
        PoseLandmark(
          index: actual.index,
          x: filtrado.x,
          y: filtrado.y,
          z: filtrado.z,
          visibility: actual.visibility,
          presence: actual.presence,
        ),
      );
    }

    return crudo.copyWith(
      landmarks: suavizados,
      landmarkCount: suavizados.length,
    );
  }

  /// Registra un frame no utilizable (sin pose o pose insuficiente).
  ///
  /// Al acumular [framesParaReset] frames así, el estado se borra para no
  /// arrastrar la última pose válida.
  void perderPose() {
    _framesSinPose++;
    if (_framesSinPose >= framesParaReset) reset();
  }

  /// Borra el estado del filtro (el siguiente frame arranca de cero).
  void reset() {
    _estado.clear();
    _framesSinPose = 0;
  }
}

/// Último valor filtrado de un landmark (x/y/z normalizados).
class _PuntoFiltrado {
  const _PuntoFiltrado({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;
}
