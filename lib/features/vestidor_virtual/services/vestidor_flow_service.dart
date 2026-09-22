import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/theme/app_colors.dart';
import '../models/vestidor_config_model.dart';
import '../models/vestidor_motor_resultado.dart';
import '../models/vestidor_session_model.dart';
import '../pages/camara_vestidor_page.dart';
import 'vestidor_api_service.dart';

/// Resultado del flujo reutilizable del vestidor.
enum VestidorFlowResultado {
  completado,
  cancelado,
  noDisponible,
  error,
  sesionExpirada,
}

/// Abre el motor AR y devuelve su resultado. Inyectable en pruebas.
typedef VestidorMotorLauncher = Future<VestidorMotorResultado> Function(
  BuildContext context,
  VestidorConfig configuracion,
);

/// Cierra la sesión local cuando el JWT fue rechazado. Inyectable en pruebas.
typedef VestidorSesionExpiradaHandler = Future<void> Function(
  BuildContext context,
  String? mensaje,
);

/// Lógica ÚNICA y reutilizable del CU26 - Vestidor virtual.
///
/// Orquesta el ciclo de negocio completo SIN duplicar código entre pantallas:
/// resuelve las configuraciones AR del producto, crea la sesión, registra la
/// prueba, abre el motor local (`CamaraVestidorPage`) y cierra la prueba/sesión
/// según cómo terminó la experiencia de cámara.
///
/// El motor AR sigue siendo 100% local: este servicio es el único que habla con
/// el backend. Las dependencias (API, launcher del motor y manejo de sesión
/// expirada) son inyectables para poder probar el flujo sin red ni cámara.
class VestidorFlowService {
  VestidorFlowService({
    VestidorApiService? api,
    VestidorMotorLauncher? motorLauncher,
    VestidorSesionExpiradaHandler? sesionExpirada,
  }) : _api = api ?? VestidorApiService(),
       _motorLauncher = motorLauncher ?? abrirMotorPorDefecto,
       _sesionExpirada = sesionExpirada ?? _sesionExpiradaPorDefecto;

  /// Mensaje controlado cuando la prenda no tiene AR usable.
  static const String mensajeNoDisponible =
      'Esta prenda todavía no está disponible en el vestidor virtual.';

  static const String mensajeError =
      'No pudimos preparar el vestidor virtual. Inténtalo nuevamente.';

  final VestidorApiService _api;
  final VestidorMotorLauncher _motorLauncher;
  final VestidorSesionExpiradaHandler _sesionExpirada;

  /// Abre el motor AR con el resultado del ciclo de negocio.
  ///
  /// [varianteId] viaja al backend cuando no es null y es mayor que cero.
  Future<VestidorFlowResultado> abrirVestidor(
    BuildContext context, {
    required int productoId,
    int? varianteId,
  }) async {
    // Referencias para la compensación: se van poblando a medida que avanza el
    // ciclo de negocio y permiten deshacer lo creado si algo falla después.
    VestidorSesion? sesion;
    VestidorPrueba? prueba;

    try {
      final VestidorConfiguracionesResponse respuesta = await _api
          .obtenerConfiguraciones(
            productoId: productoId,
            varianteId: varianteId,
          );

      final List<VestidorConfig> usables = respuesta.configuraciones
          .where((VestidorConfig config) => config.esUsable && config.esTorso)
          .toList();

      if (!respuesta.compatible || usables.isEmpty) {
        if (context.mounted) _mostrarMensaje(context, mensajeNoDisponible);
        return VestidorFlowResultado.noDisponible;
      }

      // Con una sola opción no se pregunta; con varias el cliente elige el color
      // y NUNCA se selecciona una por él.
      final VestidorConfig? elegida;
      if (usables.length == 1) {
        elegida = usables.first;
      } else {
        // Sin UI viva no se puede mostrar el selector: se cancela sin crear nada.
        if (!context.mounted) return VestidorFlowResultado.cancelado;
        elegida = await _elegirConfiguracion(context, usables);
      }
      if (elegida == null) return VestidorFlowResultado.cancelado;

      final VestidorSesion sesionCreada = await _api.crearSesion();
      sesion = sesionCreada;

      final VestidorPrueba pruebaIniciada = await _api.iniciarPrueba(
        sesionId: sesionCreada.sesionId,
        configuracionId: elegida.configuracionId,
        varianteProductoId: varianteId,
      );
      prueba = pruebaIniciada;

      // Sin UI viva no se puede abrir el motor: se compensa lo ya creado.
      if (!context.mounted) {
        await _compensar(sesion, prueba);
        return VestidorFlowResultado.cancelado;
      }

      // El launcher nunca debe romper el flujo: una excepción del motor se
      // traduce a un error controlado.
      VestidorMotorResultado resultadoMotor;
      try {
        resultadoMotor = await _motorLauncher(context, elegida);
      } catch (error) {
        debugPrint('[CU26] El motor AR falló: $error');
        resultadoMotor = VestidorMotorResultado.error;
      }

      return await _cerrar(sesionCreada, pruebaIniciada, resultadoMotor);
    } on VestidorApiException catch (error) {
      if (error.unauthorized) {
        if (context.mounted) await _sesionExpirada(context, error.message);
        await _compensar(sesion, prueba);
        return VestidorFlowResultado.sesionExpirada;
      }
      // La compensación es best-effort: jamás oculta el error original.
      await _compensar(sesion, prueba);
      if (context.mounted) _mostrarMensaje(context, error.message);
      return VestidorFlowResultado.error;
    } catch (_) {
      await _compensar(sesion, prueba);
      if (context.mounted) _mostrarMensaje(context, mensajeError);
      return VestidorFlowResultado.error;
    }
  }

