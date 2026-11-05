import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/config/api_config.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/offline/offline_operation.dart';
import '../../../core/offline/offline_queue.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/venta_contado_model.dart';

class VentaContadoException implements Exception {
  const VentaContadoException(this.message, {this.statusCode, this.queuedOffline = false, this.conflicto = false});
  final String message;
  final int? statusCode;
  final bool queuedOffline;
  final bool conflicto;
}

/// Creates tenant cash sales and stores an operation before attempting HTTP.
class VentaContadoService {
  VentaContadoService({AuthStorage? storage, http.Client? client, OfflineQueue? queue, LocalDatabase? database})
      : _storage = storage ?? AuthStorage(),
        _client = client ?? http.Client(),
        _queue = queue ?? OfflineQueue(storage: storage, database: database),
        _database = database ?? LocalDatabase.instance;

  final AuthStorage _storage;
  final http.Client _client;
  final OfflineQueue _queue;
  final LocalDatabase _database;

  Future<VentaContado> registrar({required int sucursalId, required String metodoPago, required List<Map<String, dynamic>> lineas, String? operacionId}) async {
    final String id = operacionId ?? const Uuid().v4();
    final Map<String, dynamic> payload = <String, dynamic>{
      'sucursal_id': sucursalId,
      'operacion_id': id,
      'metodo_pago': metodoPago,
      'lineas': lineas,
    };
    OfflineOperation? operation;
    try {
      operation = await _queue.add('venta_contado', payload, operationId: id);
      await _database.updateOperation(id, OfflineOperationStatus.enviado, incrementAttempt: true);
    } catch (_) {}
    try {
      final String? token = await _storage.readToken();
      if (token == null || token.isEmpty) throw const VentaContadoException('Session expired');
      final http.Response response = await _client.post(Uri.parse(ApiConfig.ventaContadoUrl), headers: <String, String>{
        'Accept': 'application/json', 'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', 'Idempotency-Key': id,
      }, body: jsonEncode(payload)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        final bool conflict = response.statusCode == 409;
        throw VentaContadoException('HTTP ${response.statusCode}', statusCode: response.statusCode, conflicto: conflict);
      }
      final VentaContado result = VentaContado.fromJson((jsonDecode(response.body) as Map).cast<String, dynamic>());
      if (operation != null) await _database.updateOperation(id, OfflineOperationStatus.confirmado);
      return result;
    } on VentaContadoException catch (error) {
      if (operation != null) await _database.updateOperation(id, error.conflicto ? OfflineOperationStatus.conflicto : OfflineOperationStatus.pendiente, error: error.message, retryDelaySeconds: 1 << operation.attempts);
      if (operation != null && error.statusCode == null) throw const VentaContadoException('Sale saved offline and will synchronize when connected.', queuedOffline: true);
      rethrow;
    } catch (_) {
      if (operation != null) await _database.updateOperation(id, OfflineOperationStatus.pendiente, error: 'No connection', retryDelaySeconds: 1 << operation.attempts);
      if (operation != null) throw const VentaContadoException('Sale saved offline and will synchronize when connected.', queuedOffline: true);
      throw const VentaContadoException('Unable to complete sale.');
    }
  }
}
