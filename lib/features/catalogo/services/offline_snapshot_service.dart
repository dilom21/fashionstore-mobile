import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';

/// Datos transitorios de una descarga CU17 (antes del COMMIT transaccional).
class _SnapshotData {
  const _SnapshotData({
    required this.productos,
    required this.variantes,
    required this.stock,
    required this.sucursales,
  });

  final List<Map<String, dynamic>> productos;
  final List<Map<String, dynamic>> variantes;
  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> sucursales;
}

/// CU17: descarga explícita y atómica de una fotografía de catálogo.
///
/// Fuente principal (contrato público seguro):
///   GET /catalogo/public/{empresa_slug}/productos?limit=100&offset=N
///   GET /catalogo/public/{empresa_slug}/productos/{id}
///
/// Si el catálogo público está cerrado por configuración del backend
/// (503/403), se usa el catálogo tenant de SOLO LECTURA autorizado para el
/// cliente (`/tenant/catalogo/...`). En ese caso el snapshot conserva
/// productos y variantes, pero NO stock publicado, y la app lo informa.
///
/// Nunca consume `/tenant/inventario` (contexto personal) ni endpoints legacy.
class OfflineSnapshotService {
  OfflineSnapshotService({
    http.Client? client,
    AuthStorage? storage,
    LocalDatabase? database,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? AuthStorage(),
       _database = database ?? LocalDatabase.instance;

  static const int _pageSize = 100;
  static const int _maxPages = 10000;

  final http.Client _client;
  final AuthStorage _storage;
  final LocalDatabase _database;

  /// Adapta el contrato paginado real de inventario (helper histórico).
  ///
  /// Se conserva por compatibilidad con las pruebas CU17 del contrato anterior;
  /// la descarga SaaS ya no consume `/tenant/inventario`.
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
    if (session == null || session.empresaSlug.trim().isEmpty) {
      throw StateError('Sesión empresarial no disponible');
    }
    final String slug = session.empresaSlug.trim().toLowerCase();
    String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      token = null;
    }
    final String startedAt = DateTime.now().toUtc().toIso8601String();

    late final _SnapshotData data;
    try {
      data = await _downloadPublicSnapshot(slug);
    } on StateError catch (error) {
      if (!_contratoPublicoCerrado(error)) rethrow;
      if (token == null || token.isEmpty) rethrow;
      // Fallback autorizado: catálogo tenant de solo lectura, sin stock.
      data = await _downloadTenantSnapshot(token);
    }

    final String completedAt = DateTime.now().toUtc().toIso8601String();
    await _database.saveCu17Snapshot(
      empresaId: session.empresaId,
      usuarioId: session.usuarioId,
      versionDatos:
          '$completedAt:${data.productos.length}:${data.variantes.length}',
      startedAt: startedAt,
      completedAt: completedAt,
      productos: data.productos,
      variantes: data.variantes,
      stock: data.stock,
      sucursales: data.sucursales,
    );
  }

  bool _contratoPublicoCerrado(StateError error) {
    final String message = error.message.toString();
    return message.contains('(503)') ||
        message.contains('(403)') ||
        message.contains('503') ||
        message.contains('403');
  }

