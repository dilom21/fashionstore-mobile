import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/storage/tenant_session.dart';
import '../models/venta_digital_model.dart';

/// Error de la compra digital con un mensaje apto para mostrar al cliente.
class VentaDigitalException implements Exception {
  const VentaDigitalException(
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
  String toString() => 'VentaDigitalException($statusCode): $message';
}

/// Servicio de la compra digital ONLINE del CLIENTE (CU14/CU19 SaaS).
///
/// Endpoint: `POST /tenant/ventas/digital` con `{carrito_id, canal: MOVIL}`.
/// El backend deriva cliente, sucursal, prendas, precios y total del carrito.
///
/// No existe cola offline de ventas: un fallo de red no crea ni confirma una
/// compra. La referencia de un checkout ya creado se conserva aparte para
/// recuperar el pago sin duplicar la venta.
class VentaDigitalService {
  VentaDigitalService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  /// Canal fijo de la app móvil (el backend solo admite WEB/MOVIL).
  static const String canalMovil = 'MOVIL';

  static const String _connectionErrorMessage =
      'No pudimos conectarnos con el servicio. Verifica tu conexión e inténtalo nuevamente.';
  static const String _unexpectedErrorMessage =
      'Ocurrió un problema. Inténtalo nuevamente.';
  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _forbiddenMessage = 'No tienes acceso a este carrito.';
  static const String _notFoundMessage =
      'No encontramos el carrito para completar la compra.';
  static const String _validationMessage =
      'No pudimos preparar tu compra con los datos enviados. Inténtalo nuevamente.';
  static const String _conflictMessage =
      'La compra no pudo completarse. Actualiza tu carrito e inténtalo nuevamente.';
  static const String _conflictStockMessage =
      'El stock cambió y no alcanza para completar la compra. Revisa tu carrito.';
  static const String _conflictVentaMessage =
      'Este carrito ya fue convertido en una venta.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Convierte el carrito ACTIVO en una venta digital PENDIENTE.
  Future<VentaDigital> realizarCompra(int carritoId) async {
    final Object? data = await _enviar(
      'POST',
      ApiConfig.ventasDigitalUrlDesde(_baseUrl),
      body: <String, dynamic>{'carrito_id': carritoId, 'canal': canalMovil},
    );
    if (data is! Map) {
      throw const VentaDigitalException(_unexpectedErrorMessage);
    }
    late final VentaDigital venta;
    try {
      venta = VentaDigital.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const VentaDigitalException(_unexpectedErrorMessage);
    }
    await guardarCheckoutPendiente(venta);
    return venta;
  }

  /// Guarda la referencia segura del checkout para recuperarlo después.
  Future<void> guardarCheckoutPendiente(VentaDigital venta) async {
    try {
      final TenantSession? session = await _storage.readSession();
      if (session == null) return;
      await _storage.savePendingCheckout(
        session.scopeKey,
        PendingCheckout(
          ventaId: venta.ventaId,
          carritoId: venta.carritoId ?? 0,
          total: venta.total,
          empresaSlug: session.empresaSlug,
          sucursalNombre: venta.sucursalNombre,
          estado: venta.estado,
        ),
      );
    } catch (_) {
      // La referencia es una ayuda de recuperación; no bloquea la compra.
    }
  }

  /// Devuelve el checkout pendiente del carrito, si pertenece al scope actual.
  Future<PendingCheckout?> leerCheckoutPendiente(int carritoId) async {
    try {
      final TenantSession? session = await _storage.readSession();
      if (session == null) return null;
      final PendingCheckout? checkout = await _storage.readPendingCheckout(
        session.scopeKey,
      );
      if (checkout == null || checkout.carritoId != carritoId) return null;
      return checkout;
    } catch (_) {
      return null;
    }
  }

  /// Elimina la referencia del checkout (tras pago confirmado o descarte).
  Future<void> limpiarCheckoutPendiente(int ventaId) async {
    try {
      final TenantSession? session = await _storage.readSession();
      if (session == null) return;
      final PendingCheckout? checkout = await _storage.readPendingCheckout(
        session.scopeKey,
      );
      if (checkout?.ventaId == ventaId) {
        await _storage.clearPendingCheckout(session.scopeKey);
      }
    } catch (_) {
      // Sin efecto sobre el flujo principal.
    }
  }

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
      } else {
        response = await _client.get(uri, headers: headers).timeout(_timeout);
      }
    } catch (_) {
      throw const VentaDigitalException(_connectionErrorMessage);
    }

    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204) {
      final String cuerpo = response.body.trim();
      if (cuerpo.isEmpty) {
        throw const VentaDigitalException(_unexpectedErrorMessage);
      }
      try {
        return jsonDecode(cuerpo);
      } catch (_) {
        throw const VentaDigitalException(_unexpectedErrorMessage);
      }
    }

    throw _errorDesde(response);
  }

  VentaDigitalException _errorDesde(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return const VentaDigitalException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const VentaDigitalException(_forbiddenMessage, statusCode: 403);
      case 404:
        return const VentaDigitalException(_notFoundMessage, statusCode: 404);
      case 409:
        return VentaDigitalException(
          _mensajeConflicto(response),
          statusCode: 409,
          conflicto: true,
        );
      case 422:
        return const VentaDigitalException(_validationMessage, statusCode: 422);
      default:
        return VentaDigitalException(
          _unexpectedErrorMessage,
          statusCode: response.statusCode,
        );
    }
  }

  String _mensajeConflicto(http.Response response) {
    final String? detalle = _detalleDeError(response);
    final String texto = (detalle ?? '').toLowerCase();

    if (texto.contains('stock')) return _conflictStockMessage;
    if (texto.contains('convertid')) return _conflictVentaMessage;
    if (texto.contains('activo')) {
      return 'El carrito ya no está activo para comprar.';
    }
    if (texto.contains('prenda') || texto.contains('vac')) {
      return 'El carrito no contiene prendas para comprar.';
    }
    return detalle ?? _conflictMessage;
  }

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

  Future<Map<String, String>> _headers({required bool conCuerpo}) async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw const VentaDigitalException(_unexpectedErrorMessage);
    }
    if (token == null || token.isEmpty) {
      throw const VentaDigitalException(
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

  void _asegurarConfiguracion() {
    if (_baseUrl.isEmpty) {
      throw const VentaDigitalException(ApiConfig.missingBaseUrlHint);
    }
  }
}
