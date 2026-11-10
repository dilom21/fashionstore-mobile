import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fashionstore_mobile/core/offline/local_database.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/core/storage/tenant_session.dart';
import 'package:fashionstore_mobile/features/catalogo/models/catalogo_filtros_model.dart';
import 'package:fashionstore_mobile/features/catalogo/models/producto_model.dart';
import 'package:fashionstore_mobile/features/catalogo/services/catalogo_service.dart';

const String _base = 'http://test.local';

class _SessionStorage extends AuthStorage {
  _SessionStorage(this.session);

  final TenantSession? session;

  @override
  Future<TenantSession?> readSession() async => session;
}

TenantSession _session(String slug, {int empresaId = 1}) => TenantSession(
  empresaId: empresaId,
  usuarioId: 10,
  empresaSlug: slug,
  empresaNombre: slug.toUpperCase(),
);

Map<String, dynamic> _product(int id) => <String, dynamic>{
  'id': id,
  'nombre': 'Producto $id',
  'descripcion': null,
  'precio': '10.00',
  'categoria': <String, dynamic>{'id': 3, 'nombre': 'Polos'},
  'imagen_principal_url': null,
  'promociones_vigentes': <dynamic>[],
  'precio_definitivo': '8.00',
  'precio_calculo_pendiente': false,
};

void main() {
  sqfliteFfiInit();
  late LocalDatabase db;
  setUp(
    () => db = LocalDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    ),
  );
  tearDown(() => db.close());

  test('usa el slug de la sesión y pagina más de 100 productos', () async {
    final List<http.Request> requests = <http.Request>[];
    final http.Client client = MockClient((http.Request request) async {
      requests.add(request);
      final int offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
      final List<Map<String, dynamic>> page = offset == 0
          ? List<Map<String, dynamic>>.generate(100, (i) => _product(i + 1))
          : <Map<String, dynamic>>[_product(101), _product(102)];
      return http.Response(jsonEncode(page), 200);
    });

    final List<Producto> productos = await CatalogoService(
      client: client,
      storage: _SessionStorage(_session('empresa-b', empresaId: 2)),
      database: db,
      baseUrl: _base,
    ).listarProductos(buscar: ' polo ', conStock: true);

    expect(productos, hasLength(102));
    expect(requests, hasLength(2));
    expect(requests.first.url.path, '/catalogo/public/empresa-b/productos');
    expect(requests.first.url.queryParameters['limit'], '100');
    expect(requests.first.url.queryParameters['offset'], '0');
    expect(requests.first.url.queryParameters['buscar'], 'polo');
    expect(requests.first.url.queryParameters['disponibilidad'], 'CON_STOCK');
    expect(requests.last.url.queryParameters['offset'], '100');
    expect(productos.first.precioMostrar, 8.0);
    expect(productos.first.categoriaId, 3);
  });

  test('detalle público parsea variantes y disponibilidad reales', () async {
    final http.Client client = MockClient((http.Request request) async {
      expect(request.url.path, '/catalogo/public/acme/productos/9');
      return http.Response(
        jsonEncode(<String, dynamic>{
          ..._product(9),
          'variantes': <dynamic>[
            <String, dynamic>{
              'id': 11,
              'sku': 'SKU-11',
              'estado': true,
              'talla': <String, dynamic>{'id': 1, 'nombre': 'M'},
              'color': <String, dynamic>{'id': 2, 'nombre': 'Negro'},
            },
          ],
          'recursos': <dynamic>[
            <String, dynamic>{
              'id': 4,
              'tipo': 'imagen',
              'url': 'https://cdn/x.jpg',
              'es_principal': true,
            },
          ],
          'disponibilidad': <dynamic>[
            <String, dynamic>{
              'variante_id': 11,
              'sucursal_id': 2,
              'sucursal': 'Centro',
              'sku': 'SKU-11',
              'talla': 'M',
              'color': 'Negro',
              'temporada': 'Verano',
              'stock_disponible': 4,
            },
          ],
        }),
        200,
      );
    });

    final ProductoDetalle detalle = await CatalogoService(
      client: client,
      storage: _SessionStorage(_session('acme')),
      database: db,
      baseUrl: _base,
    ).obtenerProducto(9);

    expect(detalle.variantes.single.tallaNombre, 'M');
    expect(detalle.variantes.single.colorNombre, 'Negro');
    expect(detalle.disponibilidad.single.varianteId, 11);
    expect(detalle.disponibilidad.single.sucursalId, 2);
    expect(detalle.disponibilidad.single.stockDisponible, 4);
    expect(detalle.recursosUtilizables.single.url, 'https://cdn/x.jpg');
  });

  test('filtros usa el contrato público de la empresa activa', () async {
    final http.Client client = MockClient((http.Request request) async {
      expect(request.url.path, '/catalogo/public/acme/filtros');
      return http.Response(
        jsonEncode(<String, dynamic>{
          'categorias': <dynamic>[
            <String, dynamic>{'id': 3, 'nombre': 'Polos'},
          ],
          'tallas': <dynamic>[],
          'colores': <dynamic>[],
          'temporadas': <dynamic>[
            <String, dynamic>{'id': 4, 'nombre': 'Verano'},
          ],
          'colecciones': <dynamic>[],
          'sucursales': <dynamic>[],
        }),
        200,
      );
    });

    final CatalogoFiltros filtros = await CatalogoService(
      client: client,
      storage: _SessionStorage(_session('acme')),
      database: db,
      baseUrl: _base,
    ).obtenerFiltros();

    expect(filtros.categorias.single.nombre, 'Polos');
    expect(filtros.temporadas.single.id, 4);
  });

  test('no mezcla la caché de dos empresas', () async {
    final http.Client ok = MockClient(
      (http.Request request) async =>
          http.Response(jsonEncode(<Map<String, dynamic>>[_product(1)]), 200),
    );
    final CatalogoService serviceA = CatalogoService(
      client: ok,
      storage: _SessionStorage(_session('empresa-a', empresaId: 1)),
      database: db,
      baseUrl: _base,
    );
    expect(await serviceA.listarProductos(), hasLength(1));

    final http.Client offline = MockClient(
      (http.Request request) async => throw http.ClientException('sin red'),
    );
    final CatalogoService serviceB = CatalogoService(
      client: offline,
      storage: _SessionStorage(_session('empresa-b', empresaId: 2)),
      database: db,
      baseUrl: _base,
    );
    await expectLater(
      serviceB.listarProductos(),
      throwsA(isA<CatalogException>()),
    );
  });

  test('sin sesión tenant no usa un slug fijo', () async {
    final CatalogoService service = CatalogoService(
      client: MockClient(
        (http.Request request) async => http.Response('[]', 200),
      ),
      storage: _SessionStorage(null),
      database: db,
      baseUrl: _base,
    );
    await expectLater(
      service.listarProductos(),
      throwsA(isA<CatalogException>()),
    );
  });
}
