// Pruebas de la pantalla de Asistencia Inteligente.
//
// No usan red: inyectan un AsistenciaService y un CarritoService falsos.
// Cubren loading, error/retry, vacío, cards, chips, navegación al detalle,
// agregar directo (CU15), selección requerida y el CTA de vestidor.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/asistencia_inteligente/models/asistencia_models.dart';
import 'package:fashionstore_mobile/features/asistencia_inteligente/pages/asistencia_inteligente_page.dart';
import 'package:fashionstore_mobile/features/asistencia_inteligente/services/asistencia_service.dart';
import 'package:fashionstore_mobile/features/carrito/models/carrito_model.dart';
import 'package:fashionstore_mobile/features/carrito/services/carrito_service.dart';
import 'package:fashionstore_mobile/features/catalogo/pages/producto_detalle_page.dart';
import 'package:fashionstore_mobile/features/inicio/pages/inicio_page.dart';

// -----------------------------------------------------------------------------
// Dobles
// -----------------------------------------------------------------------------

class _FakeAsistenciaService extends AsistenciaService {
  _FakeAsistenciaService(this._resultados, {this.completer})
    : super(baseUrl: 'http://test.local');

  final List<Object> _resultados;
  Completer<RecomendacionesResponse>? completer;

  int llamadas = 0;
  String? ultimaConsulta;
  String? ultimaTalla;

  @override
  Future<RecomendacionesResponse> recomendar({
    required String consulta,
    String? talla,
    String? color,
    double? presupuestoMax,
    int? sucursalId,
    int limite = 4,
  }) async {
    llamadas++;
    ultimaConsulta = consulta;
    ultimaTalla = talla;

    final Completer<RecomendacionesResponse>? pendiente = completer;
    if (pendiente != null) return pendiente.future;

    final Object resultado = _resultados.isEmpty
        ? _respuesta(const <RecomendacionProducto>[])
        : _resultados.removeAt(0);
    if (resultado is Exception) throw resultado;
    return resultado as RecomendacionesResponse;
  }
}

class _FakeCarritoService extends CarritoService {
  int llamadas = 0;
  int? ultimoInventario;
  int? ultimoSucursal;

  @override
  Future<CarritoDetalle> agregarItem({
    required int sucursalId,
    required int inventarioId,
    required int cantidad,
  }) async {
    llamadas++;
    ultimoInventario = inventarioId;
    ultimoSucursal = sucursalId;
    return CarritoDetalle.vacio(1);
  }
}

class _Observer extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

// -----------------------------------------------------------------------------
// Datos de prueba
// -----------------------------------------------------------------------------

RecomendacionProducto _rec({
  bool requiereSeleccion = false,
  int? inventarioId = 23,
  int? sucursalId = 1,
}) => RecomendacionProducto.fromJson(<String, dynamic>{
  'producto_id': 1,
  'nombre': 'Polo Premium',
  'precio': '149.90',
  'imagen_url': null,
  'categoria': 'Polos',
  'variante_id': requiereSeleccion ? null : 10,
  'talla': requiereSeleccion ? null : 'M',
  'color': requiereSeleccion ? null : 'Negro',
  'inventario_id': requiereSeleccion ? null : inventarioId,
  'sucursal_id': requiereSeleccion ? null : sucursalId,
  'sucursal': requiereSeleccion ? null : 'Centro',
  'temporada': requiereSeleccion ? null : 'Verano',
  'stock_disponible': 5,
  'motivo': 'Ideal para oficina',
  'requiere_seleccion': requiereSeleccion,
});

RecomendacionesResponse _respuesta(
  List<RecomendacionProducto> recomendaciones, {
  String titulo = 'Look casual',
  String descripcion = 'Selección versátil.',
}) => RecomendacionesResponse(
  titulo: titulo,
  descripcion: descripcion,
  recomendaciones: recomendaciones,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      navigatorObservers: observers,
      home: child,
    ),
  );
  await tester.pump();
}

Future<void> _enviar(WidgetTester tester, String texto) async {
  await tester.enterText(find.byType(TextField), texto);
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pump();
}

