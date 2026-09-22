// Pruebas de la CTA "PROBAR EN VESTIDOR" en el detalle de producto (CU26).
//
// No usan red ni cámara: inyectan un CatalogoService falso y un
// VestidorFlowService falso o con API/launcher falsos. Verifican que la CTA
// delega en el flujo real, que un producto sin AR NO abre el motor y que el
// botón se deshabilita mientras el flujo está abierto (sin doble apertura).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/models/catalogo_filtros_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/disponibilidad_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/producto_model.dart';
import 'package:fashionstore_mobile/features/catalogo/pages/producto_detalle_page.dart';
import 'package:fashionstore_mobile/features/catalogo/services/catalogo_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_motor_resultado.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_api_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_flow_service.dart';

// -----------------------------------------------------------------------------
// Dobles
// -----------------------------------------------------------------------------

/// Catálogo falso: un producto sin recursos ni variantes.
class _FakeCatalogoService extends CatalogoService {
  @override
  Future<ProductoDetalle> obtenerProducto(int productoId) async =>
      ProductoDetalle.fromJson(<String, dynamic>{
        'id': productoId,
        'nombre': 'Polo de prueba',
        'precio': '99.90',
        'categoria': <String, dynamic>{'id': 1, 'nombre': 'Polos'},
        'recursos': <dynamic>[],
        'variantes': <dynamic>[],
      });

  @override
  Future<DisponibilidadProducto> obtenerDisponibilidad(
    int productoId, {
    int? sucursalId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
  }) async => DisponibilidadProducto.fromJson(<String, dynamic>{
    'producto_id': productoId,
    'producto': 'Polo de prueba',
    'sucursales': <dynamic>[],
  });

  @override
  Future<CatalogoFiltros> obtenerFiltros() async =>
      CatalogoFiltros.fromJson(<String, dynamic>{});
}

/// API del vestidor falsa que responde siempre "sin AR disponible".
class _FakeVestidorApi extends VestidorApiService {
  _FakeVestidorApi() : super(baseUrl: 'http://test.local');

  @override
  Future<VestidorConfiguracionesResponse> obtenerConfiguraciones({
    required int productoId,
    int? varianteId,
    int? colorId,
  }) async => VestidorConfiguracionesResponse.fromJson(<String, dynamic>{
    'producto_id': productoId,
    'compatible': false,
    'configuraciones': <dynamic>[],
  });
}

/// Flujo falso por herencia: registra la llamada y permite controlar el cierre.
class _FakeVestidorFlow extends VestidorFlowService {
  _FakeVestidorFlow({this.completer}) : super(api: _FakeVestidorApi());

  final Completer<VestidorFlowResultado>? completer;

  int llamadas = 0;
  int? ultimoProductoId;
  int? ultimaVarianteId;

  @override
  Future<VestidorFlowResultado> abrirVestidor(
    BuildContext context, {
    required int productoId,
    int? varianteId,
  }) {
    llamadas++;
    ultimoProductoId = productoId;
    ultimaVarianteId = varianteId;
    final Completer<VestidorFlowResultado>? pendiente = completer;
    if (pendiente != null) return pendiente.future;
    return Future<VestidorFlowResultado>.value(
      VestidorFlowResultado.noDisponible,
    );
  }
}

Future<void> _pumpDetalle(
  WidgetTester tester, {
  required VestidorFlowService flow,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: ProductoDetallePage(
        productoId: 4,
        service: _FakeCatalogoService(),
        vestidorFlow: flow,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tocarCta(WidgetTester tester) async {
  await tester.ensureVisible(find.text('PROBAR EN VESTIDOR'));
  await tester.pump();
  await tester.tap(find.text('PROBAR EN VESTIDOR'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'PROBAR EN VESTIDOR sin AR no abre el motor y muestra el mensaje',
    (tester) async {
      int motorLlamadas = 0;
      final VestidorFlowService flow = VestidorFlowService(
        api: _FakeVestidorApi(),
        motorLauncher:
            (BuildContext context, VestidorConfig configuracion) async {
              motorLlamadas++;
              return VestidorMotorResultado.completada;
            },
        sesionExpirada: (BuildContext context, String? mensaje) async {},
      );

      await _pumpDetalle(tester, flow: flow);
      await _tocarCta(tester);

      expect(motorLlamadas, 0);
      expect(
        find.text(VestidorFlowService.mensajeNoDisponible),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'el CTA delega en el flujo con el productoId y evita el doble toque',
    (tester) async {
      final Completer<VestidorFlowResultado> completer =
          Completer<VestidorFlowResultado>();
      final _FakeVestidorFlow flow = _FakeVestidorFlow(completer: completer);

      await _pumpDetalle(tester, flow: flow);
      await _tocarCta(tester);

      expect(flow.llamadas, 1);
      expect(flow.ultimoProductoId, 4);

      final OutlinedButton boton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'PROBAR EN VESTIDOR'),
      );
      expect(boton.onPressed, isNull);

      await tester.tap(find.text('PROBAR EN VESTIDOR'), warnIfMissed: false);
      await tester.pump();
      expect(flow.llamadas, 1);

      completer.complete(VestidorFlowResultado.noDisponible);
      await tester.pumpAndSettle();
    },
  );
}
