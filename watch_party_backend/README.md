# Watch Party Backend

Servidor WebSocket para sincronizacion de visualizacion compartida.

## Requisitos

- Node.js 18 o superior

## Instalacion

```bash
npm install
```

## Ejecucion local

```bash
# Produccion
npm start

# Desarrollo con auto-reload
npm run dev
```

## Render

Este backend ya queda listo para Render.

### Opcion A: desde el Dashboard

1. Crear un nuevo `Web Service`.
2. Conectar el repositorio de GitHub.
3. Elegir estos valores:
   - Root Directory: `watch_party_backend`
   - Build Command: `npm install`
   - Start Command: `npm start`
4. En `Health Check Path`, usar:

```text
/health
```

5. Elegir el plan `Free`.

Render expone `PORT` automaticamente.

Cuando termine el deploy, la URL WebSocket sera:

```text
wss://TU-SERVICIO.onrender.com
```

### Opcion B: con Blueprint

En la raiz del repo se puede usar `render.yaml` para que Render tome la configuracion automaticamente.

## Flutter app

Para compilar la app apuntando al backend publicado:

```bash
flutter build apk --release --dart-define=WATCH_PARTY_WS_URL=wss://TU-SERVICIO.onrender.com
```

Si no se pasa `WATCH_PARTY_WS_URL`, la app usa `ws://10.0.2.2:3000` para pruebas con emulador Android.

## Endpoints HTTP

- `GET /health`: estado del servidor
- `GET /stats`: estadisticas de salas activas

## WebSocket Protocol

### Unirse a una sala

```json
{
  "type": "join",
  "payload": {
    "room": "AB12CD",
    "peer": "unique-peer-id",
    "name": "Juan",
    "host": true
  }
}
```

### Host: cambiar contenido

```json
{
  "type": "set_media",
  "payload": {
    "mediaKey": "movie123",
    "currentUrl": "https://example.com/video.mp4"
  }
}
```

### Host: sincronizar

```json
{
  "type": "sync",
  "payload": {
    "action": "play|pause|seek",
    "positionMs": 45000,
    "isPlaying": true
  }
}
```

## Caracteristicas

- multi-room
- host authority
- sincronizacion play, pause y seek
- roster de participantes
- limpieza automatica de salas
- health check para deploy
