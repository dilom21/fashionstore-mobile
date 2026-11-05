import 'dart:convert';

enum OfflineOperationStatus { pendiente, enviado, confirmado, conflicto, error }

class OfflineOperation {
  const OfflineOperation({
    required this.operationId,
    required this.scopeKey,
    required this.type,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.lastError,
  });

  factory OfflineOperation.fromRow(Map<String, Object?> row) => OfflineOperation(
    operationId: row['operation_id'] as String,
    scopeKey: row['scope_key'] as String,
    type: row['type'] as String,
    payload: (jsonDecode(row['payload'] as String) as Map).cast<String, dynamic>(),
    status: OfflineOperationStatus.values.byName(row['status'] as String),
    attempts: row['attempts'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
    lastError: row['last_error'] as String?,
  );

  final String operationId;
  final String scopeKey;
  final String type;
  final Map<String, dynamic> payload;
  final OfflineOperationStatus status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;
}
