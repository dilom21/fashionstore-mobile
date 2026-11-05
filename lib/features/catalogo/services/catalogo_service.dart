import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';
import '../models/catalogo_filtros_model.dart';
import '../models/disponibilidad_model.dart';
import '../models/producto_model.dart';

/// Error tipado del catálogo con un mensaje apto para mostrar al usuario.
///
/// El catálogo es público: un error aquí NUNCA debe cerrar la sesión.
class CatalogException implements Exception {
  const CatalogException(this.message, {this.statusCode});

  /// Mensaje legible para el cliente.
  final String message;

  /// Código HTTP asociado, si aplica.
  final int? statusCode;

  @override
  String toString() => 'CatalogException($message)';
}

/// Servicio de catálogo público (CU09).
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoints consumidos (todos públicos, sin JWT):
///   GET /productos
///   GET /productos/{id}
///   GET /productos/{id}/disponibilidad
///   GET /catalogo/filtros
class CatalogoService {
  CatalogoService({
    http.Client? client,
    AuthStorage? storage,
    LocalDatabase? database,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? AuthStorage(),
       _database = database ?? LocalDatabase.instance;

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el catálogo. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'No pudimos cargar el catálogo. Inténtalo nuevamente.';
  static const String _notFoundMessage = 'El producto solicitado no existe.';

  final http.Client _client;
  final AuthStorage _storage;
  final LocalDatabase _database;

  /// Lista productos activos con filtros opcionales.
  Future<List<Producto>> listarProductos({
    String? buscar,
    int? categoriaId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
    int? coleccionId,
    int? sucursalId,
    bool? conStock,
  }) async {
    _asegurarConfiguracion();

    final Map<String, String> query = construirQueryProductos(
      buscar: buscar,
      categoriaId: categoriaId,
      tallaId: tallaId,
      colorId: colorId,
      temporadaId: temporadaId,
      coleccionId: coleccionId,
      sucursalId: sucursalId,
      conStock: conStock,
    );

    final Map<String, String> tenantQuery = <String, String>{
      if (categoriaId != null) 'categoria_id': '$categoriaId',
      'limit': '100',
      'offset': '0',
    };
    final Object? data = await _getCached(
      ApiConfig.productosUrl,
      tenantQuery,
      resource: 'catalogo_productos',
      cacheKey: jsonEncode(query),
    );
    if (data is! List) throw const CatalogException(_unexpectedErrorMessage);
    List<Producto> productos = _parseLista(data, Producto.fromJson);
    final String termino = (buscar ?? '').trim().toLowerCase();
    if (termino.isNotEmpty) {
      productos = productos
          .where((Producto p) => p.nombre.toLowerCase().contains(termino))
          .toList();
    }
    return productos;
  }

  /// Construye los parámetros de `GET /productos` a partir de los filtros.
  ///
  /// Es una función pura (sin red) para poder verificarla de forma aislada.
  static Map<String, String> construirQueryProductos({
    String? buscar,
    int? categoriaId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
    int? coleccionId,
    int? sucursalId,
    bool? conStock,
  }) {
    final Map<String, String> query = <String, String>{};
    final String termino = buscar?.trim() ?? '';
    if (termino.isNotEmpty) query['buscar'] = termino;
    if (categoriaId != null) query['categoria_id'] = '$categoriaId';
    if (tallaId != null) query['talla_id'] = '$tallaId';
    if (colorId != null) query['color_id'] = '$colorId';
    if (temporadaId != null) query['temporada_id'] = '$temporadaId';
    if (coleccionId != null) query['coleccion_id'] = '$coleccionId';
    if (sucursalId != null) query['sucursal_id'] = '$sucursalId';
    if (conStock != null) query['con_stock'] = conStock ? 'true' : 'false';
    return query;
  }

  /// Obtiene el detalle de un producto (recursos y variantes incluidos).
  Future<ProductoDetalle> obtenerProducto(int productoId) async {
    _asegurarConfiguracion();

    // Primero valida que el producto pertenezca al tenant. El detalle rico
    // todavía solo existe en el contrato legacy y se usa como fallback online.
    await _getCached(
      ApiConfig.productoDetalleUrl(productoId),
      const <String, String>{},
      resource: 'catalogo_producto_tenant',
      cacheKey: '$productoId',
    );
    final Object? data = await _getCached(
      ApiConfig.productoDetalleLegacyUrl(productoId),
      const <String, String>{},
      resource: 'catalogo_producto_detalle',
      cacheKey: '$productoId',
      authenticated: false,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return ProductoDetalle.fromJson(data.cast<String, dynamic>());
  }

  /// Obtiene las opciones de filtros del catálogo.
  Future<CatalogoFiltros> obtenerFiltros() async {
    _asegurarConfiguracion();

    final Object? data = await _getCached(
      ApiConfig.catalogoFiltrosUrl,
      const <String, String>{},
      resource: 'catalogo_filtros',
      cacheKey: 'all',
      authenticated: false,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return CatalogoFiltros.fromJson(data.cast<String, dynamic>());
  }

  /// Obtiene la disponibilidad de un producto por sucursal.
  Future<DisponibilidadProducto> obtenerDisponibilidad(
    int productoId, {
    int? sucursalId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
  }) async {
    _asegurarConfiguracion();

    final Map<String, String> query = <String, String>{};
    if (sucursalId != null) query['sucursal_id'] = '$sucursalId';
    if (tallaId != null) query['talla_id'] = '$tallaId';
    if (colorId != null) query['color_id'] = '$colorId';
    if (temporadaId != null) query['temporada_id'] = '$temporadaId';

    final Object? data = await _getCached(
      ApiConfig.productoDisponibilidadUrl(productoId),
      query,
      resource: 'catalogo_disponibilidad',
      cacheKey: '$productoId:${jsonEncode(query)}',
      authenticated: false,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return DisponibilidadProducto.fromJson(data.cast<String, dynamic>());
  }

  /// Ejecuta un GET y decodifica el JSON con manejo de errores centralizado.
  Future<Object?> _getCached(
    String url,
    Map<String, String> query, {
    required String resource,
    required String cacheKey,
    bool authenticated = true,
  }) async {
    final TenantSession? session = await _storage.readSession();
    if (session == null) {
      throw const CatalogException('Inicia sesión en una empresa para consultar el catálogo.');
    }
    final Uri uri = Uri.parse(url)
        .replace(queryParameters: query.isEmpty ? null : query);

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              if (authenticated)
                'Authorization': 'Bearer ${await _storage.readToken() ?? ''}',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      final Object? cached = await _database.getCache(
        session.scopeKey, resource, cacheKey,
      );
      if (cached != null) return cached;
      throw const CatalogException(_connectionErrorMessage);
    } catch (_) {
      final Object? cached = await _database.getCache(
        session.scopeKey, resource, cacheKey,
      );
      if (cached != null) return cached;
      throw const CatalogException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      try {
        final Object? decoded = jsonDecode(response.body);
        await _database.putCache(session.scopeKey, resource, cacheKey, decoded);
        return decoded;
      } catch (_) {
        throw const CatalogException(_unexpectedErrorMessage);
      }
    }

    if (response.statusCode == 404) {
      throw const CatalogException(_notFoundMessage, statusCode: 404);
    }

    throw CatalogException(
      _unexpectedErrorMessage,
      statusCode: response.statusCode,
    );
  }

  List<T> _parseLista<T>(
    List<Object?> data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    try {
      return data
          .whereType<Map>()
          .map((Map item) => fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      throw const CatalogException(_unexpectedErrorMessage);
    }
  }

  void _asegurarConfiguracion() {
    if (!ApiConfig.isConfigured) {
      throw const CatalogException(ApiConfig.missingBaseUrlHint);
    }
  }
}
