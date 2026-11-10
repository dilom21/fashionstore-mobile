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
        version: 3,
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
          await _createCu17Tables(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE offline_operations ADD COLUMN next_retry_at TEXT",
            );
          }
          if (oldVersion < 3) await _createCu17Tables(db);
        },
      ),
    );
  }

  Future<void> _createCu17Tables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS offline_snapshot (
      empresa_id INTEGER NOT NULL, usuario_id INTEGER NOT NULL, sucursal_id INTEGER,
      snapshot_key TEXT NOT NULL, schema_version INTEGER NOT NULL, version_datos TEXT NOT NULL,
      generado_en TEXT NOT NULL, download_started_at TEXT NOT NULL, download_completed_at TEXT,
      estado TEXT NOT NULL, productos_count INTEGER NOT NULL, variantes_count INTEGER NOT NULL,
      stock_count INTEGER NOT NULL, PRIMARY KEY (empresa_id, usuario_id, sucursal_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS offline_producto (
      empresa_id INTEGER NOT NULL, usuario_id INTEGER NOT NULL, sucursal_id INTEGER,
      id INTEGER NOT NULL, json_value TEXT NOT NULL, PRIMARY KEY (empresa_id, usuario_id, sucursal_id, id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS offline_variante (
      empresa_id INTEGER NOT NULL, usuario_id INTEGER NOT NULL, sucursal_id INTEGER,
      id INTEGER NOT NULL, json_value TEXT NOT NULL, PRIMARY KEY (empresa_id, usuario_id, sucursal_id, id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS offline_stock_conocido (
      empresa_id INTEGER NOT NULL, usuario_id INTEGER NOT NULL, sucursal_id INTEGER NOT NULL,
      variante_id INTEGER NOT NULL, stock_disponible_conocido INTEGER NOT NULL,
      fecha_actualizacion TEXT NOT NULL, PRIMARY KEY (empresa_id, usuario_id, sucursal_id, variante_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS offline_sucursal (
      empresa_id INTEGER NOT NULL, usuario_id INTEGER NOT NULL, sucursal_id INTEGER NOT NULL,
      nombre TEXT NOT NULL, PRIMARY KEY (empresa_id, usuario_id, sucursal_id)
    )''');
  }

  Future<void> saveCu17Snapshot({
    required int empresaId,
    required int usuarioId,
    int? sucursalId,
    required String versionDatos,
    required String startedAt,
    required String completedAt,
    required List<Map<String, dynamic>> productos,
    required List<Map<String, dynamic>> variantes,
    required List<Map<String, dynamic>> stock,
    required List<Map<String, dynamic>> sucursales,
  }) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      final Object? scopeSucursal = sucursalId;
      for (final String table in [
        'offline_producto',
        'offline_variante',
        'offline_stock_conocido',
        'offline_sucursal',
        'offline_snapshot',
      ]) {
        final bool allBranches =
            sucursalId == null &&
            table != 'offline_snapshot' &&
            table != 'offline_producto' &&
            table != 'offline_variante';
        final String scopeWhere = allBranches
            ? '1 = 1'
            : (sucursalId == null ? 'sucursal_id IS NULL' : 'sucursal_id = ?');
        final List<Object?> scopeArgs = allBranches
            ? [empresaId, usuarioId]
            : (sucursalId == null
                  ? [empresaId, usuarioId]
                  : [empresaId, usuarioId, scopeSucursal]);
        await txn.delete(
          table,
          where: 'empresa_id = ? AND usuario_id = ? AND $scopeWhere',
          whereArgs: scopeArgs,
        );
      }
      final String key = '$empresaId:$usuarioId:${sucursalId ?? 'todas'}';
      await txn.insert('offline_snapshot', {
        'empresa_id': empresaId,
        'usuario_id': usuarioId,
        'sucursal_id': sucursalId,
        'snapshot_key': key,
        'schema_version': 1,
        'version_datos': versionDatos,
        'generado_en': completedAt,
        'download_started_at': startedAt,
        'download_completed_at': completedAt,
        'estado': 'DISPONIBLE_LOCAL',
        'productos_count': productos.length,
        'variantes_count': variantes.length,
        'stock_count': stock.length,
      });
      for (final Map<String, dynamic> row in productos) {
        await txn.insert('offline_producto', {
          'empresa_id': empresaId,
          'usuario_id': usuarioId,
          'sucursal_id': sucursalId,
          'id': row['id'],
          'json_value': jsonEncode(row),
        });
      }
      for (final Map<String, dynamic> row in variantes) {
        await txn.insert('offline_variante', {
          'empresa_id': empresaId,
          'usuario_id': usuarioId,
          'sucursal_id': sucursalId,
          'id': row['id'],
          'json_value': jsonEncode(row),
        });
      }
      for (final Map<String, dynamic> row in stock) {
        await txn.insert('offline_stock_conocido', {
          'empresa_id': empresaId,
          'usuario_id': usuarioId,
          'sucursal_id': row['sucursal_id'],
          'variante_id': row['variante_id'],
          'stock_disponible_conocido': row['stock_disponible_conocido'],
          'fecha_actualizacion': row['fecha_actualizacion'],
        });
      }
      for (final Map<String, dynamic> row in sucursales) {
        await txn.insert('offline_sucursal', {
          'empresa_id': empresaId,
          'usuario_id': usuarioId,
          'sucursal_id': row['id'],
          'nombre': row['nombre'],
        });
      }
    });
  }

  Future<Map<String, dynamic>?> cu17Status(
    int empresaId,
    int usuarioId,
    int? sucursalId,
  ) async {
    final rows = await (await database).query(
      'offline_snapshot',
      where: sucursalId == null
          ? 'empresa_id = ? AND usuario_id = ? AND sucursal_id IS NULL'
          : 'empresa_id = ? AND usuario_id = ? AND sucursal_id = ?',
      whereArgs: sucursalId == null
          ? [empresaId, usuarioId]
          : [empresaId, usuarioId, sucursalId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first.cast<String, dynamic>();
  }

  /// Lecturas CU18 sobre las tablas de la instantánea CU17. No hace red ni
  /// crea tablas/cache paralelo.
  Future<List<Map<String, dynamic>>> cu18Productos(
    int empresaId,
    int usuarioId,
    int? sucursalId,
  ) async {
    final rows = await (await database).query(
      'offline_producto',
      where: sucursalId == null
          ? 'empresa_id = ? AND usuario_id = ? AND sucursal_id IS NULL'
          : 'empresa_id = ? AND usuario_id = ? AND sucursal_id = ?',
      whereArgs: sucursalId == null
          ? [empresaId, usuarioId]
          : [empresaId, usuarioId, sucursalId],
    );
    return rows
        .map(
          (row) =>
              jsonDecode(row['json_value'] as String).cast<String, dynamic>()
                  as Map<String, dynamic>,
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> cu18Variantes(
    int empresaId,
    int usuarioId,
    int? sucursalId,
  ) async {
    final rows = await (await database).query(
      'offline_variante',
      where: sucursalId == null
          ? 'empresa_id = ? AND usuario_id = ? AND sucursal_id IS NULL'
          : 'empresa_id = ? AND usuario_id = ? AND sucursal_id = ?',
      whereArgs: sucursalId == null
          ? [empresaId, usuarioId]
          : [empresaId, usuarioId, sucursalId],
    );
    return rows
        .map(
          (row) =>
              jsonDecode(row['json_value'] as String).cast<String, dynamic>()
                  as Map<String, dynamic>,
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> cu18Stock(
    int empresaId,
    int usuarioId,
    int? sucursalId,
  ) async {
    return (await database).query(
      'offline_stock_conocido',
      where: sucursalId == null
          ? 'empresa_id = ? AND usuario_id = ?'
          : 'empresa_id = ? AND usuario_id = ? AND sucursal_id = ?',
      whereArgs: sucursalId == null
          ? [empresaId, usuarioId]
          : [empresaId, usuarioId, sucursalId],
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
      whereArgs: <Object>[
        scopeKey,
        8,
        DateTime.now().toUtc().toIso8601String(),
      ],
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

  /// Elimina solo la caché de lectura de un scope, preservando las operaciones
  /// offline (que no deben borrarse sin una política explícita).
  Future<void> clearCacheScope(String scopeKey) async {
    await (await database).delete(
      'cache_entries',
      where: 'scope_key = ?',
      whereArgs: <Object>[scopeKey],
    );
  }

  /// Elimina los datos cacheados y las operaciones pendientes de un scope.
  ///
  /// Se mantiene para pruebas y para una futura política explícita de purga;
  /// el cierre de sesión actual NO la usa.
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
