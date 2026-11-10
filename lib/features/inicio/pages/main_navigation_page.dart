import 'package:flutter/material.dart';

import '../../../core/session/session_expired.dart';
import '../../../core/storage/tenant_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../autenticacion_seguridad/models/auth_models.dart';
import '../../autenticacion_seguridad/pages/login/login_page.dart';
import '../../autenticacion_seguridad/services/auth_service.dart';
import '../../carrito/pages/carritos_page.dart';
import '../../catalogo/pages/catalogo_page.dart';
import '../../reservas/pages/reservas_page.dart';
import '../../ventas/pages/historial_compras_page.dart';
import 'inicio_page.dart';

/// Contenedor principal del CLIENTE autenticado.
///
/// Navegación inferior SaaS: Inicio, Catálogo, Carrito y Perfil. El Vestidor
/// Virtual y la Asistencia Inteligente quedan temporalmente fuera de la
/// navegación hasta que sus contratos se adapten a SaaS.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  static const int _tabCatalogo = 1;
  static const int _tabCarrito = 2;

  int _selectedIndex = 0;

  final GlobalKey<CarritosPageState> _carritoKey =
      GlobalKey<CarritosPageState>();

  late final List<Widget> _secciones = <Widget>[
    InicioPage(
      onExplorarCatalogo: () => _irATab(_tabCatalogo),
      onVerCarrito: () => _irATab(_tabCarrito),
      onVerReservas: _abrirReservas,
      onVerCompras: _abrirHistorialCompras,
    ),
    const CatalogoPage(),
    CarritosPage(
      key: _carritoKey,
      onExplorarCatalogo: () => _irATab(_tabCatalogo),
    ),
    _PerfilClientePage(onVerCarrito: () => _irATab(_tabCarrito)),
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

  void _abrirReservas() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReservasPage(onVerCarrito: () => _irATab(_tabCarrito)),
      ),
    );
  }

  void _abrirHistorialCompras() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HistorialComprasPage()),
    );
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

/// Perfil real del CLIENTE SaaS.
///
/// Los datos provienen de `GET /auth/tenant/me`; el backend es la autoridad.
/// No existe contrato SaaS de edición de perfil, por lo que la pantalla es de
/// solo lectura y no simula guardados.
class _PerfilClientePage extends StatefulWidget {
  const _PerfilClientePage({required this.onVerCarrito});

  final VoidCallback onVerCarrito;

  @override
  State<_PerfilClientePage> createState() => _PerfilClientePageState();
}

class _PerfilClientePageState extends State<_PerfilClientePage> {
  final AuthService _authService = AuthService();

  UsuarioAuth? _usuario;
  String _correoMostrado = '';
  bool _cargando = true;
  bool _cerrandoSesion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final UsuarioAuth usuario = await _authService.obtenerUsuarioActual();
      final TenantSession? sesion = await _authService.leerSesion();
      if (!mounted) return;
      setState(() {
        _usuario = usuario;
        _correoMostrado = usuario.correo.trim().isNotEmpty
            ? usuario.correo
            : (sesion?.correo ?? '');
        _cargando = false;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      if (error.unauthorized) {
        setState(() => _cargando = false);
        await SessionExpired.manejar(context, mensaje: error.message);
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tu perfil. Inténtalo nuevamente.';
        _cargando = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) return;
    setState(() => _cerrandoSesion = true);

    await _authService.cerrarSesion();
    if (!mounted) return;

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

  void _abrirHistorialCompras() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HistorialComprasPage()),
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
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargarPerfil,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _contenido()),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 34,
              ),
              const SizedBox(height: 14),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _cargarPerfil,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final UsuarioAuth? usuario = _usuario;
    if (usuario == null) {
      return const Center(
        child: Text(
          'Perfil no disponible.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    final bool tieneNombre = usuario.nombreCompleto.isNotEmpty;
    final String nombre = tieneNombre ? usuario.nombreCompleto : 'Cliente';
    final String inicial = tieneNombre
        ? nombre.trim().substring(0, 1).toUpperCase()
        : 'C';

    return Center(
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
                    gradient: AppColors.accentGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Text(
                      inicial,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _correoMostrado.trim().isEmpty
                            ? 'Correo no expuesto por el contrato SaaS'
                            : _correoMostrado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'MI EMPRESA',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            _TarjetaPerfil(
              child: Column(
                children: [
                  _DatoPerfil(
                    etiqueta: 'Empresa',
                    valor: usuario.empresaNombre.isEmpty
                        ? usuario.empresaSlug
                        : usuario.empresaNombre,
                  ),
                  _DatoPerfil(etiqueta: 'Rol', valor: usuario.rol),
                  _DatoPerfil(etiqueta: 'Usuario', valor: '${usuario.id}'),
                  if (usuario.planCodigo.trim().isNotEmpty)
                    _DatoPerfil(etiqueta: 'Plan', valor: usuario.planCodigo),
                  if (usuario.sucursalId != null)
                    _DatoPerfil(
                      etiqueta: 'Sucursal',
                      valor: '${usuario.sucursalId}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
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
              subtitulo: 'Consulta y administra tus reservas online.',
              onTap: _abrirReservas,
            ),
            const SizedBox(height: 12),
            _OpcionPerfil(
              icon: Icons.receipt_long_rounded,
              titulo: 'Mis compras',
              subtitulo: 'Consulta tu historial y tus comprobantes.',
              onTap: _abrirHistorialCompras,
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
    );
  }
}

/// Tarjeta base del perfil.
class _TarjetaPerfil extends StatelessWidget {
  const _TarjetaPerfil({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Fila etiqueta/valor del perfil.
class _DatoPerfil extends StatelessWidget {
  const _DatoPerfil({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              valor.trim().isEmpty ? 'No disponible' : valor.trim(),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
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
