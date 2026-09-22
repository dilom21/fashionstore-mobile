// Pruebas del flujo reutilizable del vestidor virtual (CU26).
//
// No usan red ni cámara: inyectan un VestidorApiService falso y un launcher del
// motor falso. Cubren el ciclo completo (configuraciones -> sesión -> prueba ->
// motor -> cierre), el selector de color, el reenvío de variante, el orden de
// las llamadas y el manejo de errores (unauthorized, fallo al cerrar).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_motor_resultado.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_session_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_api_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_flow_service.dart';

// -----------------------------------------------------------------------------
// Dobles
// -----------------------------------------------------------------------------

/// API del vestidor falsa: registra llamadas y devuelve respuestas configurables.
class _FakeVestidorApi extends VestidorApiService {
  _FakeVestidorApi() : super(baseUrl: 'http://test.local');

  VestidorConfiguracionesResponse? configuraciones;
  Object? errorConfiguraciones;

  VestidorSesion sesion = VestidorSesion.fromJson(<String, dynamic>{
    'sesion_id': 4,
    'cliente_id': 2,
    'estado': 'ACTIVA',
  });
  Object? errorSesion;

  VestidorPrueba prueba = VestidorPrueba.fromJson(<String, dynamic>{
    'prueba_id': 8,
    'sesion_vestidor_ar_id': 4,
    'configuracion_id': 10,
    'variante_producto_id': null,
    'estado': 'INICIADA',
  });
  Object? errorPrueba;
  Object? errorFinalizarPrueba;
  Object? errorFinalizarSesion;

  final List<String> llamadas = <String>[];
  int? ultimaVarianteConfig;
  int? ultimaVariantePrueba;
  int? ultimaConfiguracionId;
  int? ultimaSesionId;
  String? ultimoEstadoPrueba;
  String? ultimoEstadoSesion;

  @override
  Future<VestidorConfiguracionesResponse> obtenerConfiguraciones({
    required int productoId,
    int? varianteId,
    int? colorId,
  }) async {
    llamadas.add('obtenerConfiguraciones');
    ultimaVarianteConfig = varianteId;
    final Object? error = errorConfiguraciones;
    if (error != null) throw error;
    return configuraciones ??
        _respuesta(<Map<String, dynamic>>[_configJson(id: 10)]);
  }

  @override
  Future<VestidorSesion> crearSesion() async {
    llamadas.add('crearSesion');
    final Object? error = errorSesion;
    if (error != null) throw error;
    return sesion;
  }

  @override
  Future<VestidorPrueba> iniciarPrueba({
    required int sesionId,
    required int configuracionId,
    int? varianteProductoId,
  }) async {
    llamadas.add('iniciarPrueba');
    ultimaSesionId = sesionId;
    ultimaConfiguracionId = configuracionId;
    ultimaVariantePrueba = varianteProductoId;
    final Object? error = errorPrueba;
    if (error != null) throw error;
    return prueba;
  }

  @override
  Future<VestidorPrueba> finalizarPrueba({
    required int pruebaId,
    required String estado,
  }) async {
    llamadas.add('finalizarPrueba:$estado');
    ultimoEstadoPrueba = estado;
    final Object? error = errorFinalizarPrueba;
    if (error != null) throw error;
    return prueba;
  }

  @override
  Future<VestidorSesion> finalizarSesion({
    required int sesionId,
    required String estado,
  }) async {
    llamadas.add('finalizarSesion:$estado');
    ultimoEstadoSesion = estado;
    final Object? error = errorFinalizarSesion;
    if (error != null) throw error;
    return sesion;
  }
}

// -----------------------------------------------------------------------------
// Datos y utilidades
// -----------------------------------------------------------------------------

Map<String, dynamic> _configJson({
  required int id,
  int? colorId,
  String? color,
  String zonaCuerpo = 'TORSO',
  String tipoAsset = 'PNG_2D',
  String assetUrl = 'https://cdn.test/prenda.png',
}) => <String, dynamic>{
  'configuracion_id': id,
  'recurso_producto_id': 99,
  'asset_url': assetUrl,
  'color_id': colorId,
  'color': color,
  'zona_cuerpo': zonaCuerpo,
  'tipo_asset': tipoAsset,
  'factor_ancho': '1.45',
  'factor_alto': '1.60',
  'offset_x': '0.00',
  'offset_y': '0.05',
  'rotacion_offset': '0.00',
  'orden_capa': 1,
  'opacidad': '1.00',
};

