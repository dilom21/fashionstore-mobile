/// Resultado que el motor local del vestidor devuelve a quien lo abrió.
///
/// El motor (`CamaraVestidorPage`) sigue siendo 100% local: NO hace requests
/// HTTP. Solo informa cómo terminó la prueba para que la capa de flujo cierre
/// el ciclo de negocio (sesión/prueba).
enum VestidorMotorResultado {
  /// El cliente confirmó la prueba ("LISTO").
  completada,

  /// El cliente volvió/canceló (botón VOLVER, Back del sistema o AppBar).
  cancelada,

  /// La prueba terminó por un error controlado del motor.
  error,
}
