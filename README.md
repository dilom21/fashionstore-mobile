# VANTER MEN — App móvil de CLIENTES

Aplicación Flutter de VANTER MEN para el **cliente final** del e-commerce.
El personal interno (administradores, encargados, cajeros) utiliza el sistema
web administrativo, no esta app.

## Estructura

```
lib/
├── core/
│   ├── config/api_config.dart      # URL base y rutas del backend FastAPI
│   ├── storage/auth_storage.dart   # Token JWT (flutter_secure_storage)
│   └── theme/app_colors.dart       # Identidad visual VANTER MEN
├── features/
│   ├── autenticacion_seguridad/
│   │   ├── models/auth_models.dart
│   │   ├── pages/login/login_page.dart
│   │   └── services/auth_service.dart
│   └── inicio/
│       └── pages/
│           ├── inicio_page.dart
│           └── main_navigation_page.dart
└── main.dart
```

Flujo conceptual: `Page → Service → Backend FastAPI`.

## Estado actual

- Login real del CLIENTE contra `POST /auth/clientes/login`.
- Restauración de sesión con `GET /auth/me` al abrir la app.
- Validación de contexto: solo se permite `contexto == "cliente"`.
- Navegación inferior: Inicio, Catálogo, Vestidor, Carrito y Perfil.
- Catálogo, Vestidor, Carrito y Perfil son pantallas temporales.

## Ejecutar en desarrollo

La URL del backend se inyecta en tiempo de compilación:

### Emulador Android

`10.0.2.2` es el `localhost` del equipo anfitrión visto desde el emulador.

```
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Teléfono Android físico por USB

```
adb devices
adb reverse tcp:8000 tcp:8000
adb reverse --list
flutter run -d <DEVICE_ID> --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Con `adb reverse`, el teléfono alcanza `127.0.0.1:8000` y el tráfico se redirige
por ADB al FastAPI de la PC. **No se modifica nada en el código Dart.**

> HTTP local (cleartext) está permitido **solo en builds de debug** mediante
> `android/app/src/debug/res/xml/network_security_config.xml`. Producción
> mantiene HTTPS obligatorio.

## Validación

```
flutter pub get
flutter analyze
flutter test
```

