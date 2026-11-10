// Pruebas del estado controlado del Vestidor Virtual en el detalle de
// producto. En esta etapa SaaS el acceso está deshabilitado: no se consume el
// contrato legacy ni se abre el motor AR.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/models/catalogo_filtros_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/disponibilidad_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/producto_model.dart';
import 'package:fashionstore_mobile/features/catalogo/pages/producto_detalle_page.dart';
import 'package:fashionstore_mobile/features/catalogo/services/catalogo_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/models/vestidor_config_model.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_api_service.dart';
import 'package:fashionstore_mobile/features/vestidor_virtual/services/vestidor_flow_service.dart';

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

class _FakeVestidorFlow extends VestidorFlowService {
  _FakeVestidorFlow() : super(api: _FakeVestidorApi());

  int llamadas = 0;

  @override
  Future<VestidorFlowResultado> abrirVestidor(
    BuildContext context, {
    required int productoId,
    int? varianteId,
  }) {
    llamadas++;
    return Future<VestidorFlowResultado>.value(
      VestidorFlowResultado.noDisponible,
    );
  }
}

void main() {
  testWidgets('el Vestidor Virtual está deshabilitado y no abre el motor', (
    tester,
  ) async {
    final _FakeVestidorFlow flow = _FakeVestidorFlow();

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

    final Finder boton = find.text('VESTIDOR VIRTUAL · PRÓXIMAMENTE');
    await tester.ensureVisible(boton);
    await tester.pump();

    expect(boton, findsOneWidget);
    final OutlinedButton widget = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'VESTIDOR VIRTUAL · PRÓXIMAMENTE'),
    );
    expect(widget.onPressed, isNull);
    expect(flow.llamadas, 0);

    // Ningún toque abre el flujo ni crea una sesión AR.
    await tester.tap(boton, warnIfMissed: false);
    await tester.pump();
    expect(flow.llamadas, 0);
  });
}