  Future<_SnapshotData> _downloadPublicSnapshot(String slug) async {
    final List<Map<String, dynamic>> products = await _downloadPublicProducts(
      slug,
    );
    final List<Map<String, dynamic>> variants = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> stock = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> sucursales = <Map<String, dynamic>>[];
    final Set<int> variantIds = <int>{};
    final Set<String> stockKeys = <String>{};
    final Map<int, String> sucursalNombres = <int, String>{};

    for (final Map<String, dynamic> product in products) {
      final int productId = _requiredId(product['id'], 'producto');
      final Map<String, dynamic> detail = await _downloadPublicDetail(
        slug,
        productId,
      );

      final Object? rawVariants = detail['variantes'];
      if (rawVariants is! List) {
        throw StateError('Detalle sin variantes para producto $productId');
      }
      for (final Object? raw in rawVariants) {
        if (raw is! Map) {
          throw StateError('Variante malformada para producto $productId');
        }
        final Map<String, dynamic> row = raw.cast<String, dynamic>();
        final int variantId = _requiredId(row['id'], 'variante');
        if (!variantIds.add(variantId)) {
          throw StateError('Variante repetida: $variantId');
        }
        variants.add(<String, dynamic>{...row, 'producto_id': productId});
      }

      final Object? rawDisponibilidad = detail['disponibilidad'];
      if (rawDisponibilidad is! List) continue;
      final String updatedAt = '${detail['fecha_actualizacion'] ?? ''}';
      for (final Object? raw in rawDisponibilidad) {
        if (raw is! Map) {
          throw StateError('Disponibilidad malformada para $productId');
        }
        final Map<String, dynamic> row = raw.cast<String, dynamic>();
        final int varianteId = _asInt(row['variante_id']);
        final int sucursalId = _asInt(row['sucursal_id']);
        if (varianteId <= 0 || sucursalId <= 0) continue;
        final String key = '$sucursalId:$varianteId';
        if (!stockKeys.add(key)) continue;
        stock.add(<String, dynamic>{
          'sucursal_id': sucursalId,
          'variante_id': varianteId,
          'stock_disponible_conocido': _asInt(row['stock_disponible']),
          'fecha_actualizacion': updatedAt,
        });
        sucursalNombres.putIfAbsent(
          sucursalId,
          () => '${row['sucursal'] ?? 'Sucursal $sucursalId'}',
        );
      }
    }

    for (final MapEntry<int, String> entry in sucursalNombres.entries) {
      sucursales.add(<String, dynamic>{'id': entry.key, 'nombre': entry.value});
    }

    return _SnapshotData(
      productos: products,
      variantes: variants,
      stock: stock,
      sucursales: sucursales,
    );
  }

  /// Fallback autorizado cuando el catálogo público está cerrado.
  ///
  /// Conserva productos y variantes del catálogo tenant de solo lectura; el
  /// stock queda vacío porque no existe un contrato de disponibilidad
  /// aprobado para el cliente en ese escenario.
  Future<_SnapshotData> _downloadTenantSnapshot(String token) async {
    final List<Map<String, dynamic>> products = <Map<String, dynamic>>[];
    final Set<int> ids = <int>{};
    for (var page = 0; page < _maxPages; page++) {
      final int offset = page * _pageSize;
      final Uri uri =
          Uri.parse('${ApiConfig.baseUrl}/tenant/catalogo/productos').replace(
            queryParameters: <String, String>{
              'limit': '$_pageSize',
              'offset': '$offset',
            },
          );
      final http.Response response = await _get(
        uri,
        'Catálogo tenant',
        token: token,
      );
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Catálogo tenant malformado en offset $offset');
      }
      if (decoded.length > _pageSize) {
        throw StateError('Página tenant inválida en offset $offset');
      }
      for (final Object? item in decoded) {
        if (item is! Map) {
          throw StateError('Producto tenant malformado en offset $offset');
        }
        final Map<String, dynamic> row = item.cast<String, dynamic>();
        final int id = _requiredId(row['id'], 'producto');
        if (!ids.add(id)) throw StateError('Producto repetido: $id');
        products.add(<String, dynamic>{
          ...row,
          'categoria_id': _asInt(row['categoria_id']) != 0
              ? _asInt(row['categoria_id'])
              : (_asInt((row['categoria'] as Map?)?['id'])),
          'categoria_nombre': '${row['categoria_nombre'] ?? ''}',
        });
      }
      if (decoded.length < _pageSize) break;
    }