  /// Cierra prueba y sesión según el resultado del motor.
  Future<VestidorFlowResultado> _cerrar(
    VestidorSesion sesion,
    VestidorPrueba prueba,
    VestidorMotorResultado resultado,
  ) async {
    switch (resultado) {
      case VestidorMotorResultado.completada:
        await _api.finalizarPrueba(
          pruebaId: prueba.pruebaId,
          estado: VestidorPruebaEstado.completada,
        );
        await _api.finalizarSesion(
          sesionId: sesion.sesionId,
          estado: VestidorSesionEstado.finalizada,
        );
        return VestidorFlowResultado.completado;
      case VestidorMotorResultado.cancelada:
        await _api.finalizarPrueba(
          pruebaId: prueba.pruebaId,
          estado: VestidorPruebaEstado.cancelada,
        );
        await _api.finalizarSesion(
          sesionId: sesion.sesionId,
          estado: VestidorSesionEstado.cancelada,
        );
        return VestidorFlowResultado.cancelado;
      case VestidorMotorResultado.error:
        await _api.finalizarPrueba(
          pruebaId: prueba.pruebaId,
          estado: VestidorPruebaEstado.error,
        );
        await _api.finalizarSesion(
          sesionId: sesion.sesionId,
          estado: VestidorSesionEstado.cancelada,
        );
        return VestidorFlowResultado.error;
    }
  }

  /// Intenta dejar el ciclo de negocio consistente tras un fallo.
  ///
  /// Es best-effort: si la compensación también falla, solo se registra en
  /// consola y el resultado original se conserva.
  Future<void> _compensar(
    VestidorSesion? sesion,
    VestidorPrueba? prueba,
  ) async {
    if (prueba != null) {
      try {
        await _api.finalizarPrueba(
          pruebaId: prueba.pruebaId,
          estado: VestidorPruebaEstado.error,
        );
      } catch (error) {
        debugPrint(
          '[CU26] Compensación: no se pudo marcar la prueba ERROR: $error',
        );
      }
    }
    if (sesion != null) {
      try {
        await _api.finalizarSesion(
          sesionId: sesion.sesionId,
          estado: VestidorSesionEstado.cancelada,
        );
      } catch (error) {
        debugPrint(
          '[CU26] Compensación: no se pudo cancelar la sesión: $error',
        );
      }
    }
  }

  /// Muestra el selector de color cuando hay varias configuraciones usables.
  ///
  /// Devuelve `null` si el cliente cierra el diálogo (no se crea nada).
  Future<VestidorConfig?> _elegirConfiguracion(
    BuildContext context,
    List<VestidorConfig> opciones,
  ) {
    return showDialog<VestidorConfig>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Elige el color'),
        children: <Widget>[
          for (final VestidorConfig config in opciones)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(config),
              child: Text(config.colorEtiqueta),
            ),
        ],
      ),
    );
  }

  void _mostrarMensaje(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)),
      );
  }

  /// Launcher por defecto: push de `CamaraVestidorPage` esperando su resultado.
  static Future<VestidorMotorResultado> abrirMotorPorDefecto(
    BuildContext context,
    VestidorConfig configuracion,
  ) async {
    final VestidorMotorResultado? resultado = await Navigator.of(context)
        .push<VestidorMotorResultado>(
          MaterialPageRoute<VestidorMotorResultado>(
            builder: (_) => CamaraVestidorPage(configuracion: configuracion),
          ),
        );
    return resultado ?? VestidorMotorResultado.cancelada;
  }

  /// Manejo por defecto de la sesión expirada (delega en [SessionExpired]).
  static Future<void> _sesionExpiradaPorDefecto(
    BuildContext context,
    String? mensaje,
  ) => SessionExpired.manejar(context, mensaje: mensaje);
}
