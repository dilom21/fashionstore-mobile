import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../storage/auth_storage.dart';
import '../storage/tenant_session.dart';
import 'local_database.dart';
import 'offline_operation.dart';

class SyncReport {
  const SyncReport({
    required this.confirmed,
    required this.conflicts,
    required this.pending,
  });
  final int confirmed;
  final int conflicts;
  final int pending;
}

class OfflineSyncService {
  OfflineSyncService({
    AuthStorage? storage,
    LocalDatabase? database,
    http.Client? client,
  }) : _storage = storage ?? AuthStorage(),
       _database = database ?? LocalDatabase.instance,
       _client = client ?? http.Client();

  /// La sincronización comercial permanece DESACTIVADA en esta etapa.
  ///
  /// Reservas/ventas offline aún no tienen idempotencia durable ni atomicidad
  /// PostgreSQL certificadas. No se procesan operaciones pendientes
  /// automáticamente; se retomará en CU19-CU22.
  static const bool comercialSyncEnabled = false;

  final AuthStorage _storage;
  final LocalDatabase _database;
  final http.Client _client;

  Future<SyncReport> synchronize() async {
    if (!comercialSyncEnabled) {
      return const SyncReport(confirmed: 0, conflicts: 0, pending: 0);
    }
    final TenantSession? session = await _storage.readSession();
    final String? token = await _storage.readToken();
    if (session == null || token == null || token.isEmpty) {
      return const SyncReport(confirmed: 0, conflicts: 0, pending: 0);
    }
    int confirmed = 0;
    int conflicts = 0;
    int pending = 0;
    for (final OfflineOperation operation in await _database.pending(
      session.scopeKey,
    )) {
      final String? url = operation.type == 'reserva'
          ? ApiConfig.reservasCrearUrl
          : operation.type == 'venta_digital'
          ? ApiConfig.ventasDigitalUrl
          : operation.type == 'venta_contado'
          ? ApiConfig.ventaContadoUrl
          : null;
      if (url == null) {
        await _database.updateOperation(
          operation.operationId,
          OfflineOperationStatus.conflicto,
          error: 'Tipo de operación no soportado.',
        );
        conflicts++;
        continue;
      }
      await _database.updateOperation(
        operation.operationId,
        OfflineOperationStatus.enviado,
        incrementAttempt: true,
      );
      try {
        final http.Response response = await _client
            .post(
              Uri.parse(url),
              headers: <String, String>{
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                'Idempotency-Key': operation.operationId,
              },
              body: jsonEncode(operation.payload),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200 || response.statusCode == 201) {
          await _database.updateOperation(
            operation.operationId,
            OfflineOperationStatus.confirmado,
          );
          confirmed++;
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          await _database.updateOperation(
            operation.operationId,
            OfflineOperationStatus.conflicto,
            error: 'HTTP ${response.statusCode}',
            retryDelaySeconds: 1 << operation.attempts,
          );
          conflicts++;
        } else if (response.statusCode >= 500) {
          await _database.updateOperation(
            operation.operationId,
            operation.attempts >= 7
                ? OfflineOperationStatus.error
                : OfflineOperationStatus.pendiente,
            error: 'HTTP ${response.statusCode}',
          );
          pending++;
        }
      } catch (_) {
        await _database.updateOperation(
          operation.operationId,
          operation.attempts >= 7
              ? OfflineOperationStatus.error
              : OfflineOperationStatus.pendiente,
          error: 'Sin conexión',
          retryDelaySeconds: 1 << operation.attempts,
        );
        pending++;
      }
    }
    return SyncReport(
      confirmed: confirmed,
      conflicts: conflicts,
      pending: pending,
    );
  }
}