VestidorConfiguracionesResponse _respuesta(
  List<Map<String, dynamic>> configuraciones,
) => VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
  'producto_id': 1,
  'compatible': configuraciones.isNotEmpty,
  'configuraciones': configuraciones,
});

/// Expone el [BuildContext] real del árbol montado para probar el servicio.
class _Contexto extends StatelessWidget {
  const _Contexto({required this.onContext});

  final void Function(BuildContext) onContext;

  @override
  Widget build(BuildContext context) {
    onContext(context);
    return const SizedBox.shrink();
  }
}

Future<BuildContext> _montar(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _Contexto(onContext: (BuildContext c) => ctx = c)),
    ),
  );
  return ctx;
}

VestidorMotorLauncher _motorQue(
  List<VestidorConfig> recibidas,
  VestidorMotorResultado resultado,
) => (BuildContext context, VestidorConfig configuracion) async {
  recibidas.add(configuracion);
  return resultado;
};

Future<void> _drenarSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'una sola configuración usable no muestra selector y completa la prueba',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..configuraciones = _respuesta(<Map<String, dynamic>>[
          _configJson(id: 10, colorId: 1, color: 'Negro'),
        ]);
      final List<VestidorConfig> recibidas = <VestidorConfig>[];
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(recibidas, VestidorMotorResultado.completada),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );

      expect(resultado, VestidorFlowResultado.completado);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(recibidas.single.configuracionId, 10);
      expect(api.ultimaConfiguracionId, 10);
      expect(api.llamadas, contains('crearSesion'));
      expect(api.llamadas, contains('iniciarPrueba'));
      expect(api.llamadas, contains('finalizarPrueba:COMPLETADA'));
      expect(api.llamadas, contains('finalizarSesion:FINALIZADA'));
    },
  );

  testWidgets(
    'producto incompatible devuelve noDisponible sin abrir el motor ni crear sesión',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..configuraciones = _respuesta(<Map<String, dynamic>>[]);
      final List<VestidorConfig> recibidas = <VestidorConfig>[];
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(recibidas, VestidorMotorResultado.completada),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );
      await tester.pump();

      expect(resultado, VestidorFlowResultado.noDisponible);
      expect(recibidas, isEmpty);
      expect(api.llamadas, isNot(contains('crearSesion')));
      expect(
        find.text(VestidorFlowService.mensajeNoDisponible),
        findsOneWidget,
      );

      await _drenarSnackBar(tester);
    },
  );

  testWidgets(
    'varias configuraciones usables muestran el selector y usar la elegida',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..configuraciones = _respuesta(<Map<String, dynamic>>[
          _configJson(id: 10, colorId: 1, color: 'Negro'),
          _configJson(id: 11, colorId: 2, color: 'Blanco'),
        ]);
      final List<VestidorConfig> recibidas = <VestidorConfig>[];
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(recibidas, VestidorMotorResultado.completada),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final Future<VestidorFlowResultado> futuro = flow.abrirVestidor(
        ctx,
        productoId: 1,
      );
      await tester.pumpAndSettle();

      expect(find.text('Elige el color'), findsOneWidget);
      expect(find.text('Negro'), findsOneWidget);
      expect(find.text('Blanco'), findsOneWidget);

      await tester.tap(find.text('Blanco'));
      await tester.pumpAndSettle();

      final VestidorFlowResultado resultado = await futuro;
      expect(resultado, VestidorFlowResultado.completado);
      expect(recibidas.single.configuracionId, 11);
      expect(api.ultimaConfiguracionId, 11);
    },
  );

  testWidgets(
    'cerrar el selector sin elegir devuelve cancelado sin crear sesión',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..configuraciones = _respuesta(<Map<String, dynamic>>[
          _configJson(id: 10, colorId: 1, color: 'Negro'),
          _configJson(id: 11, colorId: 2, color: 'Blanco'),
        ]);
      final List<VestidorConfig> recibidas = <VestidorConfig>[];
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(recibidas, VestidorMotorResultado.completada),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final Future<VestidorFlowResultado> futuro = flow.abrirVestidor(
        ctx,
        productoId: 1,
      );
      await tester.pumpAndSettle();
      expect(find.text('Elige el color'), findsOneWidget);

      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();

      final VestidorFlowResultado resultado = await futuro;
      expect(resultado, VestidorFlowResultado.cancelado);
      expect(api.llamadas, isNot(contains('crearSesion')));
      expect(recibidas, isEmpty);
    },
  );

  testWidgets('reenvía varianteId al endpoint y a iniciarPrueba', (
    tester,
  ) async {
    final BuildContext ctx = await _montar(tester);
    final _FakeVestidorApi api = _FakeVestidorApi();
    final VestidorFlowService flow = VestidorFlowService(
      api: api,
      motorLauncher: _motorQue(
        <VestidorConfig>[],
        VestidorMotorResultado.completada,
      ),
      sesionExpirada: (BuildContext context, String? mensaje) async {},
    );

    await flow.abrirVestidor(ctx, productoId: 1, varianteId: 11);

    expect(api.ultimaVarianteConfig, 11);
    expect(api.ultimaVariantePrueba, 11);
  });

  testWidgets('la sesión se crea antes de iniciar la prueba', (tester) async {
    final BuildContext ctx = await _montar(tester);
    final _FakeVestidorApi api = _FakeVestidorApi();
    final VestidorFlowService flow = VestidorFlowService(
      api: api,
      motorLauncher: _motorQue(
        <VestidorConfig>[],
        VestidorMotorResultado.completada,
      ),
      sesionExpirada: (BuildContext context, String? mensaje) async {},
    );

    await flow.abrirVestidor(ctx, productoId: 1);

    final int indiceCrear = api.llamadas.indexOf('crearSesion');
    final int indiceIniciar = api.llamadas.indexOf('iniciarPrueba');
    expect(indiceCrear, isNonNegative);
    expect(indiceIniciar, greaterThan(indiceCrear));
  });

  testWidgets(
    'motor completada finaliza la prueba COMPLETADA y la sesión FINALIZADA',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi();
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(
          <VestidorConfig>[],
          VestidorMotorResultado.completada,
        ),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );

      expect(resultado, VestidorFlowResultado.completado);
      expect(api.ultimoEstadoPrueba, VestidorPruebaEstado.completada);
      expect(api.ultimoEstadoSesion, VestidorSesionEstado.finalizada);
    },
  );

  testWidgets(
    'motor cancelada finaliza la prueba CANCELADA y la sesión CANCELADA',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi();
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(
          <VestidorConfig>[],
          VestidorMotorResultado.cancelada,
        ),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );

      expect(resultado, VestidorFlowResultado.cancelado);
      expect(api.llamadas, contains('finalizarPrueba:CANCELADA'));
      expect(api.llamadas, contains('finalizarSesion:CANCELADA'));
    },
  );

  testWidgets(
    'una excepción del motor finaliza la prueba ERROR y la sesión CANCELADA',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi();
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher:
            (BuildContext context, VestidorConfig configuracion) async {
              throw StateError('motor roto');
            },
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );

      expect(resultado, VestidorFlowResultado.error);
      expect(api.llamadas, contains('finalizarPrueba:ERROR'));
      expect(api.llamadas, contains('finalizarSesion:CANCELADA'));
    },
  );

  testWidgets(
    'unauthorized usa el handler de sesión expirada y no crea sesión',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..errorConfiguraciones = const VestidorApiException(
          'Tu sesión expiró. Vuelve a iniciar sesión.',
          statusCode: 401,
          unauthorized: true,
        );
      bool manejado = false;
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(
          <VestidorConfig>[],
          VestidorMotorResultado.completada,
        ),
        sesionExpirada: (BuildContext context, String? mensaje) async {
          manejado = true;
        },
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );

      expect(resultado, VestidorFlowResultado.sesionExpirada);
      expect(manejado, isTrue);
      expect(api.llamadas, isNot(contains('crearSesion')));
      expect(api.llamadas, isNot(contains('iniciarPrueba')));
    },
  );

  testWidgets(
    'si finalizarPrueba falla se compensa cancelando la sesión y se devuelve error',
    (tester) async {
      final BuildContext ctx = await _montar(tester);
      final _FakeVestidorApi api = _FakeVestidorApi()
        ..configuraciones = _respuesta(<Map<String, dynamic>>[
          _configJson(id: 10, color: 'Negro'),
        ])
        ..errorFinalizarPrueba = const VestidorApiException(
          'No se pudo cerrar la prueba.',
        );
      final VestidorFlowService flow = VestidorFlowService(
        api: api,
        motorLauncher: _motorQue(
          <VestidorConfig>[],
          VestidorMotorResultado.completada,
        ),
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      final VestidorFlowResultado resultado = await flow.abrirVestidor(
        ctx,
        productoId: 1,
      );
      await tester.pump();

      expect(resultado, VestidorFlowResultado.error);
      expect(api.llamadas, contains('finalizarSesion:CANCELADA'));
      // El fallo original se muestra; la compensación no lo oculta.
      expect(find.text('No se pudo cerrar la prueba.'), findsOneWidget);

      await _drenarSnackBar(tester);
    },
  );
}
