import 'package:flutter/material.dart';

import '../../features/autenticacion_seguridad/pages/login/login_page.dart';
import '../storage/auth_storage.dart';

/// Manejo central de la sesión expirada (JWT rechazado por el backend).
///
/// Elimina el token local y devuelve al login mostrando el aviso una sola vez.
/// Se reutiliza desde cualquier feature autenticada (por ejemplo CU15 carrito)
/// para no duplicar la lógica en cada página.
class SessionExpired {
  /// Clase de solo utilidades: no debe instanciarse.
  const SessionExpired._();

  /// Mensaje por defecto cuando el backend responde 401.
  static const String mensajePorDefecto =
      'Tu sesión expiró. Vuelve a iniciar sesión.';

  /// Cierra la sesión local y navega al login.
  static Future<void> manejar(BuildContext context, {String? mensaje}) async {
    try {
      await AuthStorage().deleteToken();
    } catch (_) {
      // Aunque el almacenamiento falle, se fuerza el regreso al login.
    }
    if (!context.mounted) return;

    // Se captura antes de navegar: el ScaffoldMessenger raíz de MaterialApp
    // sobrevive al reemplazo de rutas.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (Route<dynamic> route) => false,
    );

    final String aviso = (mensaje?.trim().isNotEmpty ?? false)
        ? mensaje!.trim()
        : mensajePorDefecto;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(aviso), duration: const Duration(seconds: 3)),
      );
  }
}
