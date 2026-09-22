// Pruebas del selector técnico E2E (CU26 - Etapa 7).
//
// Verifican SOLO la selección de la configuración pedida: producto → config
// preferida, ausencia de la config requerida (error controlado, NUNCA se
// sustituye por otra prenda) y configuraciones incompatibles con el motor.
// No tocan cámara, MediaPipe ni red: el JSON se parsea con el modelo real del
// contrato del backend.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/vestidor_virtual/models/prenda_tecnica_e2e.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';

/// JSON de una configuración con los campos reales del backend.
///
/// Los numéricos se tipan como `Object` a propósito: el backend puede mandar
/// `1.45` (number) o `"1.45"` (Decimal serializado como string).
Map<String, dynamic> _configJson({
  required int configuracionId,
  int? colorId,
  String? color,
  String assetUrl = 'https://cdn.test/prenda.png',
  String zonaCuerpo = 'TORSO',
  String tipoAsset = 'PNG_2D',
  Object factorAncho = 1.45,
  Object factorAlto = 1.55,
  Object offsetX = 0,
  Object offsetY = 0.05,
  Object rotacionOffset = 0,
  Object opacidad = 1,
}) => <String, dynamic>{
  'configuracion_id': configuracionId,
  'recurso_producto_id': 99,
  'asset_url': assetUrl,
  'color_id': colorId,
  'color': color,
  'zona_cuerpo': zonaCuerpo,
  'tipo_asset': tipoAsset,
  'factor_ancho': factorAncho,
  'factor_alto': factorAlto,
  'offset_x': offsetX,
  'offset_y': offsetY,
  'rotacion_offset': rotacionOffset,
  'orden_capa': 1,
  'opacidad': opacidad,
};

/// Respuesta del backend tal como la parsea el modelo del contrato.
VestidorConfiguracionesResponse _respuesta(
  int productoId,
  List<Map<String, dynamic>> configuraciones,
) => VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
  'producto_id': productoId,
  'compatible': configuraciones.isNotEmpty,
  'configuraciones': configuraciones,
});

/// Aplica la selección del launcher técnico a una prenda del catálogo.
SeleccionConfigE2E _seleccionar(
  PrendaTecnicaE2E prenda,
  VestidorConfiguracionesResponse respuesta,
) => seleccionarConfiguracionE2E(
  configuraciones: respuesta.configuraciones,
  configuracionId: prenda.configuracionId,
  productoId: prenda.productoId,
);

