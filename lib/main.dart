import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'features/autenticacion_seguridad/pages/login/login_page.dart';
import 'features/autenticacion_seguridad/services/auth_service.dart';
import 'features/inicio/pages/main_navigation_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FashionStoreApp());
}

/// Aplicación móvil de VANTER MEN para CLIENTES.
///
/// Al arrancar comprueba si existe una sesión guardada válida antes de mostrar
/// el login, evitando un parpadeo entre Login e Inicio.
class FashionStoreApp extends StatelessWidget {
  /// Crea la aplicación.
  const FashionStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VANTER MEN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
      ),
      home: const _SessionGate(),
    );
  }
}

/// Decide la pantalla inicial comprobando la sesión guardada.
///
/// Mientras se resuelve (`GET /auth/me`), muestra una pantalla de carga mínima.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  final AuthService _authService = AuthService();
  late final Future<bool> _restauracion;

  @override
  void initState() {
    super.initState();
    _restauracion = _authService.restaurarSesion();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _restauracion,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashLoadingScreen();
        }
        return (snapshot.data ?? false)
            ? const MainNavigationPage()
            : const LoginPage();
      },
    );
  }
}

/// Pantalla de carga inicial (marca + indicador discreto).
class _SplashLoadingScreen extends StatelessWidget {
  const _SplashLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'VANTER MEN',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
