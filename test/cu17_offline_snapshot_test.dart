import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fashionstore_mobile/core/offline/local_database.dart';

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

  test('CU17 guarda snapshot, sobrevive lectura y separa empresa', () async {
    await db.saveCu17Snapshot(
      empresaId: 1,
      usuarioId: 10,
      sucursalId: 2,
      versionDatos: 'v1',
      startedAt: '2026-11-08T10:00:00Z',
      completedAt: '2026-11-08T10:00:01Z',
      productos: [
        {'id': 7, 'nombre': 'Camisa'},
      ],
      variantes: [
        {'id': 8, 'producto_id': 7},
      ],
      stock: [
        {
          'sucursal_id': 2,
          'variante_id': 8,
          'stock_disponible_conocido': 3,
          'fecha_actualizacion': '2026-11-08T10:00:00Z',
        },
      ],
      sucursales: [
        {'id': 2, 'nombre': 'Centro'},
      ],
    );
    expect((await db.cu17Status(1, 10, 2))?['version_datos'], 'v1');
    expect(await db.cu17Status(2, 10, 2), isNull);
  });

  test(
    'CU17 reemplaza sin duplicar y una falla previa no toca el snapshot',
    () async {
      await db.saveCu17Snapshot(
        empresaId: 1,
        usuarioId: 10,
        sucursalId: 2,
        versionDatos: 'v1',
        startedAt: 'a',
        completedAt: 'b',
        productos: [
          {'id': 7},
        ],
        variantes: [],
        stock: [],
        sucursales: [],
      );
      await db.saveCu17Snapshot(
        empresaId: 1,
        usuarioId: 10,
        sucursalId: 2,
        versionDatos: 'v2',
        startedAt: 'c',
        completedAt: 'd',
        productos: [
          {'id': 7},
        ],
        variantes: [],
        stock: [],
        sucursales: [],
      );
      final status = await db.cu17Status(1, 10, 2);
      expect(status?['version_datos'], 'v2');
      expect(status?['productos_count'], 1);
    },
  );

  test('CU17 conserva más de 100 productos, variantes e inventario', () async {
    final products = List.generate(
      151,
      (i) => {'id': i + 1, 'nombre': 'Producto $i'},
    );
    final variants = List.generate(
      151,
      (i) => {'id': i + 1001, 'producto_id': i + 1},
    );
    final stock = List.generate(
      151,
      (i) => {
        'sucursal_id': 2,
        'variante_id': i + 1001,
        'stock_disponible_conocido': i,
        'fecha_actualizacion': '2026-11-09T10:00:00Z',
      },
    );
    await db.saveCu17Snapshot(
      empresaId: 1,
      usuarioId: 10,
      versionDatos: '151',
      startedAt: 'a',
      completedAt: 'b',
      productos: products,
      variantes: variants,
      stock: stock,
      sucursales: [
        {'id': 2, 'nombre': 'Centro'},
      ],
    );
    expect(await db.cu18Productos(1, 10, null), hasLength(151));
    expect(await db.cu18Variantes(1, 10, null), hasLength(151));
    expect(await db.cu18Stock(1, 10, null), hasLength(151));
  });

  test(
    'CU17 revierte una escritura inválida y conserva el snapshot válido',
    () async {
      await db.saveCu17Snapshot(
        empresaId: 1,
        usuarioId: 10,
        sucursalId: 2,
        versionDatos: 'válido',
        startedAt: 'a',
        completedAt: 'b',
        productos: [
          {'id': 7},
        ],
        variantes: [],
        stock: [],
        sucursales: [],
      );
      await expectLater(
        db.saveCu17Snapshot(
          empresaId: 1,
          usuarioId: 10,
          sucursalId: 2,
          versionDatos: 'inválido',
          startedAt: 'c',
          completedAt: 'd',
          productos: [
            {'id': 8},
          ],
          variantes: [
            {'id': 9},
            {'id': 9},
          ],
          stock: [],
          sucursales: [],
        ),
        throwsA(isA<Exception>()),
      );
      expect((await db.cu17Status(1, 10, 2))?['version_datos'], 'válido');
      expect((await db.cu18Productos(1, 10, 2)).single['id'], 7);
    },
  );
}