    final List<Map<String, dynamic>> variants = <Map<String, dynamic>>[];
    final Set<int> variantIds = <int>{};
    for (final Map<String, dynamic> product in products) {
      final int productId = _requiredId(product['id'], 'producto');
      final Uri uri = Uri.parse(
        '${ApiConfig.baseUrl}/tenant/catalogo/productos/$productId/variantes',
      );
      final http.Response response = await _get(
        uri,
        'Variantes tenant',
        token: token,
      );
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Variantes malformadas para producto $productId');
      }
      for (final Object? raw in decoded) {
        if (raw is! Map) {
          throw StateError('Variante malformada para producto $productId');
        }
        final Map<String, dynamic> row = raw.cast<String, dynamic>();
        final int variantId = _requiredId(row['id'], 'variante');
        if (!variantIds.add(variantId)) {
          throw StateError('Variante repetida: $variantId');
        }
        variants.add(<String, dynamic>{...row, 'producto_id': productId});
      }
    }

    return _SnapshotData(
      productos: products,
      variantes: variants,
      stock: <Map<String, dynamic>>[],
      sucursales: <Map<String, dynamic>>[],
    );
  }

  Future<List<Map<String, dynamic>>> _downloadPublicProducts(
    String slug,
  ) async {
    final List<Map<String, dynamic>> products = <Map<String, dynamic>>[];
    final Set<int> ids = <int>{};
    for (var page = 0; page < _maxPages; page++) {
      final int offset = page * _pageSize;
      final Uri uri =
          Uri.parse(
            ApiConfig.catalogoProductosUrlDesde(ApiConfig.baseUrl, slug),
          ).replace(
            queryParameters: <String, String>{
              'limit': '$_pageSize',
              'offset': '$offset',
            },
          );
      final http.Response response = await _get(uri, 'Catálogo');
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw StateError('Catálogo malformado en offset $offset');
      }
      if (decoded.length > _pageSize) {
        throw StateError('Página de catálogo inválida en offset $offset');
      }
      for (final Object? item in decoded) {
        if (item is! Map) {
          throw StateError('Producto malformado en offset $offset');
        }
        final Map<String, dynamic> row = _normalizarProducto(
          item.cast<String, dynamic>(),
        );
        final int id = _requiredId(row['id'], 'producto');
        if (!ids.add(id)) throw StateError('Producto repetido: $id');
        products.add(row);
      }
      if (decoded.length < _pageSize) return products;
    }
    throw StateError('Catálogo excede el límite seguro de páginas');
  }

  Future<Map<String, dynamic>> _downloadPublicDetail(
    String slug,
    int productoId,
  ) async {
    final Uri uri = Uri.parse(
      ApiConfig.catalogoProductoDetalleUrlDesde(
        ApiConfig.baseUrl,
        slug,
        productoId,
      ),
    );
    final http.Response response = await _get(uri, 'Detalle');
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw StateError('Detalle malformado para producto $productoId');
    }
    return decoded.cast<String, dynamic>();
  }

  /// Normaliza el producto público al formato estable que lee CU18.
  static Map<String, dynamic> _normalizarProducto(Map<String, dynamic> raw) {
    final Object? categoria = raw['categoria'];
    final int categoriaId = categoria is Map
        ? _asInt(categoria['id'])
        : _asInt(raw['categoria_id']);
    final String categoriaNombre = categoria is Map
        ? '${categoria['nombre'] ?? ''}'
        : '${raw['categoria_nombre'] ?? ''}';
    return <String, dynamic>{
      ...raw,
      'categoria_id': categoriaId,
      'categoria_nombre': categoriaNombre,
      'estado': raw['estado'] ?? true,
    };
  }

  Future<http.Response> _get(Uri uri, String etiqueta, {String? token}) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw StateError('$etiqueta no disponible sin conexión');
    }
    if (response.statusCode == 403) {
      // No se abre inventario administrativo ni se cambian permisos.
      throw StateError('$etiqueta rechazado (403)');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$etiqueta rechazado (${response.statusCode})');
    }
    return response;
  }

  static int _requiredId(Object? value, String entity) {
    final int id = _asInt(value);
    if (id <= 0) throw StateError('$entity sin identificador válido');
    return id;
  }
}
