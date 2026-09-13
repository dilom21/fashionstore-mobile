// Pruebas de widgets de imágenes del catálogo CU09.
//
// Cubren: uso de la URL recibida en las cards, fallback ante null/error,
// carrusel con 0/1/2/N recursos (PageView + PageController) y la ausencia de
// llamadas de detalle por card (anti N+1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/features/catalogo/models/catalogo_filtros_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/producto_model.dart';
import 'package:fashionstore_mobile/features/catalogo/pages/catalogo_page.dart';
import 'package:fashionstore_mobile/features/catalogo/services/catalogo_service.dart';
import 'package:fashionstore_mobile/features/catalogo/widgets/producto_card.dart';
import 'package:fashionstore_mobile/features/catalogo/widgets/producto_media.dart';

Producto _producto({
  int id = 1,
  String nombre = 'Polo Premium Piqué',
  String? imagen,
}) =>
    Producto(
      id: id,
      nombre: nombre,
      descripcion: 'Prenda de prueba',
      precio: 149.90,
      estado: true,
      categoriaId: 3,
      categoriaNombre: 'Polos',
      imagenPrincipalUrl: imagen,
    );

RecursoProducto _recurso(
  int id,
  String url, {
  bool principal = false,
  String tipo = 'imagen',
}) =>
    RecursoProducto(
      id: id,
      tipo: tipo,
      url: url,
      esPrincipal: principal,
      colorNombre: null,
    );

Widget _envolver(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// Envuelve la galería con un ancho acotado (como en el detalle real, donde
/// vive dentro de un scroll vertical) para que el carrusel 4:5 no desborde el
/// viewport de prueba.
Widget _envolverGaleria(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 340, child: child),
        ),
      ),
    );

void main() {
  group('ProductoCard / ProductImage', () {
    testWidgets('usa la URL recibida en imagen_principal_url', (tester) async {
      await tester.pumpWidget(
        _envolver(
          SizedBox(
            width: 170,
            height: 360,
            child: ProductoCard(
              producto: _producto(
                imagen:
                    'https://cdn.test/storage/products/1/general/model.webp',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Image imagen = tester.widget<Image>(find.byType(Image));
      expect(imagen.image, isA<NetworkImage>());
      expect(
        (imagen.image as NetworkImage).url,
        'https://cdn.test/storage/products/1/general/model.webp',
      );
    });

    testWidgets('con URL null muestra el fallback VANTER MEN', (tester) async {
      await tester.pumpWidget(
        _envolver(
          SizedBox(
            width: 170,
            height: 360,
            child: ProductoCard(producto: _producto(imagen: null)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VanterFallback), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('imagen con error HTTP muestra fallback', (tester) async {
      await tester.pumpWidget(
        _envolver(
          const SizedBox(
            width: 200,
            height: 250,
            child: ProductImage(
              url: 'https://cdn.test/no-existe.webp',
              semanticLabel: 'Polo',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(VanterFallback), findsOneWidget);
    });
  });

  group('ProductoMedia (carrusel)', () {
    testWidgets('0 recursos no falla y no muestra controles', (tester) async {
      await tester.pumpWidget(
        _envolverGaleria(const ProductoMedia(recursos: <RecursoProducto>[])),
      );
      await tester.pump();

      expect(find.byType(PageView), findsNothing);
      expect(find.byType(VanterFallback), findsOneWidget);
    });

    testWidgets('1 recurso no muestra controles innecesarios', (tester) async {
      await tester.pumpWidget(
        _envolverGaleria(
          ProductoMedia(
            nombre: 'Polo',
            recursos: <RecursoProducto>[
              _recurso(1, 'https://cdn.test/model.webp', principal: true),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PageView), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('producto-media-thumb-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('producto-media-punto-0')),
        findsNothing,
      );
    });

    testWidgets('2 recursos permiten cambiar de página con la miniatura',
        (tester) async {
      await tester.pumpWidget(
        _envolverGaleria(
          ProductoMedia(
            nombre: 'Polo',
            recursos: <RecursoProducto>[
              _recurso(1, 'https://cdn.test/model.webp', principal: true),
              _recurso(2, 'https://cdn.test/product.webp'),
            ],
          ),
        ),
      );
      await tester.pump();

      final Semantics thumb0 = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('producto-media-thumb-0')),
      );
      expect(thumb0.properties.selected, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('producto-media-thumb-1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final Semantics thumb1 = tester.widget<Semantics>(
        find.byKey(const ValueKey<String>('producto-media-thumb-1')),
      );
      expect(thumb1.properties.selected, isTrue);
    });

    testWidgets('N recursos y reducción de la lista no producen RangeError',
        (tester) async {
      final List<RecursoProducto> cinco = List<RecursoProducto>.generate(
        5,
        (int i) => _recurso(i + 1, 'https://cdn.test/$i.webp',
            principal: i == 0),
      );

      await tester.pumpWidget(
        _envolverGaleria(ProductoMedia(nombre: 'Polo', recursos: cinco)),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('producto-media-thumb-4')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(
        _envolverGaleria(
          ProductoMedia(nombre: 'Polo', recursos: cinco.sublist(0, 2)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });

  group('CatalogoPage (anti N+1)', () {
    testWidgets('el listado no solicita el detalle por cada card',
        (tester) async {
      final _SpyCatalogoService spy = _SpyCatalogoService(<Producto>[
        _producto(id: 1, nombre: 'Polo', imagen: 'https://cdn.test/1.webp'),
        _producto(id: 2, nombre: 'Traje', imagen: 'https://cdn.test/2.webp'),
      ]);

      await tester.pumpWidget(MaterialApp(home: CatalogoPage(service: spy)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.detalleLlamadas, 0);
      expect(find.byType(ProductoCard), findsNWidgets(2));
    });
  });
}

class _SpyCatalogoService extends CatalogoService {
  _SpyCatalogoService(this._productos);

  final List<Producto> _productos;
  int detalleLlamadas = 0;

  @override
  Future<List<Producto>> listarProductos({
    String? buscar,
    int? categoriaId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
    int? coleccionId,
    int? sucursalId,
    bool? conStock,
  }) async =>
      _productos;

  @override
  Future<CatalogoFiltros> obtenerFiltros() async => const CatalogoFiltros(
        categorias: <OpcionFiltro>[],
        tallas: <OpcionFiltro>[],
        colores: <OpcionFiltro>[],
        temporadas: <OpcionFiltro>[],
        colecciones: <ColeccionFiltro>[],
        sucursales: <SucursalFiltro>[],
      );

  @override
  Future<ProductoDetalle> obtenerProducto(int productoId) async {
    detalleLlamadas++;
    throw StateError('El listado no debe pedir el detalle por card');
  }
}
