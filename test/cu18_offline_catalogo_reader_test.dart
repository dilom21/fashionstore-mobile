import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fashionstore_mobile/core/offline/local_database.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase db;
  setUp(() => db = LocalDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => db.close());

  test('CU18 lee producto, variantes y stock de la misma instantánea', () async {
    await db.saveCu17Snapshot(
      empresaId: 4, usuarioId: 8, sucursalId: null, versionDatos: 'v1',
      startedAt: '2026-11-08T10:00:00Z', completedAt: '2026-11-08T10:00:01Z',
      productos: [{'id': 10, 'nombre': 'Camisa', 'precio': 120, 'categoria_id': 1}],
      variantes: [
        {'id': 20, 'producto_id': 10, 'sku': 'CAM-M-ROJ', 'talla': {'id': 2, 'nombre': 'M'}, 'color': {'id': 3, 'nombre': 'Rojo'}},
        {'id': 21, 'producto_id': 10, 'sku': 'CAM-L-AZU', 'talla': {'id': 4, 'nombre': 'L'}, 'color': {'id': 5, 'nombre': 'Azul'}},
      ],
      stock: [{'sucursal_id': 7, 'variante_id': 20, 'stock_disponible_conocido': 3, 'fecha_actualizacion': '2026-11-08T10:00:00Z'}],
      sucursales: [{'id': 7, 'nombre': 'Centro'}],
    );
    final products = await db.cu18Productos(4, 8, null);
    final variants = await db.cu18Variantes(4, 8, null);
    final stock = await db.cu18Stock(4, 8, null);
    expect(products.single['nombre'], 'Camisa');
    expect(variants, hasLength(2));
    expect(stock.single['variante_id'], 20);
    expect(stock.single['stock_disponible_conocido'], 3);
  });

  test('CU18 no mezcla empresas en la lectura local', () async {
    await db.saveCu17Snapshot(empresaId: 1, usuarioId: 8, sucursalId: null, versionDatos: 'a', startedAt: 'a', completedAt: 'b', productos: [{'id': 1, 'nombre': 'A'}], variantes: [], stock: [], sucursales: []);
    await db.saveCu17Snapshot(empresaId: 2, usuarioId: 8, sucursalId: null, versionDatos: 'b', startedAt: 'a', completedAt: 'b', productos: [{'id': 2, 'nombre': 'B'}], variantes: [], stock: [], sucursales: []);
    expect((await db.cu18Productos(1, 8, null)).single['nombre'], 'A');
    expect((await db.cu18Productos(2, 8, null)).single['nombre'], 'B');
  });
}
