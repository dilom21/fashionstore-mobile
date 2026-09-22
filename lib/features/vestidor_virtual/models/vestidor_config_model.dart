// Modelos de negocio de CU26 - Vestidor virtual AR (parte Josias).
//
// Independientes del motor AR de Harold: NO importan MediaPipe, CameraX ni
// ninguna clase de pose/cámara. Solo mapean el contrato JSON del backend
// FastAPI (snake_case) a nombres Dart idiomáticos (camelCase):
//   configuracion_id -> configuracionId
//   recurso_producto_id -> recursoProductoId
//   asset_url -> assetUrl
//   zona_cuerpo -> zonaCuerpo
//   tipo_asset -> tipoAsset
//   factor_ancho -> factorAncho
//   factor_alto -> factorAlto
//   rotacion_offset -> rotacionOffset
//   orden_capa -> ordenCapa
//
// El parsing es defensivo: los Decimal del backend pueden llegar como number o
// string, y color/color_id pueden ser null (asset genérico del producto).

/// Configuración AR de un producto lista para el motor de vestidor.
///
/// Es el contrato estable acordado con Harold: el motor recibe este DTO y NUNCA
/// hace requests HTTP ni conoce Supabase.
class VestidorConfig {
  const VestidorConfig({
    required this.configuracionId,
    required this.productoId,
    required this.assetUrl,
    required this.zonaCuerpo,
    required this.tipoAsset,
    required this.factorAncho,
    required this.factorAlto,
    required this.offsetX,
    required this.offsetY,
    required this.rotacionOffset,
    required this.ordenCapa,
    required this.opacidad,
    this.colorId,
    this.color,
  });

  factory VestidorConfig.fromJson(
    Map<String, dynamic> json, {
    int? productoId,
  }) => VestidorConfig(
    configuracionId: _toInt(json['configuracion_id']),
    productoId: productoId ?? _toInt(json['producto_id']),
    assetUrl: _toString(json['asset_url']),
    colorId: _toNullableInt(json['color_id']),
    color: _toNullableString(json['color']),
    zonaCuerpo: _toString(json['zona_cuerpo']),
    tipoAsset: _toString(json['tipo_asset']),
    factorAncho: _toDouble(json['factor_ancho']),
    factorAlto: _toDouble(json['factor_alto']),
    offsetX: _toDouble(json['offset_x']),
    offsetY: _toDouble(json['offset_y']),
    rotacionOffset: _toDouble(json['rotacion_offset']),
    ordenCapa: _toInt(json['orden_capa']),
    opacidad: _toDouble(json['opacidad']),
  );

  final int configuracionId;
  final int productoId;

  /// URL del PNG transparente preparado para try-on.
  final String assetUrl;

  /// Color del recurso AR, si aplica (asset específico por color).
  final int? colorId;
  final String? color;

  /// Zona del cuerpo (para este parcial siempre `TORSO`).
  final String zonaCuerpo;

  /// Tipo de asset (`PNG_2D` para este parcial).
  final String tipoAsset;

  final double factorAncho;
  final double factorAlto;
  final double offsetX;
  final double offsetY;
  final double rotacionOffset;
  final int ordenCapa;
  final double opacidad;

  /// Una configuración compatible SIEMPRE debe traer un asset utilizable.
  bool get tieneAsset => assetUrl.trim().isNotEmpty;

  bool get esPng2d => tipoAsset.trim().toUpperCase() == 'PNG_2D';

  bool get esTorso => zonaCuerpo.trim().toUpperCase() == 'TORSO';

  /// Indica si puede alimentar al motor AR (asset + tipo soportado).
  bool get esUsable => tieneAsset && esPng2d;

  String get colorEtiqueta {
    final String texto = (color ?? '').trim();
    return texto.isEmpty ? 'Color único' : texto;
  }
}

/// Respuesta de `GET /vestidor-virtual/productos/{id}/configuraciones`.
class VestidorConfiguracionesResponse {
  const VestidorConfiguracionesResponse({
    required this.productoId,
    required this.compatible,
    required this.configuraciones,
  });

  factory VestidorConfiguracionesResponse.fromJson(Map<String, dynamic> json) {
    final int productoId = _toInt(json['producto_id']);
    final List<VestidorConfig> configuraciones = _listaDe(
      json['configuraciones'],
      (Map<String, dynamic> item) =>
          VestidorConfig.fromJson(item, productoId: productoId),
    );
    return VestidorConfiguracionesResponse(
      productoId: productoId,
      compatible: _toBool(json['compatible']) && configuraciones.isNotEmpty,
      configuraciones: configuraciones,
    );
  }

  final int productoId;

  /// `true` solo si el producto tiene al menos una configuración AR activa.
  final bool compatible;

  final List<VestidorConfig> configuraciones;

  bool get estaVacio => configuraciones.isEmpty;

  /// Primera configuración usable por el motor, si existe.
  VestidorConfig? get primeraUsable {
    for (final VestidorConfig config in configuraciones) {
      if (config.esUsable) return config;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// Helpers de parsing (solo frontera JSON)
// -----------------------------------------------------------------------------

List<T> _listaDe<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is! List) return <T>[];
  final List<T> resultado = <T>[];
  for (final Object? item in value) {
    if (item is Map<String, dynamic>) {
      resultado.add(fromJson(item));
    } else if (item is Map) {
      resultado.add(fromJson(item.cast<String, dynamic>()));
    }
  }
  return resultado;
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _toNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double _toDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

bool _toBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final String normalizado = value.toLowerCase().trim();
    if (normalizado == 'true' || normalizado == '1') return true;
    if (normalizado == 'false' || normalizado == '0') return false;
  }
  return fallback;
}

String _toString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

String? _toNullableString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final String limpio = value.trim();
    return limpio.isEmpty ? null : limpio;
  }
  return value.toString();
}
