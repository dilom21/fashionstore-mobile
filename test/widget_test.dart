// Test smoke de la primera funcionalidad real: al abrir la app se comprueba la
// sesión guardada y, sin token, se muestra la pantalla de login.

import 'package:flutter_test/flutter_test.dart';

import 'package:fashionstore_mobile/main.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const FashionStoreApp());
  // La restauración de sesión resuelve de inmediato porque no hay
  // API_BASE_URL configurada en el entorno de pruebas (y no hay token).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('Muestra el login cuando no hay sesión guardada', (tester) async {
    await _pumpApp(tester);

    expect(find.text('VANTER MEN'), findsWidgets);
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
  });

  testWidgets('Valida el formulario antes de enviar', (tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('INICIAR SESIÓN'));
    await tester.pump();
    await tester.tap(find.text('INICIAR SESIÓN'));
    await tester.pump();

    expect(find.text('Ingresa tu correo electrónico.'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña.'), findsOneWidget);
  });
}
