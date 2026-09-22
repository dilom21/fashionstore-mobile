// Pruebas de los modelos de CU26 - Vestidor virtual AR.
//
// Verifican el parsing defensivo del contrato JSON del backend y las rutas
// centralizadas en ApiConfig. No tocan MediaPipe ni cámara.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/core/config/api_config.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_session_model.dart';

void main() {
  group('ApiConfig - rutas CU26', () {
    test('construye todas las rutas del vestidor', () {
      const String base = 'http://api.test';
      expect(
        ApiConfig.vestidorConfiguracionesUrlDesde(base, 7),
        'http://api.test/vestidor-virtual/productos/7/configuraciones',
      );
      expect(
        ApiConfig.vestidorSesionesUrlDesde(base),
        'http://api.test/vestidor-virtual/sesiones',
      );
      expect(
        ApiConfig.vestidorSesionPruebasUrlDesde(base, 3),
        'http://api.test/vestidor-virtual/sesiones/3/pruebas',
      );
      expect(
        ApiConfig.vestidorPruebaFinalizarUrlDesde(base, 9),
        'http://api.test/vestidor-virtual/pruebas/9/finalizar',
      );
      expect(
        ApiConfig.vestidorSesionFinalizarUrlDesde(base, 3),
        'http://api.test/vestidor-virtual/sesiones/3/finalizar',
      );
    });
  });

  group('VestidorConfig', () {
    test('parsea una configuracion con números como string', () {
      final VestidorConfiguracionesResponse respuesta =
          VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
            'producto_id': 1,
            'compatible': true,
            'configuraciones': <dynamic>[
              <String, dynamic>{
                'configuracion_id': 10,
                'recurso_producto_id': 99,
                'asset_url': 'https://cdn.test/polo-negro-tryon.png',
                'color_id': 1,
                'color': 'Negro',
                'zona_cuerpo': 'TORSO',
                'tipo_asset': 'PNG_2D',
                'factor_ancho': '1.45',
                'factor_alto': '1.60',
                'offset_x': '0.00',
                'offset_y': '0.05',
                'rotacion_offset': '0.00',
                'orden_capa': 1,
                'opacidad': '1.00',
              },
            ],
          });

      expect(respuesta.productoId, 1);
      expect(respuesta.compatible, isTrue);
      expect(respuesta.estaVacio, isFalse);
      final VestidorConfig config = respuesta.configuraciones.single;
      expect(config.configuracionId, 10);
      expect(config.productoId, 1);
      expect(config.assetUrl, 'https://cdn.test/polo-negro-tryon.png');
      expect(config.colorId, 1);
      expect(config.color, 'Negro');
      expect(config.zonaCuerpo, 'TORSO');
      expect(config.tipoAsset, 'PNG_2D');
      expect(config.factorAncho, 1.45);
      expect(config.factorAlto, 1.60);
      expect(config.offsetY, 0.05);
      expect(config.ordenCapa, 1);
      expect(config.opacidad, 1.0);
      expect(config.tieneAsset, isTrue);
      expect(config.esPng2d, isTrue);
      expect(config.esTorso, isTrue);
      expect(config.esUsable, isTrue);
      expect(respuesta.primeraUsable?.configuracionId, 10);
    });

    test('color nulo usa etiqueta por defecto', () {
      final VestidorConfig config = VestidorConfig.fromJson(
        <String, dynamic>{
          'configuracion_id': 1,
          'asset_url': 'https://cdn.test/a.png',
          'zona_cuerpo': 'TORSO',
          'tipo_asset': 'PNG_2D',
          'factor_ancho': 1,
          'factor_alto': 1,
          'offset_x': 0,
          'offset_y': 0,
          'rotacion_offset': 0,
          'orden_capa': 1,
          'opacidad': 1,
        },
        productoId: 5,
      );
      expect(config.productoId, 5);
      expect(config.colorId, isNull);
      expect(config.color, isNull);
      expect(config.colorEtiqueta, 'Color único');
    });

    test('producto no compatible devuelve lista vacía', () {
      final VestidorConfiguracionesResponse respuesta =
          VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
            'producto_id': 2,
            'compatible': false,
            'configuraciones': <dynamic>[],
          });
      expect(respuesta.compatible, isFalse);
      expect(respuesta.estaVacio, isTrue);
      expect(respuesta.primeraUsable, isNull);
    });

    test('compatible=true sin items se corrige a false', () {
      final VestidorConfiguracionesResponse respuesta =
          VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
            'producto_id': 2,
            'compatible': true,
            'configuraciones': <dynamic>[],
          });
      expect(respuesta.compatible, isFalse);
    });

    test('config sin asset no es usable', () {
      final VestidorConfig config = VestidorConfig.fromJson(<String, dynamic>{
        'configuracion_id': 3,
        'asset_url': '   ',
        'zona_cuerpo': 'TORSO',
        'tipo_asset': 'PNG_2D',
        'factor_ancho': 1,
        'factor_alto': 1,
        'offset_x': 0,
        'offset_y': 0,
        'rotacion_offset': 0,
        'orden_capa': 1,
        'opacidad': 1,
      });
      expect(config.tieneAsset, isFalse);
      expect(config.esUsable, isFalse);
    });
  });

  group('VestidorSesion / VestidorPrueba', () {
    test('parsea sesion ACTIVA con fecha_fin nula', () {
      final VestidorSesion sesion = VestidorSesion.fromJson(<String, dynamic>{
        'sesion_id': 4,
        'cliente_id': 2,
        'estado': 'ACTIVA',
        'fecha_inicio': '2026-09-21T10:00:00+00:00',
        'fecha_fin': null,
      });
      expect(sesion.sesionId, 4);
      expect(sesion.clienteId, 2);
      expect(sesion.estado, 'ACTIVA');
      expect(sesion.fechaInicio, isNotNull);
      expect(sesion.fechaFin, isNull);
      expect(sesion.estaActiva, isTrue);
      expect(sesion.estaFinalizada, isFalse);
    });

    test('parsea prueba con variante opcional', () {
      final VestidorPrueba prueba = VestidorPrueba.fromJson(<String, dynamic>{
        'prueba_id': 8,
        'sesion_vestidor_ar_id': 4,
        'configuracion_id': 10,
        'variante_producto_id': null,
        'estado': 'INICIADA',
        'fecha_inicio': '2026-09-21T10:00:00+00:00',
        'fecha_fin': null,
      });
      expect(prueba.pruebaId, 8);
      expect(prueba.sesionVestidorArId, 4);
      expect(prueba.configuracionId, 10);
      expect(prueba.varianteProductoId, isNull);
      expect(prueba.estaIniciada, isTrue);
      expect(prueba.estaFinalizada, isFalse);
    });

    test('estados finales declarados', () {
      expect(VestidorSesionEstado.finales, <String>['FINALIZADA', 'CANCELADA']);
      expect(VestidorPruebaEstado.finales, <String>[
        'COMPLETADA',
        'CANCELADA',
        'ERROR',
      ]);
    });
  });
}
