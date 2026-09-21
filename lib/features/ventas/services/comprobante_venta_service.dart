import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/comprobante_venta_model.dart';

/// Error del comprobante de venta con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [noDisponible] indica un 409: la venta existe, pero todavía no tiene
/// comprobante (no está COMPLETADA o no tiene pago APROBADO).
class ComprobanteVentaException implements Exception {
  const ComprobanteVentaException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.noDisponible = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool noDisponible;

  @override
  String toString() => 'ComprobanteVentaException($statusCode): $message';
}

/// Servicio de CU23: comprobante de venta del CLIENTE (solo lectura).
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoint consumido (requiere JWT de contexto cliente):
///   GET /ventas/{venta_id}/comprobante
///
/// NO crea otra venta, NO registra otro pago, NO llama a Stripe, NO modifica
/// inventario/carrito/reserva y NO persiste el comprobante.
class ComprobanteVentaService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  ///
  /// [baseUrl] es un punto de inyección para pruebas; en producción se usa
  /// siempre `ApiConfig.baseUrl`.
  ComprobanteVentaService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage =
      'No tienes autorización para consultar este comprobante.';
  static const String _notFoundMessage = 'No encontramos la venta.';
  static const String _noDisponibleMessage =
      'El comprobante aún no está disponible para esta venta.';
  static const String _validationMessage =
      'Los datos de la venta no son válidos.';
  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Obtiene el comprobante de la venta (`GET /ventas/{venta_id}/comprobante`).
  ///
  /// El backend es la autoridad: valida que la venta pertenezca al cliente
  /// autenticado, que esté COMPLETADA y que tenga un pago APROBADO.
  Future<ComprobanteVenta> obtenerComprobante(int ventaId) async {
    if (ventaId <= 0) {
      // Mismo criterio que el backend para un `venta_id` inválido.
      throw const ComprobanteVentaException(_notFoundMessage, statusCode: 404);
    }

    _asegurarConfiguracion();

    final Object? data = await _enviar(
      ApiConfig.comprobanteVentaUrlDesde(_baseUrl, ventaId),
    );
    if (data is! Map) {
      throw const ComprobanteVentaException(_unexpectedErrorMessage);
    }

    try {
      return ComprobanteVenta.desdeJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const ComprobanteVentaException(_unexpectedErrorMessage);
    }
  }

  /// Ejecuta el `GET` y devuelve el cuerpo ya decodificado.
  Future<Object?> _enviar(String url) async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: await _headers())
          .timeout(_timeout);
    } on TimeoutException {
      throw const ComprobanteVentaException(_connectionErrorMessage);
    } on http.ClientException {
      throw const ComprobanteVentaException(_connectionErrorMessage);
    } catch (_) {
      throw const ComprobanteVentaException(_unexpectedErrorMessage);
    }

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body);
      } catch (_) {
        throw const ComprobanteVentaException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  /// Traduce el código de estado a un error con mensaje para el cliente.
  ///
  /// El backend documenta: 404 venta inexistente, 403 venta ajena / fuera de la
  /// sucursal del personal / rol no permitido, 409 venta no COMPLETADA o sin
  /// pago APROBADO.
  ComprobanteVentaException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const ComprobanteVentaException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const ComprobanteVentaException(
          _forbiddenMessage,
          statusCode: 403,
        );
      case 404:
        return const ComprobanteVentaException(
          _notFoundMessage,
          statusCode: 404,
        );
      case 409:
        return const ComprobanteVentaException(
          _noDisponibleMessage,
          statusCode: 409,
          noDisponible: true,
        );
      case 422:
        return const ComprobanteVentaException(
          _validationMessage,
          statusCode: 422,
        );
      default:
        return ComprobanteVentaException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  /// Cabeceras de la petición, con el JWT del cliente.
  Future<Map<String, String>> _headers() async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const ComprobanteVentaException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const ComprobanteVentaException(
        _unauthorizedMessage,
        statusCode: 401,
        unauthorized: true,
      );
    }

    return <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  void _asegurarConfiguracion() {
    if (_baseUrl.isEmpty) {
      throw const ComprobanteVentaException(ApiConfig.missingBaseUrlHint);
    }
  }
}
