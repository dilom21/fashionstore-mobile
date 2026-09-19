import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/carrito_model.dart';

/// Error del carrito con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [conflicto] indica un 409 del backend (stock, carrito no activo,
/// inventario de otra sucursal, etc.) tras el cual conviene refrescar datos.
class CarritoException implements Exception {
  const CarritoException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.conflicto = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool conflicto;

  @override
  String toString() => 'CarritoException($statusCode): $message';
}

/// Servicio del carrito del CLIENTE (CU15).
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoints consumidos (todos requieren JWT de contexto cliente):
///   POST   /carritos/items
///   GET    /carritos
///   GET    /carritos/{carrito_id}
///   PATCH  /carritos/{carrito_id}/items/{detalle_id}
///   DELETE /carritos/{carrito_id}/items/{detalle_id}
///   DELETE /carritos/{carrito_id}
///
/// El backend obtiene el cliente desde `get_current_cliente`: la app nunca
/// envía `cliente_id`.
class CarritoService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  CarritoService({AuthStorage? storage, http.Client? client})
      : _storage = storage ?? AuthStorage(),
        _client = client ?? http.Client();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage = 'No tienes acceso a este carrito.';
  static const String _notFoundMessage =
      'No encontramos el carrito o la prenda solicitada.';
  static const String _conflictMessage =
      'El carrito cambió o ya no hay stock suficiente. Actualiza e inténtalo nuevamente.';
  static const String _validationMessage =
      'La selección enviada no es válida. Revísala e inténtalo nuevamente.';

  final AuthStorage _storage;
  final http.Client _client;

  /// Agrega una prenda al carrito activo de la sucursal (`POST /carritos/items`).
  ///
  /// El backend deriva producto, variante, talla y color desde `inventarioId`,
  /// por eso solo se envían `sucursal_id`, `inventario_id` y `cantidad`.
  Future<CarritoDetalle> agregarItem({
    required int sucursalId,
    required int inventarioId,
    required int cantidad,
  }) async {
    final Object? data = await _enviar(
      'POST',
      ApiConfig.carritoItemsUrl,
      body: <String, dynamic>{
        'sucursal_id': sucursalId,
        'inventario_id': inventarioId,
        'cantidad': cantidad,
      },
    );
    return _detalleDesde(data);
  }

  /// Lista los carritos activos del cliente (`GET /carritos`).
  ///
  /// Un cliente puede tener varios carritos activos: uno por sucursal.
  Future<CarritoListaResponse> listarCarritos() async {
    final Object? data = await _enviar('GET', ApiConfig.carritosUrl);
    if (data is! Map) throw const CarritoException(_unexpectedErrorMessage);
    try {
      return CarritoListaResponse.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const CarritoException(_unexpectedErrorMessage);
    }
  }

  /// Obtiene el detalle de un carrito (`GET /carritos/{carrito_id}`).
  Future<CarritoDetalle> obtenerCarrito(int carritoId) async {
    final Object? data = await _enviar(
      'GET',
      ApiConfig.carritoDetalleUrl(carritoId),
    );
    return _detalleDesde(data);
  }

  /// Actualiza la cantidad de una línea
  /// (`PATCH /carritos/{carrito_id}/items/{detalle_id}`).
  ///
  /// Debe enviarse `cantidad >= 1`: para quitar la última unidad se usa
  /// [eliminarItem].
  Future<CarritoDetalle> actualizarCantidad({
    required int carritoId,
    required int detalleId,
    required int cantidad,
  }) async {
    final Object? data = await _enviar(
      'PATCH',
      ApiConfig.carritoItemUrl(carritoId, detalleId),
      body: <String, dynamic>{'cantidad': cantidad},
    );
    return _detalleDesde(data);
  }

  /// Elimina una línea (`DELETE /carritos/{carrito_id}/items/{detalle_id}`).
  Future<CarritoDetalle> eliminarItem({
    required int carritoId,
    required int detalleId,
  }) async {
    final Object? data = await _enviar(
      'DELETE',
      ApiConfig.carritoItemUrl(carritoId, detalleId),
    );
    return _detalleDesde(data);
  }

  /// Elimina un carrito completo (`DELETE /carritos/{carrito_id}`).
  ///
  /// El backend puede responder con el detalle del carrito eliminado o con
  /// `204 No Content`; en ese caso se devuelve un detalle vacío y quien llama
  /// recarga el listado con [listarCarritos].
  Future<CarritoDetalle> eliminarCarrito(int carritoId) async {
    final Object? data = await _enviar(
      'DELETE',
      ApiConfig.carritoDetalleUrl(carritoId),
    );
    if (data == null) return CarritoDetalle.vacio(carritoId);
    return _detalleDesde(data);
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  /// Ejecuta la petición autenticada y decodifica el JSON.
  ///
  /// Centraliza el `Authorization: Bearer`, los códigos de estado y los
  /// mensajes de error para que las páginas no manejen HTTP directamente.
  Future<Object?> _enviar(
    String metodo,
    String url, {
    Map<String, dynamic>? body,
  }) async {
    _asegurarConfiguracion();
    final Map<String, String> headers = await _headers(conCuerpo: body != null);
    final Uri uri = Uri.parse(url);

    final http.Response response;
    try {
      if (metodo == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else if (metodo == 'PATCH') {
        response = await _client
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(_timeout);
      } else if (metodo == 'DELETE') {
        response = await _client
            .delete(uri, headers: headers)
            .timeout(_timeout);
      } else {
        response = await _client.get(uri, headers: headers).timeout(_timeout);
      }
    } catch (_) {
      throw const CarritoException(_connectionErrorMessage);
    }

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      final String cuerpo = response.body.trim();
      if (cuerpo.isEmpty) return null;
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const CarritoException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  CarritoException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const CarritoException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const CarritoException(_forbiddenMessage, statusCode: 403);
      case 404:
        return const CarritoException(_notFoundMessage, statusCode: 404);
      case 409:
        return CarritoException(
          _detalleDeError(response) ?? _conflictMessage,
          statusCode: 409,
          conflicto: true,
        );
      case 422:
        return const CarritoException(_validationMessage, statusCode: 422);
      default:
        return CarritoException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  /// Extrae `detail` del backend solo si es un mensaje breve y no técnico.
  String? _detalleDeError(http.Response response) {
    try {
      final Object? data = jsonDecode(response.body);
      if (data is! Map) return null;
      final Object? detalle = data['detail'];
      final String texto = detalle is String ? detalle.trim() : '';
      if (texto.isEmpty || texto.length > 160) return null;
      final String minusculas = texto.toLowerCase();
      const List<String> tecnicos = <String>[
        'traceback',
        'exception',
        'sql',
        'select ',
        'insert ',
        'postgres',
        'error interno',
      ];
      for (final String tecnico in tecnicos) {
        if (minusculas.contains(tecnico)) return null;
      }
      return texto;
    } catch (_) {
      return null;
    }
  }

  /// Cabeceras de la petición, con el JWT del cliente.
  Future<Map<String, String>> _headers({required bool conCuerpo}) async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const CarritoException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const CarritoException(
        _unauthorizedMessage,
        statusCode: 401,
        unauthorized: true,
      );
    }

    return <String, String>{
      'Accept': 'application/json',
      if (conCuerpo) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  CarritoDetalle _detalleDesde(Object? data) {
    if (data is! Map) throw const CarritoException(_unexpectedErrorMessage);
    try {
      return CarritoDetalle.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const CarritoException(_unexpectedErrorMessage);
    }
  }

  void _asegurarConfiguracion() {
    if (!ApiConfig.isConfigured) {
      throw const CarritoException(ApiConfig.missingBaseUrlHint);
    }
  }
}


