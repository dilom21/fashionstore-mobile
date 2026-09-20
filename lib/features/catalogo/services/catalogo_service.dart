import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
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
  CatalogoService({http.Client? client}) : _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el catálogo. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'No pudimos cargar el catálogo. Inténtalo nuevamente.';
  static const String _notFoundMessage = 'El producto solicitado no existe.';

  final http.Client _client;

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

    final Object? data = await _get(ApiConfig.productosUrl, query);
    if (data is! List) throw const CatalogException(_unexpectedErrorMessage);
    return _parseLista(data, Producto.fromJson);
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

    final Object? data = await _get(
      ApiConfig.productoDetalleUrl(productoId),
      const <String, String>{},
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return ProductoDetalle.fromJson(data.cast<String, dynamic>());
  }

  /// Obtiene las opciones de filtros del catálogo.
  Future<CatalogoFiltros> obtenerFiltros() async {
    _asegurarConfiguracion();

    final Object? data = await _get(
      ApiConfig.catalogoFiltrosUrl,
      const <String, String>{},
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

    final Object? data = await _get(
      ApiConfig.productoDisponibilidadUrl(productoId),
      query,
    );
    if (data is! Map) throw const CatalogException(_unexpectedErrorMessage);
    return DisponibilidadProducto.fromJson(data.cast<String, dynamic>());
  }

  /// Ejecuta un GET y decodifica el JSON con manejo de errores centralizado.
  Future<Object?> _get(String url, Map<String, String> query) async {
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
      throw const CatalogException(_connectionErrorMessage);
    } catch (_) {
      throw const CatalogException(_connectionErrorMessage);
    }

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body);
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
