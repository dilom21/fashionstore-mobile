// Política de contraseña de CLIENTES de VANTER MEN.
//
// Es la MISMA regla que valida el backend en `POST /auth/clientes/registro` y
// replica exactamente el util del cliente Web
// (`auth/utils/password-strength.util.ts`):
//
//  1. longitud entre 8 y 128 caracteres;
//  2. al menos una letra minúscula a-z;
//  3. al menos una letra MAYÚSCULA A-Z;
//  4. al menos un número 0-9;
//  5. al menos un carácter especial: cualquier carácter que NO sea A-Z, a-z,
//     0-9 ni espacio. El ESPACIO no cuenta como carácter especial.
//
// No se llama al backend para evaluar la contraseña: solo el servidor es la
// autoridad final.

/// Longitud mínima exigida.
const int passwordMinLongitud = 8;

/// Longitud máxima exigida.
const int passwordMaxLongitud = 128;

/// Nivel visible de fortaleza (única condición válida: 5/5 requisitos).
enum NivelPassword { insegura, media, segura }

/// Clave de cada requisito del checklist.
enum ClaveRequisitoPassword {
  longitud,
  mayuscula,
  minuscula,
  numero,
  especial,
}

/// Resultado de evaluar una contraseña contra la política real.
class PasswordStrength {
  const PasswordStrength._({
    required this.longitud,
    required this.minuscula,
    required this.mayuscula,
    required this.numero,
    required this.especial,
    required this.cantidadCumplida,
    required this.nivel,
  });

  /// Entre 8 y 128 caracteres.
  final bool longitud;

  /// Tiene al menos una minúscula.
  final bool minuscula;

  /// Tiene al menos una mayúscula.
  final bool mayuscula;

  /// Tiene al menos un número.
  final bool numero;

  /// Tiene al menos un carácter especial (el espacio no cuenta).
  final bool especial;

  /// Requisitos cumplidos (0 a 5).
  final int cantidadCumplida;

  /// Nivel derivado de [cantidadCumplida].
  final NivelPassword nivel;

  /// `true` solo cuando cumple los 5 requisitos: habilita el envío.
  bool get valida => cantidadCumplida == 5;

  /// Progreso de la barra entre 0.0 y 1.0.
  double get progreso =>
      cantidadCumplida / ClaveRequisitoPassword.values.length;

  /// Texto del nivel para la barra.
  String get etiquetaNivel {
    switch (nivel) {
      case NivelPassword.segura:
        return 'SEGURA';
      case NivelPassword.media:
        return 'NIVEL MEDIO';
      case NivelPassword.insegura:
        return 'INSEGURA';
    }
  }

  /// Checklist en el mismo orden en que se explica al cliente.
  List<RequisitoPassword> get requisitos => <RequisitoPassword>[
    RequisitoPassword(
      clave: ClaveRequisitoPassword.longitud,
      etiqueta: '8 a 128 caracteres',
      cumple: longitud,
    ),
    RequisitoPassword(
      clave: ClaveRequisitoPassword.mayuscula,
      etiqueta: 'Una letra mayúscula',
      cumple: mayuscula,
    ),
    RequisitoPassword(
      clave: ClaveRequisitoPassword.minuscula,
      etiqueta: 'Una letra minúscula',
      cumple: minuscula,
    ),
    RequisitoPassword(
      clave: ClaveRequisitoPassword.numero,
      etiqueta: 'Un número',
      cumple: numero,
    ),
    RequisitoPassword(
      clave: ClaveRequisitoPassword.especial,
      etiqueta: 'Un carácter especial',
      cumple: especial,
    ),
  ];

  /// Evalúa la contraseña sin llamar al backend.
  ///
  /// 5 requisitos: segura (verde). 3 o 4: nivel medio (ámbar). 0 a 2: insegura
  /// (rojo), igual que el cliente Web.
  static PasswordStrength evaluar(String password) {
    final bool cumpleLongitud =
        password.length >= passwordMinLongitud &&
        password.length <= passwordMaxLongitud;
    final bool cumpleMinuscula = _reMinuscula.hasMatch(password);
    final bool cumpleMayuscula = _reMayuscula.hasMatch(password);
    final bool cumpleNumero = _reNumero.hasMatch(password);
    final bool cumpleEspecial = _reEspecial.hasMatch(password);

    final int cantidad = <bool>[
      cumpleLongitud,
      cumpleMinuscula,
      cumpleMayuscula,
      cumpleNumero,
      cumpleEspecial,
    ].where((bool cumple) => cumple).length;

    final NivelPassword nivel;
    if (cantidad == 5) {
      nivel = NivelPassword.segura;
    } else if (cantidad >= 3) {
      nivel = NivelPassword.media;
    } else {
      nivel = NivelPassword.insegura;
    }

    return PasswordStrength._(
      longitud: cumpleLongitud,
      minuscula: cumpleMinuscula,
      mayuscula: cumpleMayuscula,
      numero: cumpleNumero,
      especial: cumpleEspecial,
      cantidadCumplida: cantidad,
      nivel: nivel,
    );
  }
}

/// Fila del checklist visible bajo la barra de fortaleza.
class RequisitoPassword {
  const RequisitoPassword({
    required this.clave,
    required this.etiqueta,
    required this.cumple,
  });

  final ClaveRequisitoPassword clave;
  final String etiqueta;
  final bool cumple;
}

final RegExp _reMinuscula = RegExp(r'[a-z]');
final RegExp _reMayuscula = RegExp(r'[A-Z]');
final RegExp _reNumero = RegExp(r'[0-9]');

/// Especial = todo lo que no sea A-Z, a-z, 0-9 ni espacio (el espacio NO
/// cuenta como carácter especial).
final RegExp _reEspecial = RegExp(r'[^A-Za-z0-9\s]');