void main() {
  testWidgets('muestra loading mientras espera la respuesta', (tester) async {
    final Completer<RecomendacionesResponse> completer =
        Completer<RecomendacionesResponse>();
    final _FakeAsistenciaService service = _FakeAsistenciaService(
      const <Object>[],
      completer: completer,
    );

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
    );

    await _enviar(tester, 'look casual');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_respuesta(<RecomendacionProducto>[_rec()]));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Polo Premium'), findsOneWidget);
  });

  testWidgets('muestra error y reintenta', (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      const AsistenciaException('El asistente no está disponible.'),
      _respuesta(<RecomendacionProducto>[_rec()]),
    ]);

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
    );

    await _enviar(tester, 'look casual');
    expect(find.text('El asistente no está disponible.'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Polo Premium'), findsOneWidget);
    expect(service.llamadas, 2);
  });

  testWidgets('muestra el estado vacío', (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(
        const <RecomendacionProducto>[],
        descripcion: 'No encontramos prendas disponibles.',
      ),
    ]);

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
    );

    await _enviar(tester, 'look imposible');
    await tester.pump();

    expect(find.text('No encontramos prendas disponibles.'), findsOneWidget);
  });

  testWidgets('renderiza cards con datos reales y los chips rellenan la consulta',
      (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(<RecomendacionProducto>[_rec()]),
    ]);

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
    );

    await _enviar(tester, 'look formal');
    await tester.pump();

    expect(find.text('Polo Premium'), findsOneWidget);
    expect(find.text('Bs 149.90'), findsOneWidget);
    expect(find.text('Stock: 5'), findsOneWidget);
    expect(find.text('Ideal para oficina'), findsOneWidget);
    expect(find.text('Look casual'), findsOneWidget);

    // Chip de estilo.
    await tester.tap(find.text('Casual'));
    await tester.pump();
    final TextField campo = tester.widget(find.byType(TextField));
    expect(campo.controller!.text, contains('Casual'));

    // Chip de talla: setea el filtro y viaja al backend. Se usa `.first`
    // porque la tarjeta también muestra la etiqueta "Talla M".
    await tester.tap(find.text('Talla M').first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(service.ultimaTalla, 'M');
  });

  testWidgets('Ver detalle abre ProductoDetallePage', (tester) async {
    final _Observer observer = _Observer();
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(<RecomendacionProducto>[_rec()]),
    ]);

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
      observers: <NavigatorObserver>[observer],
    );
    observer.pushed.clear();

    await _enviar(tester, 'look casual');
    await tester.pump();

    await tester.ensureVisible(find.text('Ver detalle'));
    await tester.pump();
    await tester.tap(find.text('Ver detalle'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ProductoDetallePage), findsOneWidget);
    expect(observer.pushed, isNotEmpty);
  });

  testWidgets('Agregar directo usa CarritoService (CU15)', (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(<RecomendacionProducto>[_rec()]),
    ]);
    final _FakeCarritoService carrito = _FakeCarritoService();

    await _pump(
      tester,
      AsistenciaInteligentePage(service: service, carritoService: carrito),
    );

    await _enviar(tester, 'look casual');
    await tester.pump();

    await tester.ensureVisible(find.text('Agregar'));
    await tester.pump();
    await tester.tap(find.text('Agregar'));
    await tester.pump();
    await tester.pump();

    expect(carrito.llamadas, 1);
    expect(carrito.ultimoInventario, 23);
    expect(carrito.ultimoSucursal, 1);
    expect(find.text('Prenda agregada al carrito.'), findsOneWidget);
  });

  testWidgets('selección requerida abre el detalle y no agrega',
      (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(
        <RecomendacionProducto>[_rec(requiereSeleccion: true)],
      ),
    ]);
    final _FakeCarritoService carrito = _FakeCarritoService();

    await _pump(
      tester,
      AsistenciaInteligentePage(service: service, carritoService: carrito),
    );

    await _enviar(tester, 'look casual');
    await tester.pump();

    expect(find.text('Elegir talla'), findsOneWidget);
    await tester.ensureVisible(find.text('Elegir talla'));
    await tester.pump();
    await tester.tap(find.text('Elegir talla'));
    await tester.pump();
    await tester.pump();

    expect(carrito.llamadas, 0);
    expect(find.byType(ProductoDetallePage), findsOneWidget);
  });

  testWidgets('Probar en vestidor muestra el placeholder de AR',
      (tester) async {
    final _FakeAsistenciaService service = _FakeAsistenciaService(<Object>[
      _respuesta(<RecomendacionProducto>[_rec()]),
    ]);

    await _pump(
      tester,
      AsistenciaInteligentePage(
        service: service,
        carritoService: _FakeCarritoService(),
      ),
    );

    await _enviar(tester, 'look casual');
    await tester.pump();

    await tester.ensureVisible(find.text('Probar en vestidor'));
    await tester.pump();
    await tester.tap(find.text('Probar en vestidor'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'El probador con realidad aumentada estará disponible próximamente.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('InicioPage abre AsistenciaInteligentePage desde el CTA',
      (tester) async {
    final _Observer observer = _Observer();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        navigatorObservers: <NavigatorObserver>[observer],
        home: const InicioPage(),
      ),
    );
    await tester.pump();
    observer.pushed.clear();

    await tester.ensureVisible(find.text('Asistencia Inteligente'));
    await tester.tap(find.text('Asistencia Inteligente'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AsistenciaInteligentePage), findsOneWidget);
  });
}
