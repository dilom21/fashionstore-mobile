import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inicio/pages/main_navigation_page.dart';
import '../../models/auth_models.dart';
import '../../services/auth_service.dart';
import '../registro/registro_cliente_page.dart';

/// Pantalla de inicio de sesión del CLIENTE SaaS.
///
/// Flujo: seleccionar empresa (`GET /auth/tenant/empresas`) -> credenciales ->
/// `POST /auth/tenant/login` -> validación `/auth/tenant/me` -> área comercial.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  List<EmpresaTenant> _empresas = <EmpresaTenant>[];
  EmpresaTenant? _empresa;
  bool _cargandoEmpresas = true;
  String? _errorEmpresas;

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _cargarEmpresas();
  }

  @override
  void dispose() {
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Carga las empresas habilitadas una sola vez (sin solicitudes duplicadas).
  Future<void> _cargarEmpresas() async {
    if (!_cargandoEmpresas && _empresas.isNotEmpty) return;
    setState(() {
      _cargandoEmpresas = true;
      _errorEmpresas = null;
    });
    try {
      final List<EmpresaTenant> empresas = await _authService.listarEmpresas();
      if (!mounted) return;
      setState(() {
        _empresas = empresas;
        _empresa = empresas.isEmpty ? null : empresas.first;
        _cargandoEmpresas = false;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _cargandoEmpresas = false;
        _errorEmpresas = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoEmpresas = false;
        _errorEmpresas =
            'No pudimos cargar las empresas. Inténtalo nuevamente.';
      });
    }
  }

  Future<void> _iniciarSesion() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    final EmpresaTenant? empresa = _empresa;
    final bool datosValidos = _formKey.currentState?.validate() ?? false;
    if (!datosValidos) return;
    if (empresa == null) {
      setState(() => _errorMessage = 'Selecciona una empresa.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.loginCliente(
        correo: _correoController.text.trim(),
        password: _passwordController.text,
        empresaSlug: empresa.slug,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Ocurrió un problema. Inténtalo nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Abre el registro conservando la empresa seleccionada.
  Future<void> _abrirRegistro() async {
    if (_isLoading) return;
    final EmpresaTenant? empresa = _empresa;
    if (empresa == null) {
      setState(
        () => _errorMessage = 'Selecciona una empresa para registrarte.',
      );
      return;
    }

    final String? correo = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => RegistroClientePage(
          empresaSlug: empresa.slug,
          empresaNombre: empresa.etiqueta,
        ),
      ),
    );
    if (!mounted) return;
    if (correo == null || correo.trim().isEmpty) return;

    setState(() {
      _correoController.text = correo.trim();
      _passwordController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _seleccionarEmpresa() async {
    if (_cargandoEmpresas || _empresas.isEmpty) return;
    final EmpresaTenant? elegida = await showModalBottomSheet<EmpresaTenant>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            const Text(
              'SELECCIONA TU EMPRESA',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final EmpresaTenant empresa in _empresas)
              ListTile(
                leading: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  empresa.etiqueta,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: _empresa?.slug == empresa.slug
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight: _empresa?.slug == empresa.slug
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  empresa.slug,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                trailing: _empresa?.slug == empresa.slug
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(empresa),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    setState(() => _empresa = elegida);
  }

  void _mostrarProximamente() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Disponible próximamente.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  String? _validarCorreo(String? value) {
    final String correo = value?.trim() ?? '';
    if (correo.isEmpty) return 'Ingresa tu correo electrónico.';
    final RegExp regex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
    if (!regex.hasMatch(correo)) return 'Ingresa un correo válido.';
    return null;
  }

  String? _validarPassword(String? value) {
    if (value == null || value.isEmpty) return 'Ingresa tu contraseña.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildEncabezado(),
                      const SizedBox(height: 32),
                      _buildFormulario(),
                      const SizedBox(height: 26),
                      _buildPie(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'FASHIONSTORE',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'CUENTA DE CLIENTE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Bienvenido de nuevo',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _empresa == null
              ? 'Selecciona tu empresa para acceder a tu cuenta.'
              : 'Accede a ${_empresa!.etiqueta}.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildFormulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectorEmpresa(
          empresa: _empresa,
          cargando: _cargandoEmpresas,
          error: _errorEmpresas,
          habilitado: !_isLoading,
          onTap: _seleccionarEmpresa,
          onReintentar: _cargarEmpresas,
        ),
        const SizedBox(height: 18),
        _CampoTexto(
          controller: _correoController,
          label: 'Correo electrónico',
          hint: 'tucorreo@ejemplo.com',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_isLoading,
          validator: _validarCorreo,
        ),
        const SizedBox(height: 18),
        _CampoTexto(
          controller: _passwordController,
          label: 'Contraseña',
          hint: 'Tu contraseña',
          icon: Icons.lock_outline,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          validator: _validarPassword,
          onSubmitted: (_) => _iniciarSesion(),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            tooltip: _obscurePassword
                ? 'Mostrar contraseña'
                : 'Ocultar contraseña',
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _mostrarProximamente,
            child: const Text(
              '¿Olvidaste tu contraseña?',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ),
        if (_errorMessage != null) _buildError(),
        const SizedBox(height: 6),
        _BotonPrincipal(
          label: 'INICIAR SESIÓN',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _iniciarSesion,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPie() {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(
              child: Divider(color: AppColors.border, thickness: 1, height: 1),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            Expanded(
              child: Divider(color: AppColors.border, thickness: 1, height: 1),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          '¿Aún no tienes una cuenta?',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: _isLoading ? null : _abrirRegistro,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Crear cuenta',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'ESTILO. DISCIPLINA. RESULTADOS.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Selector visual de empresa con estados de carga, error y lista vacía.
class _SelectorEmpresa extends StatelessWidget {
  const _SelectorEmpresa({
    required this.empresa,
    required this.cargando,
    required this.error,
    required this.habilitado,
    required this.onTap,
    required this.onReintentar,
  });

  final EmpresaTenant? empresa;
  final bool cargando;
  final String? error;
  final bool habilitado;
  final VoidCallback onTap;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Empresa',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        if (cargando)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Cargando empresas...',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          )
        else if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else if (empresa == null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'No hay empresas habilitadas.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          )
        else
          Material(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: habilitado ? onTap : null,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            empresa!.etiqueta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            empresa!.slug,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Campo de texto con el estilo visual de la aplicación.
class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.suffix,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          autocorrect: false,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.inactive, fontSize: 14),
            prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
            suffixIcon: suffix,
            filled: true,
            fillColor: AppColors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 12,
            ),
            errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
            border: _borde(AppColors.border),
            enabledBorder: _borde(AppColors.border),
            focusedBorder: _borde(AppColors.primary),
            errorBorder: _borde(AppColors.error),
            focusedErrorBorder: _borde(AppColors.error),
            disabledBorder: _borde(AppColors.border),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _borde(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color),
  );
}

/// Botón principal con gradiente de acento.
class _BotonPrincipal extends StatelessWidget {
  const _BotonPrincipal({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.65,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
