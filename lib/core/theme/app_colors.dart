import 'package:flutter/material.dart';

/// Identidad visual de VANTER MEN.
///
/// Paleta oscura premium (azul/negro muy oscuro) con acentos lila/magenta.
/// Es un elemento transversal de la aplicación: centraliza los colores para
/// mantener coherencia entre todas las pantallas.
class AppColors {
  /// Clase de solo constantes: no debe instanciarse.
  const AppColors._();

  /// Fondo principal (azul/negro muy oscuro).
  static const Color background = Color(0xFF07070D);

  /// Superficies elevadas (tarjetas, barra inferior).
  static const Color surface = Color(0xFF12121F);

  /// Superficie alterna para campos de texto.
  static const Color surfaceVariant = Color(0xFF1A1A29);

  /// Bordes sutiles.
  static const Color border = Color(0xFF2A2A3D);

  /// Acento principal (violeta).
  static const Color primary = Color(0xFF8B5CF6);

  /// Acento secundario (magenta).
  static const Color secondary = Color(0xFFD946EF);

  /// Texto principal.
  static const Color textPrimary = Color(0xFFF5F5FA);

  /// Texto secundario, descripciones y placeholders.
  static const Color textMuted = Color(0xFF9A9AB2);

  /// Elementos inactivos (iconos de navegación sin seleccionar).
  static const Color inactive = Color(0xFF7C7C93);

  /// Errores y validaciones.
  static const Color error = Color(0xFFFF5C7A);

  /// Gradiente de acento para botones y elementos destacados.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Gradiente de fondo sutil para las pantallas.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0C0C19), background],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
