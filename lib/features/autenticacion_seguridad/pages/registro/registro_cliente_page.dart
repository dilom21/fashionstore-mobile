import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatters.dart';
import '../../models/auth_models.dart';
import '../../services/auth_service.dart';
import '../../utils/password_strength.dart';

/// Registro PÚBLICO de cuenta de CLIENTE de VANTER MEN.
///
/// Flujo: Login -> [Crear cuenta] -> esta pantalla ->
/// `AuthService.registrarCliente` -> `POST /auth/clientes/registro`.
///
/// El endpoint es público y responde 201 **sin** `access_token`: al terminar se
/// muestra una confirmación y se vuelve al Login con el correo precargado. NO
/// hay auto-login, NO se guarda JWT y NO se llama a `loginCliente()`.
class RegistroClientePage extends StatefulWidget {
  /// Crea la pantalla de registro de cliente.
  const RegistroClientePage({super.key, this.authService});

  /// Servicio inyectable (mismo patrón que el resto de la app).
  final AuthService? authService;

  @override
  State<RegistroClientePage> createState() => _RegistroClientePageState();
}

class _RegistroClientePageState extends State<RegistroClientePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _apellidoController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _ciController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmacionController =
      TextEditingController();

  late final AuthService _authService;

  SexoCliente? _sexo;
  DateTime? _fechaNacimiento;

  /// Ojos independientes para cada contraseña.
  bool _mostrarPassword = false;
  bool _mostrarConfirmacion = false;

  PasswordStrength _fortaleza = PasswordStrength.evaluar('');

  bool _enviando = false;
  String? _errorMessage;
  String? _errorSexo;
  String? _errorFecha;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _correoController.dispose();
    _ciController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    _passwordConfirmacionController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Estado del formulario
  // -------------------------------------------------------------------------

  /// Recalcula la fortaleza en tiempo real (sin llamar al backend).
  ///
  /// Se refresca con cada cambio: además de la barra y el checklist, el
  /// formulario depende de la contraseña escrita (por ejemplo, para saber si
  /// ya coincide con la confirmación).
  void _actualizarFortaleza() {
    setState(() {
      _fortaleza = PasswordStrength.evaluar(_passwordController.text);
    });
  }

  /// Refresca el estado del CTA cuando cambia la confirmación.
  void _refrescarEstado() => setState(() {});

  /// El CTA se ve habilitado solo cuando todo está completo y válido.
  ///
  /// Aun así el toque ejecuta las validaciones y muestra el error sin llamar al
  /// backend, para no enviar datos incompletos.
  bool get _puedeEnviar {
    if (_enviando) return false;
    if (_sexo == null) return false;
    if (_fechaNacimiento == null) return false;
    if (!_fortaleza.valida) return false;
    return _passwordController.text == _passwordConfirmacionController.text;
  }

  // -------------------------------------------------------------------------
  // Validaciones (mismas reglas que el backend)
  // -------------------------------------------------------------------------

  String? _validarNombre(String? value) {
    final String texto = value?.trim() ?? '';
    if (texto.isEmpty) return 'Ingresa tu nombre.';
    if (texto.length < 2) return 'El nombre debe tener al menos 2 caracteres.';
    if (texto.length > 100) return 'El nombre no puede superar 100 caracteres.';
    return null;
  }

  String? _validarApellido(String? value) {
    final String texto = value?.trim() ?? '';
    if (texto.isEmpty) return 'Ingresa tu apellido.';
    if (texto.length < 2) {
      return 'El apellido debe tener al menos 2 caracteres.';
    }
    if (texto.length > 100) {
      return 'El apellido no puede superar 100 caracteres.';
    }
    return null;
  }

  String? _validarCorreo(String? value) {
    final String correo = value?.trim() ?? '';
    if (correo.isEmpty) return 'Ingresa tu correo electrónico.';
    if (correo.length < 5 || correo.length > 150) {
      return 'Ingresa un correo válido.';
    }
    final RegExp regex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');
    if (!regex.hasMatch(correo)) return 'Ingresa un correo válido.';
    return null;
  }

  /// El CI es texto: nunca se convierte a número ni se exige solo dígitos.
  String? _validarCi(String? value) {
    final String ci = value?.trim() ?? '';
    if (ci.isEmpty) return 'Ingresa tu documento.';
    if (ci.length < 3) return 'El documento debe tener al menos 3 caracteres.';
    if (ci.length > 30) return 'El documento no puede superar 30 caracteres.';
    return null;
  }

  String? _validarTelefono(String? value) {
    final String telefono = value?.trim() ?? '';
    if (telefono.isEmpty) return 'Ingresa tu teléfono.';
    if (telefono.length > 30) {
      return 'El teléfono no puede superar 30 caracteres.';
    }
    return null;
  }

  String? _validarPassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Ingresa tu contraseña.';
    if (!PasswordStrength.evaluar(password).valida) {
      return 'La contraseña no cumple la política de seguridad.';
    }
    return null;
  }

  String? _validarConfirmacion(String? value) {
    final String confirmacion = value ?? '';
    if (confirmacion.isEmpty) return 'Confirma tu contraseña.';
    if (confirmacion != _passwordController.text) {
      return 'Las contraseñas no coinciden.';
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  /// Selector de sexo: guarda el valor REAL que espera el backend.
  void _seleccionarSexo(SexoCliente? sexo) {
    setState(() {
      _sexo = sexo;
      if (sexo != null) _errorSexo = null;
    });
  }

  /// `showDatePicker` sin fechas futuras (el backend también lo valida).
  Future<void> _elegirFechaNacimiento() async {
    final DateTime hoy = DateTime.now();
    final DateTime sugerida =
        _fechaNacimiento ?? DateTime(hoy.year - 18, hoy.month, hoy.day);

    final DateTime? elegida = await showDatePicker(
      context: context,
      initialDate: sugerida.isAfter(hoy) ? hoy : sugerida,
      firstDate: DateTime(hoy.year - 120, 1, 1),
      lastDate: hoy,
      helpText: 'FECHA DE NACIMIENTO',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
    );
    if (elegida == null || !mounted) return;

    setState(() {
      _fechaNacimiento = DateTime(elegida.year, elegida.month, elegida.day);
      _errorFecha = null;
    });
  }

  /// Envía el registro. Nunca guarda token ni inicia sesión.
  Future<void> _crearCuenta() async {
    if (_enviando) return;
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    final bool datosValidos = _formKey.currentState?.validate() ?? false;

    final SexoCliente? sexo = _sexo;
    final DateTime? fechaNacimiento = _fechaNacimiento;
    final bool passwordSegura = PasswordStrength.evaluar(
      _passwordController.text,
    ).valida;
    final bool coincide =
        _passwordController.text == _passwordConfirmacionController.text;

    setState(() {
      _errorSexo = sexo == null ? 'Selecciona tu sexo.' : null;
      _errorFecha = fechaNacimiento == null
          ? 'Selecciona tu fecha de nacimiento.'
          : null;
      if (!coincide) {
        _errorMessage = 'Las contraseñas no coinciden.';
      } else if (!passwordSegura) {
        _errorMessage = 'La contraseña no cumple la política de seguridad.';
      }
    });

    // No se envía nada si falta algo: el CTA sí explica el motivo.
    if (!datosValidos ||
        sexo == null ||
        fechaNacimiento == null ||
        !passwordSegura ||
        !coincide) {
      return;
    }

    setState(() => _enviando = true);

    try {
      final ClienteRegistroResponse respuesta = await _authService
          .registrarCliente(
            ClienteRegistroRequest(
              correo: _correoController.text.trim().toLowerCase(),
              password: _passwordController.text,
              passwordConfirmacion: _passwordConfirmacionController.text,
              nombre: _nombreController.text.trim(),
              apellido: _apellidoController.text.trim(),
              ci: _ciController.text.trim(),
              telefono: _telefonoController.text.trim(),
              sexo: sexo,
              fechaNacimiento: fechaNacimiento,
            ),
          );
      if (!mounted) return;
      setState(() => _enviando = false);
      await _mostrarCuentaCreada(respuesta);
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorMessage = 'Ocurrió un problema. Inténtalo nuevamente.';
      });
    }
  }

  /// Confirmación premium y regreso al Login con el correo (sin contraseña).
  Future<void> _mostrarCuentaCreada(ClienteRegistroResponse respuesta) async {
    final String correo = respuesta.correo.trim().isEmpty
        ? _correoController.text.trim().toLowerCase()
        : respuesta.correo.trim();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DialogoCuentaCreada(
        nombre: respuesta.nombrePila,
        correo: correo,
        onIniciarSesion: () => Navigator.of(dialogContext).pop(),
      ),
    );

    if (!mounted) return;
    // Devuelve el correo al Login: la contraseña nunca viaja entre pantallas.
    Navigator.of(context).pop(correo);
  }

  void _volverAlLogin() => Navigator.of(context).pop();

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: _enviando ? null : _volverAlLogin,
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'VANTER MEN',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildEncabezado(),
                      const SizedBox(height: 28),
                      const _TituloSeccionRegistro('DATOS PERSONALES'),
                      const SizedBox(height: 14),
                      _buildDatosPersonales(),
                      const SizedBox(height: 26),
                      const _TituloSeccionRegistro('SEGURIDAD'),
                      const SizedBox(height: 14),
                      _buildSeguridad(),
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 16),
                        _buildError(),
                      ],
                      const SizedBox(height: 22),
                      _BotonPrincipalRegistro(
                        label: 'CREAR CUENTA',
                        labelCargando: 'CREANDO CUENTA...',
                        isLoading: _enviando,
                        habilitado: _puedeEnviar,
                        onPressed: _enviando ? null : _crearCuenta,
                      ),
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
      children: <Widget>[
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
        const SizedBox(height: 18),
        const Text(
          'CREA TU CUENTA',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Únete a VANTER MEN y disfruta una experiencia personalizada.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildDatosPersonales() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CampoTextoRegistro(
          controller: _nombreController,
          label: 'Nombre',
          hint: 'Juan',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          enabled: !_enviando,
          autofillHints: const <String>[AutofillHints.givenName],
          validator: _validarNombre,
        ),
        const SizedBox(height: 16),
        _CampoTextoRegistro(
          controller: _apellidoController,
          label: 'Apellido',
          hint: 'Pérez',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
          enabled: !_enviando,
          autofillHints: const <String>[AutofillHints.familyName],
          validator: _validarApellido,
        ),
        const SizedBox(height: 16),
        _CampoTextoRegistro(
          controller: _correoController,
          label: 'Correo electrónico',
          hint: 'tucorreo@ejemplo.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_enviando,
          autofillHints: const <String>[AutofillHints.email],
          validator: _validarCorreo,
        ),
        const SizedBox(height: 16),
        _buildCiYTelefono(),
        const SizedBox(height: 16),
        _SelectorSexo(
          valor: _sexo,
          error: _errorSexo,
          habilitado: !_enviando,
          onChanged: _seleccionarSexo,
        ),
        const SizedBox(height: 16),
        _CampoFechaRegistro(
          valor: _fechaNacimiento,
          error: _errorFecha,
          habilitado: !_enviando,
          onTap: _elegirFechaNacimiento,
        ),
      ],
    );
  }

  /// CI y teléfono: dos columnas cuando hay ancho, apilados si no cabe.
  Widget _buildCiYTelefono() {
    final Widget ci = _CampoTextoRegistro(
      controller: _ciController,
      label: 'CI',
      hint: '12345678',
      icon: Icons.credit_card_rounded,
      textInputAction: TextInputAction.next,
      enabled: !_enviando,
      validator: _validarCi,
    );
    final Widget telefono = _CampoTextoRegistro(
      controller: _telefonoController,
      label: 'Teléfono',
      hint: '70000000',
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      enabled: !_enviando,
      validator: _validarTelefono,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Desde ~400 px caben dos columnas sin apretar el contenido.
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[ci, const SizedBox(height: 16), telefono],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: ci),
            const SizedBox(width: 14),
            Expanded(child: telefono),
          ],
        );
      },
    );
  }

  Widget _buildSeguridad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CampoTextoRegistro(
          controller: _passwordController,
          label: 'Contraseña',
          hint: 'Crea una contraseña segura',
          icon: Icons.lock_outline_rounded,
          obscureText: !_mostrarPassword,
          textInputAction: TextInputAction.next,
          enabled: !_enviando,
          onChanged: (_) => _actualizarFortaleza(),
          validator: _validarPassword,
          suffix: IconButton(
            onPressed: () =>
                setState(() => _mostrarPassword = !_mostrarPassword),
            tooltip: _mostrarPassword
                ? 'Ocultar contraseña'
                : 'Mostrar contraseña',
            icon: Icon(
              _mostrarPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BarraFortaleza(fortaleza: _fortaleza),
        const SizedBox(height: 12),
        _ChecklistPassword(fortaleza: _fortaleza),
        const SizedBox(height: 20),
        _CampoTextoRegistro(
          controller: _passwordConfirmacionController,
          label: 'Confirmar contraseña',
          hint: 'Repite tu contraseña',
          icon: Icons.lock_reset_rounded,
          obscureText: !_mostrarConfirmacion,
          textInputAction: TextInputAction.done,
          enabled: !_enviando,
          validator: _validarConfirmacion,
          onChanged: (_) => _refrescarEstado(),
          onSubmitted: (_) => _crearCuenta(),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _mostrarConfirmacion = !_mostrarConfirmacion),
            tooltip: _mostrarConfirmacion
                ? 'Ocultar contraseña'
                : 'Mostrar contraseña',
            icon: Icon(
              _mostrarConfirmacion
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
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
      children: <Widget>[
        Row(
          children: const <Widget>[
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
        const SizedBox(height: 18),
        const Text(
          '¿Ya tienes una cuenta?',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _enviando ? null : _volverAlLogin,
          child: const Text(
            'INICIAR SESIÓN',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'ESTILO • DISCIPLINA • RESULTADOS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==CU24REG_PARTE_G==
}

/// Título de sección del formulario de registro.
class _TituloSeccionRegistro extends StatelessWidget {
  const _TituloSeccionRegistro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// Campo de texto con la identidad visual de VANTER MEN.
class _CampoTextoRegistro extends StatelessWidget {
  const _CampoTextoRegistro({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.enabled = true,
    this.autofillHints,
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
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
          onChanged: onChanged,
          validator: validator,
          autofillHints: autofillHints,
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

/// Selector de sexo: muestra etiquetas legibles y envía el código real.
class _SelectorSexo extends StatelessWidget {
  const _SelectorSexo({
    required this.valor,
    required this.habilitado,
    required this.onChanged,
    this.error,
  });

  final SexoCliente? valor;
  final bool habilitado;
  final ValueChanged<SexoCliente?> onChanged;
  final String? error;

  Future<void> _abrirOpciones(BuildContext context) async {
    if (!habilitado) return;

    final SexoCliente? elegido = await showModalBottomSheet<SexoCliente>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 18),
            const Text(
              'SEXO',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final SexoCliente opcion in SexoCliente.values)
              ListTile(
                title: Text(
                  opcion.etiqueta,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: valor == opcion
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight: valor == opcion
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                trailing: valor == opcion
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(opcion),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (elegido == null) return;
    onChanged(elegido);
  }

  @override
  Widget build(BuildContext context) {
    final String? mensajeError = error;
    final bool hayError = mensajeError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Sexo',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _abrirOpciones(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hayError ? AppColors.error : AppColors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.wc_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    valor?.etiqueta ?? 'Seleccionar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: valor == null
                          ? AppColors.inactive
                          : AppColors.textPrimary,
                    ),
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
        if (hayError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              mensajeError,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Fecha de nacimiento: se muestra `dd/MM/yyyy` y se envía `YYYY-MM-DD`.
class _CampoFechaRegistro extends StatelessWidget {
  const _CampoFechaRegistro({
    required this.valor,
    required this.habilitado,
    required this.onTap,
    this.error,
  });

  final DateTime? valor;
  final bool habilitado;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final DateTime? fecha = valor;
    final String? mensajeError = error;
    final bool hayError = mensajeError != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Fecha de nacimiento',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: habilitado ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hayError ? AppColors.error : AppColors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.calendar_today_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fecha == null ? 'dd/mm/aaaa' : formatearFecha(fecha),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: fecha == null
                          ? AppColors.inactive
                          : AppColors.textPrimary,
                    ),
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
        if (hayError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              mensajeError,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Colores semánticos LOCALES de la fortaleza (no se crea otra paleta).
const Color _rojoInsegura = AppColors.error;
const Color _ambarMedia = Color(0xFFFBBF24);
const Color _verdeSegura = Color(0xFF34D399);

/// Barra de fortaleza con los tres estados reales (rojo / ámbar / verde).
///
/// Solo el estado verde significa que la contraseña cumple la política.
class _BarraFortaleza extends StatelessWidget {
  const _BarraFortaleza({required this.fortaleza});

  final PasswordStrength fortaleza;

  Color get _color {
    switch (fortaleza.nivel) {
      case NivelPassword.segura:
        return _verdeSegura;
      case NivelPassword.media:
        return _ambarMedia;
      case NivelPassword.insegura:
        return _rojoInsegura;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Fortaleza',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            Text(
              fortaleza.etiquetaNivel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fortaleza.progreso),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          builder: (BuildContext context, double valor, Widget? child) {
            final double avance = valor.clamp(0.0, 1.0);
            return Stack(
              children: <Widget>[
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: avance,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Checklist de requisitos que se actualiza mientras el cliente escribe.
class _ChecklistPassword extends StatelessWidget {
  const _ChecklistPassword({required this.fortaleza});

  final PasswordStrength fortaleza;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final RequisitoPassword requisito in fortaleza.requisitos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Icon(
                  requisito.cumple
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 14,
                  color: requisito.cumple ? _verdeSegura : AppColors.inactive,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    requisito.etiqueta,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: requisito.cumple
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Botón principal con el gradiente de acento de VANTER MEN.
///
/// Mientras el registro está en curso muestra "CREANDO CUENTA..." y bloquea el
/// toque, para evitar envíos duplicados.
class _BotonPrincipalRegistro extends StatelessWidget {
  const _BotonPrincipalRegistro({
    required this.label,
    required this.labelCargando,
    required this.onPressed,
    this.isLoading = false,
    this.habilitado = true,
  });

  final String label;
  final String labelCargando;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Solo cambia la apariencia: el toque sigue validando y avisando.
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final bool activo = habilitado && !isLoading;

    return Opacity(
      opacity: activo ? 1 : 0.65,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: isLoading
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              labelCargando,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: Colors.white,
                              ),
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

/// Confirmación de registro: solo nombre y correo (nunca ids internos).
class _DialogoCuentaCreada extends StatelessWidget {
  const _DialogoCuentaCreada({
    required this.nombre,
    required this.correo,
    required this.onIniciarSesion,
  });

  final String nombre;
  final String correo;
  final VoidCallback onIniciarSesion;

  @override
  Widget build(BuildContext context) {
    final String saludo = nombre.trim().isEmpty
        ? 'Ya puedes iniciar sesión con:'
        : '${nombre.trim()}, ya puedes iniciar sesión con:';

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'CUENTA CREADA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tu cuenta fue registrada correctamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              saludo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                correo,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 22),
            _BotonPrincipalRegistro(
              label: 'INICIAR SESIÓN',
              labelCargando: 'INICIAR SESIÓN',
              onPressed: onIniciarSesion,
            ),
          ],
        ),
      ),
    );
  }
}
