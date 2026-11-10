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
/// El catálogo público no cierra la sesión: un error aquí NUNCA debe expulsar
/// al cliente autenticado.
class CatalogException implements Exception {
  const CatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'CatalogException($message)';
}

/// Servicio del catálogo público SaaS (CU09).
///
/// La empresa activa sale SIEMPRE de la sesión tenant seleccionada
/// (`TenantSession.empresaSlug`). No existe un slug fijo de compilación.
///
/// Endpoints consumidos (públicos, sin JWT):
///   GET /catalogo/public/{empresa_slug}/productos
///   GET /catalogo/public/{empresa_slug}/productos/{id}
///   GET /catalogo/public/{empresa_slug}/filtros
class CatalogoService {
  CatalogoService({
    http.Client? client,
    AuthStorage? storage,
    LocalDatabase? database,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? AuthStorage(),
       _database = database ?? LocalDatabase.instance,
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  /// Tamaño máximo aceptado por el contrato público (`limit <= 100`).
  static const int pageSize = 100;

  /// Límite defensivo de páginas (100 * 1000 = 100 000 productos).
  static const int maxPages = 1000;

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el catálogo. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'No pudimos cargar el catálogo. Inténtalo nuevamente.';
  static const String _notFoundMessage = 'El producto solicitado no existe.';
  static const String _missingEmpresaMessage =
      'Selecciona una empresa para consultar su catálogo.';

  final http.Client _client;
  final AuthStorage _storage;
  final LocalDatabase _database;
  final String _baseUrl;

  /// Slug de la empresa de la sesión tenant activa.
  Future<String> empresaSlug() async {
    final TenantSession? session = await _storage.readSession();
    final String slug = (session?.empresaSlug ?? '').trim().toLowerCase();
    if (slug.isEmpty) throw const CatalogException(_missingEmpresaMessage);
    return slug;
  }

  /// Lista TODOS los productos activos aplicando paginación real.
  ///
  /// El endpoint devuelve un arreglo plano y limita `limit` a 100, por lo que
  /// se consultan páginas sucesivas hasta recibir una página incompleta.
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
    final String slug = await empresaSlug();

    final Map<String, String> query = construirQueryProductosSaaS(
      buscar: buscar,
      categoriaId: categoriaId,
      tallaId: tallaId,
      colorId: colorId,
      temporadaId: temporadaId,
      coleccionId: coleccionId,
      sucursalId: sucursalId,
      conStock: conStock,
    );

    final TenantSession? session = await _storage.readSession();
    final String scopeKey = session?.scopeKey ?? 'public:$slug';
    final String resource = 'catalogo_productos_saas';
    final String cacheKey = jsonEncode(query);
    final String url = ApiConfig.catalogoProductosUrlDesde(_baseUrl, slug);

    try {
      final List<Object?> acumulado = <Object?>[];
      for (int page = 0; page < maxPages; page++) {
        final Map<String, String> pageQuery = <String, String>{
          ...query,
          'limit': '$pageSize',
          'offset': '${page * pageSize}',
        };
        final Uri uri = Uri.parse(url).replace(queryParameters: pageQuery);
        final http.Response response = await _client
            .get(
              uri,
              headers: const <String, String>{'Accept': 'application/json'},
            )
            .timeout(_timeout);

        if (response.statusCode != 200) {
          throw CatalogException(
            response.statusCode == 404
                ? _notFoundMessage
                : _unexpectedErrorMessage,
            statusCode: response.statusCode,
          );
        }

        final Object? decoded = jsonDecode(response.body);
        if (decoded is! List) {
          throw const CatalogException(_unexpectedErrorMessage);
        }
        acumulado.addAll(decoded);
        if (decoded.length < pageSize) {
          await _database.putCache(scopeKey, resource, cacheKey, acumulado);
          return _parseLista(acumulado, Producto.fromJson);
        }
      }
      throw const CatalogException('El catálogo excede el límite de páginas.');
    } on CatalogException {
      rethrow;
    } catch (_) {
      final Object? cached = await _database.getCache(
        scopeKey,
        resource,
        cacheKey,
      );
      if (cached is List) return _parseLista(cached, Producto.fromJson);
      throw const CatalogException(_connectionErrorMessage);
    }
  }

  /// Construye los parámetros del contrato público SaaS.
  static Map<String, String> construirQueryProductosSaaS({
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
    query['disponibilidad'] = conStock == true ? 'CON_STOCK' : 'TODOS';
    return query;
  }

  /// Compatibilidad con pruebas/helpers del primer parcial.
  ///
  /// La app SaaS usa [construirQueryProductosSaaS]; este método se conserva
  /// únicamente como función pura equivalente del contrato legacy.
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

  /// Obtiene el detalle público con variantes, recursos y disponibilidad.
  Future<ProductoDetalle> obtenerProducto(int productoId) async {
    _asegurarConfiguracion();
    final String slug = await empresaSlug();

    final Object? data = await _getCached(
      ApiConfig.catalogoProductoDetalleUrlDesde(_baseUrl, slug, productoId),
      const <String, String>{},
      resource: 'catalogo_producto_saas',
      cacheKey: '$productoId',
      slug: slug,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return ProductoDetalle.fromJson(data.cast<String, dynamic>());
  }

  /// Obtiene las opciones de filtros del catálogo público de la empresa.
  Future<CatalogoFiltros> obtenerFiltros() async {
    _asegurarConfiguracion();
    final String slug = await empresaSlug();

    final Object? data = await _getCached(
      ApiConfig.catalogoFiltrosUrlDesde(_baseUrl, slug),
      const <String, String>{},
      resource: 'catalogo_filtros_saas',
      cacheKey: 'all',
      slug: slug,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return CatalogoFiltros.fromJson(data.cast<String, dynamic>());
  }

  /// Disponibilidad del producto agrupada por sucursal.
  ///
  /// En SaaS proviene del mismo detalle público (`disponibilidad[]`), nunca de
  /// un endpoint administrativo de inventario.
  Future<DisponibilidadProducto> obtenerDisponibilidad(
    int productoId, {
    int? sucursalId,
    int? tallaId,
    int? colorId,
    int? temporadaId,
  }) async {
    final ProductoDetalle detalle = await obtenerProducto(productoId);

    Set<int>? variantesFiltradas;
    if (tallaId != null || colorId != null) {
      variantesFiltradas = detalle.variantes
          .where(
            (VarianteProducto variante) =>
                (tallaId == null || variante.tallaId == tallaId) &&
                (colorId == null || variante.colorId == colorId),
          )
          .map((VarianteProducto variante) => variante.id)
          .toSet();
    }

    String? temporadaNombre;
    if (temporadaId != null) {
      try {
        final CatalogoFiltros filtros = await obtenerFiltros();
        temporadaNombre = filtros.nombreOpcion(filtros.temporadas, temporadaId);
      } catch (_) {
        temporadaNombre = null;
      }
    }

    final Map<int, List<DisponibilidadVariante>> porSucursal =
        <int, List<DisponibilidadVariante>>{};
    final Map<int, String> sucursalNombre = <int, String>{};
    for (final DisponibilidadVariante fila in detalle.disponibilidad) {
      if (sucursalId != null && fila.sucursalId != sucursalId) continue;
      if (variantesFiltradas != null &&
          !variantesFiltradas.contains(fila.varianteId)) {
        continue;
      }
      if (temporadaNombre != null &&
          temporadaNombre.trim().isNotEmpty &&
          fila.temporada.trim().toLowerCase() !=
              temporadaNombre.trim().toLowerCase()) {
        continue;
      }
      porSucursal
          .putIfAbsent(fila.sucursalId, () => <DisponibilidadVariante>[])
          .add(fila);
      sucursalNombre.putIfAbsent(
        fila.sucursalId,
        () => fila.sucursal.isEmpty
            ? 'Sucursal ${fila.sucursalId}'
            : fila.sucursal,
      );
    }

    return DisponibilidadProducto.fromJson(<String, dynamic>{
      'producto_id': detalle.id,
      'producto': detalle.nombre,
      'sucursales': porSucursal.entries
          .map(
            (MapEntry<int, List<DisponibilidadVariante>> entry) =>
                <String, dynamic>{
                  'sucursal_id': entry.key,
                  'sucursal': sucursalNombre[entry.key],
                  'variantes': entry.value
                      .map(
                        (DisponibilidadVariante fila) => <String, dynamic>{
                          'variante_id': fila.varianteId,
                          'sku': fila.sku,
                          'talla': fila.talla,
                          'color': fila.color,
                          'temporada': fila.temporada,
                          'stock_disponible': fila.stockDisponible,
                        },
                      )
                      .toList(),
                },
          )
          .toList(),
    });
  }

  /// Ejecuta un GET público con caché aislada por empresa.
  Future<Object?> _getCached(
    String url,
    Map<String, String> query, {
    required String resource,
    required String cacheKey,
    required String slug,
  }) async {
    final TenantSession? session = await _storage.readSession();
    final String scopeKey = session?.scopeKey ?? 'public:$slug';
    final Uri uri = Uri.parse(url)
        .replace(queryParameters: query.isEmpty ? null : query);

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      final Object? cached = await _database.getCache(
        scopeKey,
        resource,
        cacheKey,
      );
      if (cached != null) return cached;
      throw const CatalogException(_connectionErrorMessage);
    } catch (_) {
      final Object? cached = await _database.getCache(
        scopeKey,
        resource,
        cacheKey,
      );
      if (cached != null) return cached;
      throw const CatalogException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      try {
        final Object? decoded = jsonDecode(response.body);
        await _database.putCache(scopeKey, resource, cacheKey, decoded);
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
    if (_baseUrl.isEmpty) {
      throw const CatalogException(ApiConfig.missingBaseUrlHint);
    }
  }
}
