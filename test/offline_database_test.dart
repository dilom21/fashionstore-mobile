import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fashionstore_mobile/core/offline/local_database.dart';
import 'package:fashionstore_mobile/core/offline/offline_operation.dart';

void main() {
  sqfliteFfiInit();

  late LocalDatabase database;
  setUp(() {
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => database.close());

  test('cache is isolated by company and user scope', () async {
    await database.putCache('1:10', 'catalog', 'all', <String>['tenant-a']);
    await database.putCache('2:10', 'catalog', 'all', <String>['tenant-b']);

    expect(await database.getCache('1:10', 'catalog', 'all'), <String>[
      'tenant-a',
    ]);
    expect(await database.getCache('2:10', 'catalog', 'all'), <String>[
      'tenant-b',
    ]);
    expect(await database.getCache('1:11', 'catalog', 'all'), isNull);
  });

  test('operation id prevents duplicate queue entries after replay', () async {
    final OfflineOperation operation = OfflineOperation(
      operationId: '1d26e66d-b327-4ed0-9657-f7cba9b58889',
      scopeKey: '1:10',
      type: 'venta_digital',
      payload: const <String, dynamic>{'carrito_id': 7, 'canal': 'MOVIL'},
      status: OfflineOperationStatus.pendiente,
      attempts: 0,
      createdAt: DateTime.utc(2026, 10, 31),
    );
    await database.enqueue(operation);
    await database.enqueue(operation);

    final List<OfflineOperation> pending = await database.pending('1:10');
    expect(pending, hasLength(1));
    expect(pending.single.operationId, operation.operationId);
    expect(await database.pending('2:10'), isEmpty);
  });

  test('clearScope removes cache and queue for one scope only', () async {
    await database.putCache('1:10', 'catalog', 'all', <String>['tenant-a']);
    await database.putCache('2:10', 'catalog', 'all', <String>['tenant-b']);
    for (final (String id, String scope) in <(String, String)>[
      ('op-scope-a', '1:10'),
      ('op-scope-b', '2:10'),
    ]) {
      await database.enqueue(
        OfflineOperation(
          operationId: id,
          scopeKey: scope,
          type: 'venta_digital',
          payload: const <String, dynamic>{'carrito_id': 9},
          status: OfflineOperationStatus.pendiente,
          attempts: 0,
          createdAt: DateTime.utc(2026, 10, 31),
        ),
      );
    }

    await database.clearScope('1:10');

    expect(await database.getCache('1:10', 'catalog', 'all'), isNull);
    expect(await database.pending('1:10'), isEmpty);
    expect(await database.getCache('2:10', 'catalog', 'all'), <String>[
      'tenant-b',
    ]);
    expect(await database.pending('2:10'), hasLength(1));
  });

  test('retry counter is bounded and conflict leaves pending queue', () async {
    const String id = 'a9b0bede-13da-4f99-977d-937accba3bd7';
    await database.enqueue(
      OfflineOperation(
        operationId: id,
        scopeKey: '1:10',
        type: 'venta_digital',
        payload: const <String, dynamic>{'carrito_id': 8},
        status: OfflineOperationStatus.pendiente,
        attempts: 0,
        createdAt: DateTime.utc(2026, 10, 31),
      ),
    );
    for (int i = 0; i < 3; i++) {
      await database.updateOperation(
        id,
        OfflineOperationStatus.pendiente,
        incrementAttempt: true,
      );
    }
    expect(await database.pending('1:10'), isEmpty);

    await database.updateOperation(id, OfflineOperationStatus.conflicto);
    expect(await database.pending('1:10'), isEmpty);
  });

  test('CU21/CU22 reads every status but never crosses tenant scope', () async {
    for (final OfflineOperationStatus status in OfflineOperationStatus.values) {
      await database.enqueue(
        OfflineOperation(
          operationId: 'op-${status.name}',
          scopeKey: '1:10',
          type: 'local_${status.name}',
          payload: const <String, dynamic>{},
          status: status,
          attempts: 1,
          createdAt: DateTime.utc(2026, 11, 1),
        ),
      );
    }
    await database.enqueue(
      OfflineOperation(
        operationId: 'other-tenant',
        scopeKey: '2:10',
        type: 'hidden',
        payload: <String, dynamic>{},
        status: OfflineOperationStatus.conflicto,
        attempts: 1,
        createdAt: DateTime.utc(2026, 11, 1),
      ),
    );

    final rows = await database.operationsForScope('1:10');
    expect(rows, hasLength(OfflineOperationStatus.values.length));
    expect(rows.map((row) => row.type), isNot(contains('hidden')));
    expect(
      await database.operationsForScope(
        '1:10',
        status: OfflineOperationStatus.conflicto,
      ),
      hasLength(1),
    );
  });
}