void main() {
  group('Catálogo técnico E2E (Etapa 7)', () {
    test('contiene producto 6/56, producto 1/55 y producto 5/57', () {
      final List<PrendaTecnicaE2E> catalogo = PrendaTecnicaE2E.catalogoTecnico;

      expect(catalogo.length, 3);
      expect(
        catalogo.map(
          (PrendaTecnicaE2E prenda) =>
              '${prenda.productoId}/${prenda.configuracionId}',
        ),
        <String>['6/56', '1/55', '5/57'],
      );
      expect(
        catalogo.every(
          (PrendaTecnicaE2E prenda) => prenda.etiqueta.trim().isNotEmpty,
        ),
        isTrue,
      );
      expect(catalogo[0].resumen, 'producto 6 · config 56');
    });

    test('no incluye pantalones ni el producto 4 en esta etapa', () {
      final List<PrendaTecnicaE2E> catalogo = PrendaTecnicaE2E.catalogoTecnico;

      expect(
        catalogo.where((PrendaTecnicaE2E p) => p.productoId == 4),
        isEmpty,
      );
      // Cada prenda apunta a una configuración distinta (sin duplicados).
      expect(
        catalogo
            .map((PrendaTecnicaE2E prenda) => prenda.configuracionId)
            .toSet()
            .length,
        catalogo.length,
      );
    });
  });

  group('Selección producto → config preferida', () {
    test('producto 6 elige la configuración 56', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[0],
        _respuesta(6, <Map<String, dynamic>>[
          _configJson(configuracionId: 56, colorId: 1, color: 'Negro'),
        ]),
      );

      expect(seleccion.esExito, isTrue);
      expect(seleccion.configuracion!.configuracionId, 56);
      expect(seleccion.configuracion!.productoId, 6);
      expect(seleccion.error, isNull);
    });

    test('producto 1 elige la configuración 55', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[1],
        _respuesta(1, <Map<String, dynamic>>[
          _configJson(configuracionId: 55, colorId: 2, color: 'Negro'),
        ]),
      );

      expect(seleccion.esExito, isTrue);
      expect(seleccion.configuracion!.configuracionId, 55);
      expect(seleccion.configuracion!.productoId, 1);
    });

    test('producto 5 elige la 57 aunque el backend devuelva varias', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[2],
        _respuesta(5, <Map<String, dynamic>>[
          _configJson(configuracionId: 50, color: 'Azul'),
          _configJson(configuracionId: 57, color: 'Blanco'),
          _configJson(configuracionId: 58, color: 'Rojo'),
        ]),
      );

      expect(seleccion.esExito, isTrue);
      expect(seleccion.configuracion!.configuracionId, 57);
      expect(seleccion.configuracion!.colorEtiqueta, 'Blanco');
    });

    test('la configuración elegida conserva los valores del backend', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[0],
        _respuesta(6, <Map<String, dynamic>>[
          _configJson(
            configuracionId: 56,
            assetUrl: 'https://cdn.test/camiseta-negra-tryon.png',
            // El backend manda Decimal como string: debe parsearse igual.
            factorAncho: '1.45',
            factorAlto: '1.55',
            offsetY: '0.05',
          ),
        ]),
      );

      final VestidorConfig config = seleccion.configuracion!;
      expect(config.assetUrl, 'https://cdn.test/camiseta-negra-tryon.png');
      expect(config.factorAncho, closeTo(1.45, 1e-9));
      expect(config.factorAlto, closeTo(1.55, 1e-9));
      expect(config.offsetY, closeTo(0.05, 1e-9));
      expect(config.esUsable && config.esTorso, isTrue);
    });
  });

  group('Errores controlados (no se abre la cámara)', () {
    test('producto sin configuraciones activas', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[2],
        _respuesta(5, <Map<String, dynamic>>[]),
      );

      expect(seleccion.esExito, isFalse);
      expect(seleccion.configuracion, isNull);
      expect(seleccion.error, contains('producto 5'));
    });

    test('config requerida ausente: NO se sustituye por otra prenda', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[2],
        _respuesta(5, <Map<String, dynamic>>[
          _configJson(configuracionId: 50, color: 'Azul'),
          _configJson(configuracionId: 58, color: 'Rojo'),
        ]),
      );

      expect(seleccion.esExito, isFalse);
      expect(seleccion.configuracion, isNull);
      expect(seleccion.error, contains('57'));
      expect(seleccion.error, contains('50, 58'));
    });

    test('config sin asset_url', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[1],
        _respuesta(1, <Map<String, dynamic>>[
          _configJson(configuracionId: 55, assetUrl: '   '),
        ]),
      );

      expect(seleccion.esExito, isFalse);
      expect(seleccion.error, contains('asset_url'));
    });

    test('config con tipo_asset distinto de PNG_2D', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[1],
        _respuesta(1, <Map<String, dynamic>>[
          _configJson(configuracionId: 55, tipoAsset: 'GLB_3D'),
        ]),
      );

      expect(seleccion.esExito, isFalse);
      expect(seleccion.error, contains('GLB_3D'));
    });

    test('config de zona distinta de TORSO', () {
      final SeleccionConfigE2E seleccion = _seleccionar(
        PrendaTecnicaE2E.catalogoTecnico[1],
        _respuesta(1, <Map<String, dynamic>>[
          _configJson(configuracionId: 55, zonaCuerpo: 'PIERNAS'),
        ]),
      );

      expect(seleccion.esExito, isFalse);
      expect(seleccion.error, contains('PIERNAS'));
    });
  });
}
