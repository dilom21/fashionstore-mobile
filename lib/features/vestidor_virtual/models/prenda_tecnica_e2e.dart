// Selector técnico E2E de prendas (CU26 - Etapa 7, TEMPORAL).
//
// Este archivo NO es negocio: es el catálogo mínimo que permite validar en el
// teléfono que el MISMO motor 2D (TorsoAnchor -> VestidorConfig ->
// PrendaGeometry -> PrendaOverlay) renderiza varias prendas reales sin lógica
// especial por producto.
//
// Aquí SOLO se fijan `productoId` y la `configuracionId` preferida. Todo lo que
// define el aspecto de la prenda (assetUrl, factorAncho, factorAlto, offsetX,
// offsetY, rotacionOffset, opacidad) se obtiene del backend con
// `VestidorApiService.obtenerConfiguraciones`: nunca se hardcodea.
//
// Se elimina cuando exista la navegación definitiva desde el detalle del
// producto.

import 'vestidor_config_model.dart';

/// Una prenda de prueba del selector técnico E2E.
class PrendaTecnicaE2E {
  const PrendaTecnicaE2E({
    required this.etiqueta,
    required this.productoId,
    required this.configuracionId,
  });

  /// Nombre visible en el selector (solo para el desarrollador).
  final String etiqueta;

  /// Producto real del catálogo.
  final int productoId;

  /// Configuración AR exacta que se quiere validar en ese producto.
  final int configuracionId;

  /// Resumen corto para la UI/DEBUG.
  String get resumen => 'producto $productoId · config $configuracionId';

  /// Catálogo TEMPORAL de validación multi-prenda (Etapa 7).
  ///
  /// - producto 6 → config 56: Camiseta Essential Cotton Negra (validada en
  ///   Etapa 6).
  /// - producto 1 → config 55: Polo Premium Piqué Negro.
  /// - producto 5 → config 57: Camisa Oxford Blanca.
  ///
  /// NO incluye pantalones ni el producto 4: el motor de este parcial es
  /// TORSO / PNG_2D.
  static const List<PrendaTecnicaE2E> catalogoTecnico = <PrendaTecnicaE2E>[
    PrendaTecnicaE2E(
      etiqueta: 'Camiseta Essential Cotton Negra',
      productoId: 6,
      configuracionId: 56,
    ),
    PrendaTecnicaE2E(
      etiqueta: 'Polo Premium Piqué Negro',
      productoId: 1,
      configuracionId: 55,
    ),
    PrendaTecnicaE2E(
      etiqueta: 'Camisa Oxford Blanca',
      productoId: 5,
      configuracionId: 57,
    ),
  ];
}

/// Resultado de resolver la configuración pedida por el selector técnico.
///
/// Nunca sustituye una configuración por otra: o devuelve EXACTAMENTE la pedida
/// y compatible con el motor, o un mensaje de error controlado.
class SeleccionConfigE2E {
  const SeleccionConfigE2E._({this.configuracion, this.error});

  /// Éxito: configuración encontrada y compatible con el motor.
  const SeleccionConfigE2E.exito(VestidorConfig configuracion)
    : this._(configuracion: configuracion);

  /// Error controlado con mensaje apto para el usuario.
  const SeleccionConfigE2E.error(String error) : this._(error: error);

  /// Configuración a enviar al motor (solo si [esExito]).
  final VestidorConfig? configuracion;

  /// Mensaje de error (solo si NO es éxito).
  final String? error;

  bool get esExito => error == null;
}

/// Resuelve la configuración EXACTA pedida por el selector técnico.
///
/// Reglas de la Etapa 7:
/// - Busca por `configuracionId`; si no aparece, devuelve error y NO elige otra.
/// - Valida el contrato del motor: `tieneAsset`, `esPng2d` y `esTorso`
///   (`esUsable` queda cubierto por los dos primeros).
/// - El mensaje incluye los ids disponibles para poder corregir la prueba sin
///   adivinar.
SeleccionConfigE2E seleccionarConfiguracionE2E({
  required List<VestidorConfig> configuraciones,
  required int configuracionId,
  required int productoId,
}) {
  if (configuraciones.isEmpty) {
    return SeleccionConfigE2E.error(
      'El producto $productoId no tiene configuraciones de vestidor activas.',
    );
  }

  VestidorConfig? encontrada;
  for (final VestidorConfig config in configuraciones) {
    if (config.configuracionId == configuracionId) {
      encontrada = config;
      break;
    }
  }

  if (encontrada == null) {
    final String disponibles = configuraciones
        .map((VestidorConfig config) => config.configuracionId)
        .join(', ');
    return SeleccionConfigE2E.error(
      'No encontramos la configuración $configuracionId del producto '
      '$productoId. Disponibles: $disponibles.',
    );
  }

  if (!encontrada.tieneAsset) {
    return SeleccionConfigE2E.error(
      'La configuración $configuracionId no tiene asset_url: la prenda no se '
      'puede dibujar.',
    );
  }

  if (!encontrada.esPng2d) {
    return SeleccionConfigE2E.error(
      'La configuración $configuracionId usa tipo_asset '
      '"${encontrada.tipoAsset}": el motor de esta etapa solo renderiza PNG_2D.',
    );
  }

  if (!encontrada.esTorso) {
    return SeleccionConfigE2E.error(
      'La configuración $configuracionId es de zona "${encontrada.zonaCuerpo}": '
      'el motor de esta etapa solo dibuja prendas de TORSO.',
    );
  }

  return SeleccionConfigE2E.exito(encontrada);
}
