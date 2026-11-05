import 'package:uuid/uuid.dart';

import '../storage/auth_storage.dart';
import '../storage/tenant_session.dart';
import 'local_database.dart';
import 'offline_operation.dart';

class OfflineQueue {
  OfflineQueue({AuthStorage? storage, LocalDatabase? database, Uuid? uuid})
    : _storage = storage ?? AuthStorage(),
      _database = database ?? LocalDatabase.instance,
      _uuid = uuid ?? const Uuid();

  final AuthStorage _storage;
  final LocalDatabase _database;
  final Uuid _uuid;

  Future<OfflineOperation> add(
    String type,
    Map<String, dynamic> payload, {
    String? operationId,
  }) async {
    final TenantSession? session = await _storage.readSession();
    if (session == null || session.empresaId <= 0 || session.usuarioId <= 0) {
      throw StateError('No hay un contexto tenant activo.');
    }
    final OfflineOperation operation = OfflineOperation(
      operationId: operationId ?? _uuid.v4(),
      scopeKey: session.scopeKey,
      type: type,
      payload: payload,
      status: OfflineOperationStatus.pendiente,
      attempts: 0,
      createdAt: DateTime.now().toUtc(),
    );
    await _database.enqueue(operation);
    return operation;
  }
}
