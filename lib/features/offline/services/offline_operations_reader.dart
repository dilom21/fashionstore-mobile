import '../../../core/offline/local_database.dart';
import '../../../core/offline/offline_operation.dart';
import '../../../core/storage/auth_storage.dart';

class OfflineOperationsReader {
  OfflineOperationsReader({AuthStorage? storage, LocalDatabase? database})
    : _storage = storage ?? AuthStorage(),
      _database = database ?? LocalDatabase.instance;

  final AuthStorage _storage;
  final LocalDatabase _database;

  Future<List<OfflineOperation>> read({OfflineOperationStatus? status}) async {
    final session = await _storage.readSession();
    if (session == null) return const <OfflineOperation>[];
    return _database.operationsForScope(session.scopeKey, status: status);
  }
}
