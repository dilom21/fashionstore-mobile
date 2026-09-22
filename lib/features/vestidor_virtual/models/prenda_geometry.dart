import 'torso_anchor.dart';
import 'vestidor_config_model.dart';

/// Geometría final de la prenda 2D (Etapa 6), en coordenadas normalizadas.
///
/// Es el resultado de aplicar [VestidorConfig] sobre el [TorsoAnchor] **base**,
/// UNA sola vez y SIN ningún multiplicador local adicional. Principio del CU26:
/// `TorsoAnchor` = geometría corporal base, `VestidorConfig` = única fuente de
/// calibración de cada prenda, `PrendaGeometry` = aplicación directa.
///
/// ```
/// width    = anchor.shoulderWidth   * config.factorAncho
/// height   = anchor.torsoHeight     * config.factorAlto
/// centerX  = anchor.centerX         + config.offsetX
/// centerY  = anchor.centerY         + config.offsetY
/// rotation = anchor.rotationRadians + config.rotacionOffset
/// opacidad = config.opacidad limitada a 0..1
/// ```
///
/// Modelo puro (sin UI y sin red) para poder verificarlo con tests. El margen
/// 1.15 del rectángulo de diagnóstico NO interviene aquí: vive en
/// `TorsoAnchorOverlay`, así que la prenda nunca multiplica ese factor.
class PrendaGeometry {
  const PrendaGeometry({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.rotationRadians,
    required this.opacidad,
  });

  /// Calcula la geometría de la prenda, o `null` si no se debe renderizar.
  ///
  /// Devuelve `null` cuando: no hay ancla válida, la configuración no es
  /// utilizable (sin `assetUrl`, tipo distinto de `PNG_2D` o zona distinta de
  /// `TORSO`) o el tamaño resultante es degenerado.
  static PrendaGeometry? desde({
    required TorsoAnchor? anchor,
    required VestidorConfig configuracion,
  }) {
    if (anchor == null || !anchor.esValido) return null;
    if (!configuracion.tieneAsset ||
        !configuracion.esPng2d ||
        !configuracion.esTorso) {
      return null;
    }

    final PrendaGeometry geometria = PrendaGeometry(
      centerX: anchor.centerX + configuracion.offsetX,
      centerY: anchor.centerY + configuracion.offsetY,
      width: anchor.shoulderWidth * configuracion.factorAncho,
      height: anchor.torsoHeight * configuracion.factorAlto,
      rotationRadians: anchor.rotationRadians + configuracion.rotacionOffset,
      opacidad: limitarOpacidad(configuracion.opacidad),
    );

    if (geometria.width <= 0 || geometria.height <= 0) return null;
    return geometria;
  }

  /// Limita la opacidad al rango pintable (0..1).
  static double limitarOpacidad(double valor) =>
      valor.clamp(0.0, 1.0).toDouble();

  /// Centro de la prenda (normalizado).
  final double centerX;
  final double centerY;

  /// Ancho de la prenda (normalizado, ya escalado por la configuración).
  final double width;

  /// Alto de la prenda (normalizado, ya escalado por la configuración).
  final double height;

  /// Giro de la prenda en radianes (inclinación del torso + offset).
  final double rotationRadians;

  /// Opacidad final (0..1).
  final double opacidad;

  /// `true` cuando la prenda se puede dibujar.
  bool get esVisible => width > 0 && height > 0 && opacidad > 0;

  @override
  String toString() =>
      'PrendaGeometry(center=(${centerX.toStringAsFixed(3)}, '
      '${centerY.toStringAsFixed(3)}), width=${width.toStringAsFixed(3)}, '
      'height=${height.toStringAsFixed(3)}, '
      'rot=${rotationRadians.toStringAsFixed(3)}, '
      'op=${opacidad.toStringAsFixed(2)})';
}
