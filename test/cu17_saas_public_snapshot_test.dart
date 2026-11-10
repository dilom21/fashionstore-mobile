import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fashionstore_mobile/core/offline/local_database.dart';
import 'package:fashionstore_mobile/core/storage/auth_storage.dart';
import 'package:fashionstore_mobile/core/storage/tenant_session.dart';
import 'package:fashionstore_mobile/features/catalogo/services/offline_snapshot_service.dart';

class _Storage extends AuthStorage {
  @override
  Future<TenantSession?> readSession() async => const TenantSession(
    empresaId: 4,
    usuarioId: 8,
    empresaSlug: 'acme',
    empresaNombre: 'Acme',
  );
}

class _TokenStorage extends _Storage {
  @override
  Future<String?> readToken() async => 'jwt';
}

Map<String, dynamic> _product(int id) => <String, dynamic>{
  'id': id,
  'nombre': 'Producto $id',
  'descripcion': null,
  'precio': '10.00',
  'categoria': <String, dynamic>{'id': 3, 'nombre': 'Polos'},
  'imagen_principal_url': null,
};

Map<String, dynamic> _detail(int id) => <String, dynamic>{
  ..._product(id),
  'variantes': <dynamic>[
    <String, dynamic>{
      'id': id + 1000,
      'sku': 'SKU-$id',
      'estado': true,
      'talla': <String, dynamic>{'id': 1, 'nombre': 'M'},
      'color': <String, dynamic>{'id': 2, 'nombre': 'Negro'},
    },
  ],
  'recursos': <dynamic>[],
  'disponibilidad': <dynamic>[
    <String, dynamic>{
      'variante_id': id + 1000,
      'sucursal_id': 2,
      'sucursal': 'Centro',
      'sku': 'SKU-$id',
      'talla': 'M',
      'color': 'Negro',
      'temporada': 'Verano',
      'stock_disponible': id,
    },
  ],
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

  test(
    'CU17 descarga el catálogo público paginado y su disponibilidad',
    () async {
      final List<http.Request> requests = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.path == '/catalogo/public/acme/productos') {
          final int offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          final List<Map<String, dynamic>> page = offset == 0
              ? List<Map<String, dynamic>>.generate(100, (i) => _product(i + 1))
              : <Map<String, dynamic>>[_product(101)];
          return http.Response(jsonEncode(page), 200);
        }
        if (request.url.path.startsWith('/catalogo/public/acme/productos/')) {
          final int id = int.parse(request.url.pathSegments.last);
          return http.Response(jsonEncode(_detail(id)), 200);
        }
        return http.Response('{}', 404);
      });

      await OfflineSnapshotService(
        client: client,
        storage: _Storage(),
        database: db,
      ).download();

      final Map<String, dynamic>? status = await db.cu17Status(4, 8, null);
      expect(status?['productos_count'], 101);
      expect(status?['variantes_count'], 101);
      expect(status?['stock_count'], 101);
      expect(
        requests.where((http.Request r) => r.url.path.contains('/tenant/')),
        isEmpty,
        reason: 'CU17 no debe consumir inventario/catálogo administrativo',
      );
      expect(
        requests.any(
          (http.Request r) =>
              r.url.path == '/catalogo/public/acme/productos' &&
              r.url.queryParameters['offset'] == '100',
        ),
        isTrue,
      );
      expect(await db.cu18Productos(4, 8, null), hasLength(101));
      expect((await db.cu18Stock(4, 8, null)).first['sucursal_id'], 2);
    },
  );

  test('CU17 no abre inventario si el catálogo público responde 403', () async {
    final List<String> paths = <String>[];
    final http.Client client = MockClient((http.Request request) async {
      paths.add(request.url.path);
      return http.Response('{}', 403);
    });

    await expectLater(
      OfflineSnapshotService(
        client: client,
        storage: _Storage(),
        database: db,
      ).download(),
      throwsA(isA<StateError>()),
    );

    expect(await db.cu17Status(4, 8, null), isNull);
    expect(
      paths.every((String p) => !p.contains('/tenant/inventario')),
      isTrue,
    );
  });

  test(
    'CU17 usa catálogo tenant autorizado si el público está cerrado',
    () async {
      final List<String> paths = <String>[];
      final http.Client client = MockClient((http.Request request) async {
        paths.add(request.url.path);
        if (request.url.path.startsWith('/catalogo/public/')) {
          return http.Response('{}', 503);
        }
        if (request.url.path == '/tenant/catalogo/productos') {
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 1,
                'nombre': 'Producto 1',
                'descripcion': null,
                'precio': '10.00',
                'categoria_id': 3,
                'categoria_nombre': 'Polos',
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/tenant/catalogo/productos/1/variantes') {
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 11,
                'producto_id': 1,
                'sku': 'SKU-1',
                'talla': 'M',
                'color': 'Negro',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      await OfflineSnapshotService(
        client: client,
        storage: _TokenStorage(),
        database: db,
      ).download();

      final Map<String, dynamic>? status = await db.cu17Status(4, 8, null);
      expect(status?['productos_count'], 1);
      expect(status?['variantes_count'], 1);
      // El contrato público cerrado no permite afirmar stock para el cliente.
      expect(status?['stock_count'], 0);
      expect(
        paths.every((String p) => !p.contains('/tenant/inventario')),
        isTrue,
      );
    },
  );
}
