import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/auth_storage.dart';
import '../models/historial_compras_model.dart';

/// Error del historial de compras con un mensaje apto para mostrar al cliente.
///
/// [unauthorized] indica que el JWT fue rechazado (hay que cerrar la sesión
/// local). [filtrosInvalidos] marca un 422 (filtros/parámetros rechazados) y
/// [aunNoHistorica] un 409: la venta existe y es del cliente, pero todavía no
/// forma parte del historial (PENDIENTE/PAGADA).
class HistorialComprasException implements Exception {
  const HistorialComprasException(
    this.message, {
    this.statusCode,
    this.unauthorized = false,
    this.filtrosInvalidos = false,
    this.aunNoHistorica = false,
  });

  final String message;
  final int? statusCode;
  final bool unauthorized;
  final bool filtrosInvalidos;
  final bool aunNoHistorica;

  @override
  String toString() => 'HistorialComprasException($statusCode): $message';
}

/// Servicio de CU24: historial de compras del CLIENTE autenticado.
///
/// Flujo: Page -> Service -> Backend FastAPI.
/// Endpoints consumidos (requieren JWT de contexto cliente):
///   GET /ventas/historial
///   GET /ventas/historial/{venta_id}
///
/// El backend identifica al cliente por el JWT: NUNCA se envía `cliente_id`.
/// Es solo lectura: no modifica ventas, pagos, inventario ni carrito, y no
/// genera comprobantes (eso es CU23).
class HistorialComprasService {
  /// Crea el servicio, permitiendo inyectar almacenamiento y cliente HTTP.
  ///
  /// [baseUrl] es un punto de inyección para pruebas; en producción se usa
  /// siempre `ApiConfig.baseUrl`.
  HistorialComprasService({
    AuthStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? AuthStorage(),
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).trim();

  static const Duration _timeout = Duration(seconds: 15);

  /// Página inicial del backend.
  static const int paginaPorDefecto = 1;

  /// Tamaño de página por defecto del backend (20).
  static const int tamanoPaginaPorDefecto = 20;

  /// Tamaño máximo aceptado por el backend (`tamano_pagina <= 50`).
  static const int tamanoPaginaMaximo = 50;

  static const String _unauthorizedMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
  static const String _listadoForbiddenMessage =
      'No tienes autorización para consultar este historial.';
  static const String _listadoFiltrosMessage =
      'Revisa los filtros e inténtalo nuevamente.';
  static const String _listadoRedMessage =
      'No pudimos cargar tu historial. Verifica tu conexión e inténtalo nuevamente.';
  static const String _listadoServidorMessage =
      'No pudimos cargar tu historial. Inténtalo nuevamente.';
  static const String _detalleForbiddenMessage =
      'No tienes autorización para consultar esta compra.';
  static const String _detalleNoEncontradaMessage =
      'No encontramos esta compra.';
  static const String _detalleNoHistoricaMessage =
      'Esta venta aún no forma parte de tu historial.';
  static const String _detalleMessage =
      'No pudimos cargar el detalle. Inténtalo nuevamente.';

  final AuthStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  /// Obtiene el historial paginado del cliente (`GET /ventas/historial`).
  ///
  /// Los filtros son opcionales y solo se envían cuando tienen valor. El orden
  /// de los resultados y la propiedad de las ventas los decide el backend.
  Future<HistorialComprasResponse> obtenerHistorial({
    EstadoHistorial? estado,
    CanalHistorial? canal,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int pagina = paginaPorDefecto,
    int tamanoPagina = tamanoPaginaPorDefecto,
  }) async {
    _asegurarConfiguracion();

    final int paginaSegura = pagina < paginaPorDefecto
        ? paginaPorDefecto
        : pagina;
    final int tamanoSeguro = tamanoPagina < 1
        ? tamanoPaginaPorDefecto
        : (tamanoPagina > tamanoPaginaMaximo
              ? tamanoPaginaMaximo
              : tamanoPagina);

    final Map<String, String> query = <String, String>{
      'pagina': '$paginaSegura',
      'tamano_pagina': '$tamanoSeguro',
      if (estado != null) 'estado': estado.codigo,
      if (canal != null) 'canal': canal.codigo,
      if (fechaDesde != null) 'fecha_desde': _fechaQuery(fechaDesde),
      if (fechaHasta != null) 'fecha_hasta': _fechaQuery(fechaHasta),
    };

    final Uri uri = Uri.parse(
      ApiConfig.historialComprasUrlDesde(_baseUrl),
    ).replace(queryParameters: query);

    final Object? data = await _enviar(uri, detalle: false);
    if (data is! Map) {
      throw const HistorialComprasException(_listadoServidorMessage);
    }

    try {
      return HistorialComprasResponse.desdeJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const HistorialComprasException(_listadoServidorMessage);
    }
  }

  /// Obtiene el detalle de una compra del cliente
  /// (`GET /ventas/historial/{venta_id}`).
  ///
  /// El backend vuelve a validar la propiedad de la venta, por eso la pantalla
  /// de detalle consulta de nuevo en lugar de confiar en el listado.
  Future<HistorialCompraDetalle> obtenerDetalle(int ventaId) async {
    if (ventaId <= 0) {
      // Mismo criterio que el backend para un `venta_id` inválido.
      throw const HistorialComprasException(
        _detalleNoEncontradaMessage,
        statusCode: 404,
      );
    }

    _asegurarConfiguracion();

    final Object? data = await _enviar(
      Uri.parse(ApiConfig.historialCompraDetalleUrlDesde(_baseUrl, ventaId)),
      detalle: true,
    );
    if (data is! Map) {
      throw const HistorialComprasException(_detalleMessage);
    }

    try {
      return HistorialCompraDetalle.desdeJson(data.cast<String, dynamic>());
    } catch (_) {
      throw const HistorialComprasException(_detalleMessage);
    }
  }

  /// Ejecuta el `GET` y devuelve el cuerpo ya decodificado.
  Future<Object?> _enviar(Uri uri, {required bool detalle}) async {
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: await _headers(detalle: detalle))
          .timeout(_timeout);
    } on TimeoutException {
      throw HistorialComprasException(
        detalle ? _detalleMessage : _listadoRedMessage,
      );
    } on http.ClientException {
      throw HistorialComprasException(
        detalle ? _detalleMessage : _listadoRedMessage,
      );
    } on HistorialComprasException {
      // Sin JWT (401 local): no se enmascara como error inesperado.
      rethrow;
    } catch (_) {
      throw HistorialComprasException(
        detalle ? _detalleMessage : _listadoServidorMessage,
      );
    }

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body);
      } catch (_) {
        throw HistorialComprasException(
          detalle ? _detalleMessage : _listadoServidorMessage,
        );
      }
    }

    return throw (detalle
        ? _errorDetalle(response.statusCode)
        : _errorListado(response.statusCode));
  }

  /// Traduce el estado HTTP del listado a un error con mensaje para el cliente.
  ///
  /// El backend documenta: 401 sin JWT válido, 403 rol/alcance no permitido,
  /// 422 filtros rechazados (por ejemplo `fecha_desde` posterior a
  /// `fecha_hasta`).
  HistorialComprasException _errorListado(int statusCode) {
    switch (statusCode) {
      case 401:
        return const HistorialComprasException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const HistorialComprasException(
          _listadoForbiddenMessage,
          statusCode: 403,
        );
      case 422:
        return const HistorialComprasException(
          _listadoFiltrosMessage,
          statusCode: 422,
          filtrosInvalidos: true,
        );
      default:
        return HistorialComprasException(
          _listadoServidorMessage,
          statusCode: statusCode,
        );
    }
  }

  /// Traduce el estado HTTP del detalle a un error con mensaje para el cliente.
  ///
  /// El backend documenta: 404 venta inexistente, 403 compra de otro cliente,
  /// 409 venta aún no histórica (PENDIENTE/PAGADA).
  HistorialComprasException _errorDetalle(int statusCode) {
    switch (statusCode) {
      case 401:
        return const HistorialComprasException(
          _unauthorizedMessage,
          statusCode: 401,
          unauthorized: true,
        );
      case 403:
        return const HistorialComprasException(
          _detalleForbiddenMessage,
          statusCode: 403,
        );
      case 404:
        return const HistorialComprasException(
          _detalleNoEncontradaMessage,
          statusCode: 404,
        );
      case 409:
        return const HistorialComprasException(
          _detalleNoHistoricaMessage,
          statusCode: 409,
          aunNoHistorica: true,
        );
      default:
        return HistorialComprasException(
          _detalleMessage,
          statusCode: statusCode,
        );
    }
  }

  /// Cabeceras de la petición, con el JWT del cliente.
  Future<Map<String, String>> _headers({required bool detalle}) async {
    final String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      throw HistorialComprasException(
        detalle ? _detalleMessage : _listadoServidorMessage,
      );
    }
    if (token == null || token.isEmpty) {
      throw const HistorialComprasException(
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
      throw const HistorialComprasException(ApiConfig.missingBaseUrlHint);
    }
  }

  /// Convierte una fecha a `YYYY-MM-DD` (formato que espera el backend).
  ///
  /// Se arma desde los componentes locales, igual que `formatearIsoLocal` de
  /// `core/utils/date_formatters.dart`: no se hacen conversiones de zona
  /// horaria arbitrarias, la fecha es la que eligió el cliente.
  String _fechaQuery(DateTime fecha) {
    final DateTime local = fecha.toLocal();
    return '${local.year.toString().padLeft(4, '0')}'
        '-${_dosDigitos(local.month)}'
        '-${_dosDigitos(local.day)}';
  }

  String _dosDigitos(int valor) => valor.toString().padLeft(2, '0');
}
