# Contexto de Trabajo

## Proyecto

- Ruta local: `D:\zuper\zuper_app`
- Repo GitHub: `https://github.com/julianmcancelo/argonAPP`
- Backend Render: `https://argonapp.onrender.com`
- WebSocket usado en builds: `wss://argonapp.onrender.com`

## Estado actual real

- Hubo varias iteraciones de dashboard y navegacion.
- La base mas reciente dejada estable apunta nuevamente al `DashboardScreen` original desde `SplashScreen`.
- El acceso a `Ajustes` fue conectado desde ese dashboard.
- `Watch Party` fue simplificado para no pedir nombre en cada uso.
- El nombre de `Watch Party` se guarda en ajustes.

## Cambios ya hechos

### Navegacion y dashboard

- `lib/screens/splash_screen.dart`
  - vuelve a abrir `DashboardScreen`
- `lib/screens/dashboard_screen.dart`
  - el icono de ajustes abre `SettingsScreen`
- `lib/screens/main_navigation.dart`
  - existe, pero no es la ruta principal actual
- `lib/screens/home_dashboard_screen.dart`
  - existe como dashboard alternativo/simplificado

### Ajustes

- `lib/screens/settings_screen.dart`
  - bloque `Watch Party`
  - campo `Nombre para salas`
  - boton `Guardar nombre`

### Preferencias Watch Party

- `lib/services/watch_party_prefs.dart`
  - guarda el nombre con `SharedPreferences`

### Watch Party app

- `lib/screens/details_screen.dart`
  - dialogo de `Watch Party`
  - `Crear sala` genera codigo
  - `Unirse` pide solo codigo
  - se agrego un dialogo previo para elegir:
    - `Reproducir`
    - `Ver en grupo`

- `lib/services/watch_party_service.dart`
  - fix de conexion/join
  - espera `welcome`
  - timeout controlado

- `lib/screens/video_player_screen.dart`
  - sigue teniendo integracion de Watch Party en reproduccion
  - listener conectado antes del `connect()`

### Backend Watch Party

- `watch_party_backend/server.js`
  - backend WebSocket activo
  - extendido con eventos nuevos:
    - `set_ready`
    - `chat_message`
    - `start_playback`
  - estos cambios todavia no quedaron completamente integrados en la UI final

## Build actual

- APK release compilado correctamente:
  - `build/app/outputs/flutter-apk/app-release.apk`

- AAB:
  - quedo interrumpido varias veces por aborto manual
  - no tomarlo como build final cerrada hasta recompilarlo

## Version actual

- `pubspec.yaml`
- version dejada:
  - `1.3.1+7`

## Problemas abiertos

### 1. Dashboard

- El usuario indico que el dashboard "rarito" no le gusta.
- Quiere volver al dashboard que ya tenia antes.
- Hay multiples pantallas relacionadas:
  - `dashboard_screen.dart`
  - `home_dashboard_screen.dart`
  - `main_navigation.dart`
- La ruta principal actual vuelve a `dashboard_screen.dart`.

### 2. Watch Party

- Mejoro el flujo, pero todavia no esta terminado al nivel pedido.
- Falta implementar bien:
  - lobby previo real
  - participantes
  - chat
  - estado `listo`
  - boton `Iniciar` solo para anfitrion
  - arranque sincronizado luego del OK del host

### 3. Backend Render

- Si se quiere usar el lobby/chat/listo/iniciar de verdad, hay que redeployar Render porque `watch_party_backend/server.js` cambio.

## Lo que el usuario quiere exactamente

- Smart TV first
- dashboard anterior, no el simplificado/rarito
- `Ajustes`, `Mi cuenta`, `Perfiles` visibles y funcionales
- `Watch Party` sin molestar:
  - nombre/configuracion en ajustes
  - crear/unirse en detalle
  - idealmente lobby previo
  - no arrancar video directo

## Siguiente paso recomendado

1. Confirmar visualmente cual dashboard quiere dejar definitivo
2. Mantener una sola ruta de entrada desde `SplashScreen`
3. Terminar lobby de `Watch Party`
4. Recompilar:

```bash
flutter build apk --release --dart-define=WATCH_PARTY_WS_URL=wss://argonapp.onrender.com
flutter build appbundle --release --dart-define=WATCH_PARTY_WS_URL=wss://argonapp.onrender.com
```

## Comandos utiles

```bash
flutter build apk --release --dart-define=WATCH_PARTY_WS_URL=wss://argonapp.onrender.com
flutter build appbundle --release --dart-define=WATCH_PARTY_WS_URL=wss://argonapp.onrender.com
node --check watch_party_backend/server.js
```
