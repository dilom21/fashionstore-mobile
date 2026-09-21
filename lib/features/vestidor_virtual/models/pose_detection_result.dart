import 'pose_landmark.dart';

/// Resultado de una inferencia de MediaPipe Pose Landmarker (CU26 – Etapa 2C).
///
/// Modelo independiente de la UI: solo transporta datos numéricos.
class PoseDetectionResult {
  const PoseDetectionResult({
    required this.poseDetected,
    required this.timestampMs,
    required this.inferenceTimeMs,
    required this.landmarkCount,
    required this.imageWidth,
    required this.imageHeight,
    required this.isFrontCamera,
    required this.landmarks,
    required this.worldLandmarks,
  });

  /// `true` cuando MediaPipe encontró al menos una pose.
  final bool poseDetected;

  /// Marca de tiempo del frame analizado (`SystemClock.uptimeMillis`).
  final int timestampMs;

  /// Milisegundos que tardó la inferencia.
  final int inferenceTimeMs;

  /// Cantidad de landmarks recibidos (33 cuando hay pose).
  final int landmarkCount;

  /// Tamaño de la imagen analizada (ya rotada/espejada).
  final int imageWidth;
  final int imageHeight;

  /// `true` si el frame provino de la cámara frontal.
  final bool isFrontCamera;

  /// Landmarks normalizados (x/y/z en 0..1).
  final List<PoseLandmark> landmarks;

  /// Los mismos puntos en coordenadas del mundo (metros).
  final List<PoseLandmark> worldLandmarks;

  /// Devuelve el landmark con ese índice, o `null` si no está disponible.
  PoseLandmark? porIndice(int index) {
    for (final PoseLandmark punto in landmarks) {
      if (punto.index == index) return punto;
    }
    return null;
  }

  /// Crea el resultado desde el Map que envía el EventChannel.
  /// Devuelve `null` si el valor no es un mapa válido.
  static PoseDetectionResult? desdeMapa(Object? valor) {
    if (valor is! Map) return null;

    return PoseDetectionResult(
      poseDetected: valor['poseDetected'] == true,
      timestampMs: _aEntero(valor['timestampMs']) ?? 0,
      inferenceTimeMs: _aEntero(valor['inferenceTimeMs']) ?? 0,
      landmarkCount: _aEntero(valor['landmarkCount']) ?? 0,
      imageWidth: _aEntero(valor['imageWidth']) ?? 0,
      imageHeight: _aEntero(valor['imageHeight']) ?? 0,
      isFrontCamera: valor['isFrontCamera'] == true,
      landmarks: _aPuntos(valor['landmarks']),
      worldLandmarks: _aPuntos(valor['worldLandmarks']),
    );
  }

  /// Crea una copia con algunos campos reemplazados.
  ///
  /// Lo usa `PoseSmoothingService` para devolver el resultado con los landmarks
  /// filtrados sin duplicar el modelo.
  PoseDetectionResult copyWith({
    bool? poseDetected,
    int? timestampMs,
    int? inferenceTimeMs,
    int? landmarkCount,
    int? imageWidth,
    int? imageHeight,
    bool? isFrontCamera,
    List<PoseLandmark>? landmarks,
    List<PoseLandmark>? worldLandmarks,
  }) {
    return PoseDetectionResult(
      poseDetected: poseDetected ?? this.poseDetected,
      timestampMs: timestampMs ?? this.timestampMs,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
      landmarkCount: landmarkCount ?? this.landmarkCount,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      landmarks: landmarks ?? this.landmarks,
      worldLandmarks: worldLandmarks ?? this.worldLandmarks,
    );
  }

  @override
  String toString() =>
      'PoseDetectionResult(poseDetected=$poseDetected, '
      'landmarkCount=$landmarkCount, inferenceTimeMs=$inferenceTimeMs)';
}

/// Convierte la lista de landmarks del canal en modelos.
List<PoseLandmark> _aPuntos(Object? valor) {
  if (valor is! List) return const <PoseLandmark>[];

  final List<PoseLandmark> puntos = <PoseLandmark>[];
  for (final Object? item in valor) {
    final PoseLandmark? punto = PoseLandmark.desdeMapa(item);
    if (punto != null) puntos.add(punto);
  }
  return puntos;
}

/// Convierte un valor numérico del canal a `int`.
int? _aEntero(Object? valor) {
  if (valor is int) return valor;
  if (valor is double) return valor.toInt();
  return null;
}
