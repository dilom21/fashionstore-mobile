import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../autenticacion_seguridad/pages/login/login_page.dart';
import '../../autenticacion_seguridad/services/auth_service.dart';
import '../../carrito/pages/carritos_page.dart';
import '../../catalogo/pages/catalogo_page.dart';
import '../../reservas/pages/reservas_page.dart';
import '../../vestidor_virtual/pages/vestidor_virtual_page.dart';
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
  /// Índice de la pestaña Catálogo.
  static const int _tabCatalogo = 1;

  /// Índice de la pestaña Carrito.
  static const int _tabCarrito = 3;

  int _selectedIndex = 0;

  /// Permite refrescar el carrito al volver a su pestaña: el `IndexedStack`
  /// mantiene viva la página, así que `initState` no es suficiente.
  final GlobalKey<CarritosPageState> _carritoKey =
      GlobalKey<CarritosPageState>();

  /// Secciones de la navegación inferior (Inicio es la inicial).
  late final List<Widget> _secciones = <Widget>[
    const InicioPage(),
    const CatalogoPage(),
    const VestidorVirtualPage(),
    CarritosPage(
      key: _carritoKey,
      onExplorarCatalogo: () => _irATab(_tabCatalogo),
    ),
    _PerfilPlaceholderPage(onVerCarrito: () => _irATab(_tabCarrito)),
  ];

  void _irATab(int index) {
    if (!mounted) return;
    setState(() => _selectedIndex = index);
  }

  void _onDestinationSelected(int index) {
    setState(() => _selectedIndex = index);
    if (index == _tabCarrito) {
      _carritoKey.currentState?.recargar();
    }
  }

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
          onDestinationSelected: _onDestinationSelected,
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
/// Opción táctil del perfil.
class _OpcionPerfil extends StatelessWidget {
  const _OpcionPerfil({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Perfil del cliente.
///
/// Ofrece el acceso real a "Mis reservas" (CU16) y el cierre de sesión; el
/// resto del perfil se implementará en otro caso de uso.
class _PerfilPlaceholderPage extends StatefulWidget {
  const _PerfilPlaceholderPage({required this.onVerCarrito});

  /// Permite que "VER CARRITO" (estado vacío de reservas) cambie de pestaña.
  final VoidCallback onVerCarrito;

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

  void _abrirReservas() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReservasPage(onVerCarrito: widget.onVerCarrito),
      ),
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
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              children: [
                Row(
                  children: [
                    Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Perfil',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Tu información personal estará disponible '
                            'próximamente.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'MI CUENTA',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                _OpcionPerfil(
                  icon: Icons.event_available_rounded,
                  titulo: 'Mis reservas',
                  subtitulo: 'Consulta y administra tus reservas de prendas.',
                  onTap: _abrirReservas,
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


