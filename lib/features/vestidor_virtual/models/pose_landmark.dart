/// Punto corporal detectado por MediaPipe (CU26 – Etapa 2C).
///
/// Modelo independiente de la UI: solo transporta datos.
class PoseLandmark {
  const PoseLandmark({
    required this.index,
    required this.x,
    required this.y,
    required this.z,
    this.visibility,
    this.presence,
  });

  /// Posición del punto dentro de la lista de MediaPipe (0..32).
  ///
  /// MediaPipe no expone el índice dentro del punto: es su posición en la
  /// lista, que se conserva en el orden oficial de 33 landmarks.
  final int index;

  /// Coordenadas normalizadas (x e y en 0..1 respecto de la imagen analizada).
  final double x;
  final double y;

  /// Profundidad relativa (menor = más cerca de la cámara).
  final double z;

  /// Confianza de visibilidad. Kotlin envía `null` si MediaPipe no la da.
  final double? visibility;

  /// Confianza de presencia. Kotlin envía `null` si MediaPipe no la da.
  final double? presence;

  /// Crea un landmark desde el Map que envía el EventChannel.
  /// Devuelve `null` si el punto viene incompleto.
  static PoseLandmark? desdeMapa(Object? valor) {
    if (valor is! Map) return null;

    final int? indice = _aEntero(valor['index']);
    final double? x = _aDecimal(valor['x']);
    final double? y = _aDecimal(valor['y']);
    final double? z = _aDecimal(valor['z']);
    if (indice == null || x == null || y == null || z == null) return null;

    return PoseLandmark(
      index: indice,
      x: x,
      y: y,
      z: z,
      visibility: _aDecimal(valor['visibility']),
      presence: _aDecimal(valor['presence']),
    );
  }

  @override
  String toString() =>
      'PoseLandmark($index: x=$x, y=$y, z=$z, visibility=$visibility, '
      'presence=$presence)';
}

/// Convierte un valor numérico del canal a `int`.
int? _aEntero(Object? valor) {
  if (valor is int) return valor;
  if (valor is double) return valor.toInt();
  return null;
}

/// Convierte un valor numérico del canal a `double`.
double? _aDecimal(Object? valor) {
  if (valor is double) return valor;
  if (valor is int) return valor.toDouble();
  return null;
}
