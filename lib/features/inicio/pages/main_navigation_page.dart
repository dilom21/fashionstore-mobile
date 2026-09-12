import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../autenticacion_seguridad/pages/login/login_page.dart';
import '../../autenticacion_seguridad/services/auth_service.dart';
import 'inicio_page.dart';

/// Contenedor principal del CLIENTE autenticado.
///
/// Agrupa la navegación inferior premium de VANTER MEN con cinco secciones:
/// Inicio, Catálogo, Vestidor, Carrito y Perfil. Las secciones que todavía no
/// tienen funcionalidad real muestran una pantalla temporal elegante.
class MainNavigationPage extends StatefulWidget {
  /// Crea el contenedor de navegación principal.
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  /// Secciones de la navegación inferior (Inicio es la inicial).
  static const List<Widget> _secciones = [
    InicioPage(),
    _CatalogoPlaceholderPage(),
    _VestidorPlaceholderPage(),
    _CarritoPlaceholderPage(),
    _PerfilPlaceholderPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _selectedIndex, children: _secciones),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final bool selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.textPrimary : AppColors.inactive,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final bool selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              color: selected ? AppColors.primary : AppColors.inactive,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Catálogo',
            ),
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt_rounded),
              label: 'Vestidor',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag_rounded),
              label: 'Carrito',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
/// Pantalla temporal reutilizable para secciones aún no implementadas.
class _SeccionProximamente extends StatelessWidget {
  const _SeccionProximamente({
    required this.title,
    required this.icon,
    required this.message,
  });

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 76,
                  width: 76,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 32),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Disponible próximamente.',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder de Catálogo (sin funcionalidad real todavía).
class _CatalogoPlaceholderPage extends StatelessWidget {
  const _CatalogoPlaceholderPage();

  @override
  Widget build(BuildContext context) => const _SeccionProximamente(
        title: 'Catálogo',
        icon: Icons.grid_view_rounded,
        message: 'Muy pronto podrás descubrir nuestras colecciones.',
      );
}

/// Placeholder del Vestidor Virtual (futuro acceso a la cámara).
class _VestidorPlaceholderPage extends StatelessWidget {
  const _VestidorPlaceholderPage();

  @override
  Widget build(BuildContext context) => const _SeccionProximamente(
        title: 'Vestidor Virtual',
        icon: Icons.camera_alt_rounded,
        message: 'Próximamente podrás probar nuevas experiencias utilizando '
            'la cámara de tu dispositivo.',
      );
}

/// Placeholder del Carrito (sin funcionalidad real todavía).
class _CarritoPlaceholderPage extends StatelessWidget {
  const _CarritoPlaceholderPage();

  @override
  Widget build(BuildContext context) => const _SeccionProximamente(
        title: 'Carrito',
        icon: Icons.shopping_bag_rounded,
        message: 'Tu experiencia de compra estará disponible próximamente.',
      );
}

/// Placeholder de Perfil.
///
/// Incluye temporalmente un botón para probar el cierre de sesión, ya que
/// todavía no existe la funcionalidad real de perfil.
class _PerfilPlaceholderPage extends StatefulWidget {
  const _PerfilPlaceholderPage();

  @override
  State<_PerfilPlaceholderPage> createState() => _PerfilPlaceholderPageState();
}

class _PerfilPlaceholderPageState extends State<_PerfilPlaceholderPage> {
  final AuthService _authService = AuthService();
  bool _cerrandoSesion = false;

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) return;
    setState(() => _cerrandoSesion = true);

    await _authService.cerrarSesion();
    if (!mounted) return;

    // Limpia toda la pila: el botón atrás no vuelve al área autenticada.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Perfil',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 76,
                  width: 76,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Perfil',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tu información personal estará disponible próximamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _cerrandoSesion ? null : _cerrarSesion,
                  icon: _cerrandoSesion
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.textMuted,
                            ),
                          ),
                        )
                      : const Icon(Icons.logout_rounded, size: 18),
                  label: const Text(
                    'Cerrar sesión',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


