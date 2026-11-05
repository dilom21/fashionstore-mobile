import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'offline_operation.dart';

class LocalDatabase {
  LocalDatabase({DatabaseFactory? factory, String? path})
    // Los parámetros públicos no pueden llamarse `_factory`/`_path`; se
    // conserva la API `factory:`/`path:` usada por las pruebas.
    // ignore: prefer_initializing_formals
    : _factory = factory,
      // ignore: prefer_initializing_formals
      _path = path;

  static final LocalDatabase instance = LocalDatabase();

  /// Fábrica explícita (pruebas o plataformas sin el plugin sqflite).
  ///
  /// Se resuelve de forma diferida en [_open]: construir el servicio no debe
  /// tocar la fábrica global, porque `databaseFactory` lanza si el plugin no
  /// está inicializado y eso rompería cualquier pantalla o prueba que solo
  /// use el camino online.
  final DatabaseFactory? _factory;
  final String? _path;
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final DatabaseFactory factory = _factory ?? databaseFactory;
    final String path =
        _path ?? '${await factory.getDatabasesPath()}/fashionstore_tenant.db';
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE cache_entries (
              scope_key TEXT NOT NULL,
              resource TEXT NOT NULL,
              cache_key TEXT NOT NULL,
              json_value TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (scope_key, resource, cache_key)
            )
          ''');
          await db.execute('''
            CREATE TABLE offline_operations (
              operation_id TEXT PRIMARY KEY,
              scope_key TEXT NOT NULL,
              type TEXT NOT NULL,
              payload TEXT NOT NULL,
              status TEXT NOT NULL CHECK(status IN ('pendiente','enviado','confirmado','conflicto','error')),
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              next_retry_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_offline_scope_status ON offline_operations(scope_key, status, created_at)',
          );
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute("ALTER TABLE offline_operations ADD COLUMN next_retry_at TEXT");
          }
        },
      ),
    );
  }

  Future<void> putCache(
    String scopeKey,
    String resource,
    String cacheKey,
    Object? value,
  ) async {
    final Database db = await database;
    await db.insert('cache_entries', <String, Object?>{
      'scope_key': scopeKey,
      'resource': resource,
      'cache_key': cacheKey,
      'json_value': jsonEncode(value),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Object?> getCache(
    String scopeKey,
    String resource,
    String cacheKey,
  ) async {
    final List<Map<String, Object?>> rows = await (await database).query(
      'cache_entries',
      columns: <String>['json_value'],
      where: 'scope_key = ? AND resource = ? AND cache_key = ?',
      whereArgs: <Object>[scopeKey, resource, cacheKey],
      limit: 1,
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['json_value'] as String);
  }

  Future<void> enqueue(OfflineOperation operation) async {
    final String now = DateTime.now().toUtc().toIso8601String();
    await (await database).insert('offline_operations', <String, Object?>{
      'operation_id': operation.operationId,
      'scope_key': operation.scopeKey,
      'type': operation.type,
      'payload': jsonEncode(operation.payload),
      'status': operation.status.name,
      'attempts': operation.attempts,
      'last_error': operation.lastError,
      'created_at': operation.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<OfflineOperation>> pending(
    String scopeKey, {
    int limit = 20,
  }) async {
    final List<Map<String, Object?>> rows = await (await database).query(
      'offline_operations',
       where: "scope_key = ? AND status IN ('pendiente','enviado') AND attempts < ? AND (next_retry_at IS NULL OR next_retry_at <= ?)",
       whereArgs: <Object>[scopeKey, 8, DateTime.now().toUtc().toIso8601String()],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(OfflineOperation.fromRow).toList();
  }

  Future<void> updateOperation(
    String operationId,
    OfflineOperationStatus status, {
    bool incrementAttempt = false,
    String? error,
    int retryDelaySeconds = 4,
  }) async {
    final DateTime? retryAt = status == OfflineOperationStatus.pendiente
        ? DateTime.now().toUtc().add(Duration(seconds: retryDelaySeconds))
        : null;
    await (await database).rawUpdate(
      '''UPDATE offline_operations
         SET status = ?, attempts = attempts + ?, last_error = ?, next_retry_at = ?, updated_at = ?
         WHERE operation_id = ?''',
      <Object?>[
        status.name,
        incrementAttempt ? 1 : 0,
        error,
        retryAt?.toIso8601String(),
        DateTime.now().toUtc().toIso8601String(),
        operationId,
      ],
    );
  }

  /// Elimina los datos cacheados y las operaciones pendientes de un scope.
  ///
  /// Se usa al cerrar sesión para que la caché y la cola offline de
  /// `empresa:usuario` no sobrevivan en el dispositivo. La operación es
  /// atómica: si falla, no queda una limpieza a medias entre ambas tablas.
  Future<void> clearScope(String scopeKey) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        'cache_entries',
        where: 'scope_key = ?',
        whereArgs: <Object>[scopeKey],
      );
      await txn.delete(
        'offline_operations',
        where: 'scope_key = ?',
        whereArgs: <Object>[scopeKey],
      );
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
