import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';

/// CU17: descarga explícita y atómica de una fotografía de solo lectura.
/// No crea reservas, ventas ni operaciones pendientes.
class OfflineSnapshotService {
  OfflineSnapshotService({
    http.Client? client,
    AuthStorage? storage,
    LocalDatabase? database,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? AuthStorage(),
       _database = database ?? LocalDatabase.instance;
  final http.Client _client;
  final AuthStorage _storage;
  final LocalDatabase _database;

  static const int _pageSize = 100;
  static const int _maxPages = 10000;

  /// Adapta el contrato real de `GET /tenant/inventario` a las filas que
  /// conserva la instantánea. El endpoint devuelve `items` planos; no se debe
  /// asumir el contrato anidado de `GET /tenant/catalogo/productos`.
  static List<Map<String, dynamic>> inventoryRows(Object? decoded) {
    if (decoded is! Map || decoded['items'] is! List) {
      return <Map<String, dynamic>>[];
    }
    return (decoded['items'] as List)
        .whereType<Map>()
        .map((raw) {
          final row = raw.cast<String, dynamic>();
          return <String, dynamic>{
            'sucursal_id': _asInt(row['sucursal_id']),
            'variante_id': _asInt(row['variante_producto_id']),
            'stock_disponible_conocido': _asInt(row['stock_disponible']),
            'fecha_actualizacion': '${row['fecha_actualizacion'] ?? ''}',
          };
        })
        .where(
          (row) =>
              row['sucursal_id'] as int > 0 && row['variante_id'] as int > 0,
        )
        .toList();
  }

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  Future<Map<String, dynamic>?> status() async {
    final TenantSession? session = await _storage.readSession();
    if (session == null) return null;
    return _database.cu17Status(session.empresaId, session.usuarioId, null);
  }

  Future<void> download() async {
    final TenantSession? session = await _storage.readSession();
    final String? token = await _storage.readToken();
    if (session == null || token == null) {
      throw StateError('Sesión empresarial no disponible');
    }
    final headers = {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final List<Map<String, dynamic>> products = await _downloadProducts(
      headers,
    );
    final List<Map<String, dynamic>> variants = [];
    final variantIds = <int>{};
    for (final dynamic product in products) {
      final int id = _requiredId((product as Map)['id'], 'producto');
      final response = await _client.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/tenant/catalogo/productos/$id/variantes',
        ),
        headers: headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Variantes rechazadas (${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Variantes malformadas para producto $id');
      }
      for (final raw in decoded) {
        if (raw is! Map) {
          throw StateError('Variante malformada para producto $id');
        }
        final row = raw.cast<String, dynamic>();
        final variantId = _requiredId(row['id'], 'variante');
        if (!variantIds.add(variantId)) {
          throw StateError('Variante repetida: $variantId');
        }
        if (_asInt(row['producto_id']) != id) {
          throw StateError(
            'Variante $variantId sin relación válida con producto $id',
          );
        }
        variants.add(row);
      }
    }
    final List<Map<String, dynamic>> stock = session.usuarioId > 0
        ? await _downloadInventory(headers)
        : <Map<String, dynamic>>[];
    final String now = DateTime.now().toUtc().toIso8601String();
    final sucursalIds = <int>{};
    final sucursales = stock
        .where((row) => sucursalIds.add(row['sucursal_id'] as int))
        .map(
          (row) => <String, dynamic>{
            'id': row['sucursal_id'],
            'nombre': 'Sucursal ${row['sucursal_id']}',
          },
        )
        .toList();
    await _database.saveCu17Snapshot(
      empresaId: session.empresaId,
      usuarioId: session.usuarioId,
      versionDatos: '$now:${products.length}:${variants.length}',
      startedAt: now,
      completedAt: now,
      productos: products,
      variantes: variants,
      stock: stock,
      sucursales: sucursales,
    );
  }

  Future<List<Map<String, dynamic>>> _downloadProducts(
    Map<String, String> headers,
  ) async {
    final products = <Map<String, dynamic>>[];
    final ids = <int>{};
    for (var page = 0; page < _maxPages; page++) {
      final offset = page * _pageSize;
      final response = await _client.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/tenant/catalogo/productos?limit=$_pageSize&offset=$offset',
        ),
        headers: headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Catálogo rechazado (${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Catálogo malformado en offset $offset');
      }
      if (decoded.any((item) => item is! Map)) {
        throw StateError('Producto malformado en offset $offset');
      }
      final rows = decoded
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
      if (rows.length > _pageSize) {
        throw StateError('Página de catálogo inválida en offset $offset');
      }
      for (final row in rows) {
        final id = _requiredId(row['id'], 'producto');
        if (!ids.add(id)) throw StateError('Producto repetido: $id');
        products.add(row);
      }
      if (rows.length < _pageSize) return products;
    }
    throw StateError('Catálogo excede el límite seguro de páginas');
  }

  Future<List<Map<String, dynamic>>> _downloadInventory(
    Map<String, String> headers,
  ) async {
    final rows = <Map<String, dynamic>>[];
    final keys = <String>{};
    int? total;
    for (var page = 0; page < _maxPages; page++) {
      final offset = page * _pageSize;
      final response = await _client.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/tenant/inventario?limit=$_pageSize&offset=$offset',
        ),
        headers: headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Inventario rechazado (${response.statusCode})');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['items'] is! List ||
          decoded['total'] is! num ||
          decoded['limit'] is! num ||
          decoded['offset'] is! num) {
        throw StateError('Inventario malformado en offset $offset');
      }
      final actualTotal = (decoded['total'] as num).toInt();
      if (total != null && total != actualTotal) {
        throw StateError('Total de inventario inestable');
      }
      total = actualTotal;
      if ((decoded['limit'] as num).toInt() != _pageSize ||
          (decoded['offset'] as num).toInt() != offset ||
          actualTotal < 0) {
        throw StateError('Paginación de inventario inválida');
      }
      final pageRows = inventoryRows(decoded);
      final rawItems = decoded['items'] as List;
      if (pageRows.length != rawItems.length) {
        throw StateError('Inventario contiene IDs inválidos en offset $offset');
      }
      for (final row in pageRows) {
        final key = '${row['sucursal_id']}:${row['variante_id']}';
        if (!keys.add(key)) throw StateError('Inventario repetido: $key');
        rows.add(row);
      }
      if (rows.length > actualTotal) {
        throw StateError('Inventario excede el total declarado');
      }
      if (rows.length == actualTotal) return rows;
      if (pageRows.isEmpty) {
        throw StateError('Página de inventario vacía antes del total');
      }
    }
    throw StateError('Inventario excede el límite seguro de páginas');
  }

  static int _requiredId(Object? value, String entity) {
    final id = _asInt(value);
    if (id <= 0) throw StateError('$entity sin identificador válido');
    return id;
  }
}
