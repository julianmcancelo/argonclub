# Zuper App

Zuper App es una app Flutter orientada a Android TV y Smart TV, con foco en:

- catalogo de peliculas y series optimizado para control remoto
- dashboard estilo streaming con navegacion TV-first
- reproduccion mejorada para TV
- Watch Party para ver contenido sincronizado
- backend WebSocket listo para Railway

## Estructura

- `lib/`: aplicacion Flutter
- `watch_party_backend/`: backend Node.js para salas Watch Party
- `android/`: proyecto Android
- `assets/`: imagenes y recursos

## Requisitos

- Flutter estable
- Android SDK
- Node.js 18+ para `watch_party_backend`

## Ejecutar la app

```bash
flutter pub get
flutter run
```

## Compilar APK release

```bash
flutter build apk --release
```

## Compilar AAB release

```bash
flutter build appbundle --release
```

## Backend Watch Party

Instalar dependencias:

```bash
cd watch_party_backend
npm install
```

Ejecutar local:

```bash
npm start
```

La app puede apuntar al backend con:

```bash
flutter build apk --release --dart-define=WATCH_PARTY_WS_URL=wss://TU-BACKEND.up.railway.app
```

## Deploy en Railway

La carpeta `watch_party_backend/` ya incluye `railway.json`.

Pasos:

1. Crear proyecto nuevo en Railway.
2. Subir este repo a GitHub.
3. Conectar el repo en Railway.
4. Configurar el servicio usando `watch_party_backend/` como raiz si hace falta.
5. Usar la URL publica resultante como `WATCH_PARTY_WS_URL`.

## Estado actual

- interfaz priorizada para Smart TV
- catalogo compacto para ver mas contenido por fila
- soporte inicial de Watch Party
- APK y AAB release generables desde Flutter

## Notas

- No se incluyen builds compiladas ni archivos sensibles en git.
- Para Google Play, compilar con firma release real.
