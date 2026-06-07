# Watch Party Backend Setup

## Quick Start

### 1. Instalar el backend

```bash
cd watch_party_backend
npm install
```

### 2. Ejecutar en desarrollo

```bash
npm run dev
```

El servidor estará en `ws://localhost:3000`

### 3. Ejecutar en producción

```bash
npm start
```

## Configuración de la app Flutter

Por defecto, Flutter intenta conectarse a `ws://localhost:3000`. Para cambiar el endpoint:

**En video_player_screen.dart:**
```dart
final service = WatchPartyService(
  roomId: normalizedRoom,
  peerId: _partyPeerId,
  peerName: peer,
  isHost: isHost,
  endpoint: 'ws://tu-servidor.com:3000',  // Cambiar aquí
);
```

## Deploying a producción

### Opción 1: Railway.app (recomendado)

1. Conecta el repo a Railway
2. Selecciona la carpeta `watch_party_backend`
3. Configura PORT como variable de ambiente
4. Railway asigna un dominio públicamente accesible

### Opción 2: Docker

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY server.js .
EXPOSE 3000
CMD ["node", "server.js"]
```

```bash
docker build -t watch-party-backend .
docker run -p 3000:3000 -e PORT=3000 watch-party-backend
```

### Opción 3: VPS/Cloud

1. SSH en tu servidor
2. `git clone` el repo
3. `cd watch_party_backend && npm install`
4. Usa `pm2` para mantener el proceso:
   ```bash
   npm install -g pm2
   pm2 start server.js --name "watch-party"
   pm2 save
   ```
5. Configura Nginx como reverse proxy:
   ```nginx
   location /ws {
     proxy_pass http://localhost:3000;
     proxy_http_version 1.1;
     proxy_set_header Upgrade $http_upgrade;
     proxy_set_header Connection "upgrade";
   }
   ```

## Testing

### Health Check
```bash
curl http://localhost:3000/health
```

Respuesta:
```json
{
  "status": "ok",
  "timestamp": "2026-06-01T...",
  "roomsActive": 0
}
```

### Stats
```bash
curl http://localhost:3000/stats
```

Respuesta:
```json
{
  "totalRooms": 2,
  "totalPeers": 4,
  "rooms": [
    {
      "roomId": "ABC123",
      "peerCount": 2,
      "hostId": "peer-1",
      "createdAt": "2026-06-01T..."
    }
  ]
}
```

## Architecture

### Flujo de conexión

1. **Host** crea una sala con `isHost: true`
2. **Invitados** se unen con el código de la sala
3. El servidor le asigna al primer peer como host
4. Host sincroniza play/pause/seek
5. Invitados reciben events y reproducen

### Autoridad del host

- Solo el host puede enviar `sync` y `set_media`
- Los invitados que intenten sincronizar reciben error
- Si el host se desconecta, el primer invitado se promueve automáticamente

### Rooms lifecycle

- Rooms se crean al primer join
- Se limpian automáticamente si no hay actividad > 1 hora
- Se limpian si todos los peers se desconectan

## Troubleshooting

### "Connection refused"
- ¿El servidor está corriendo?
- ¿Está en el puerto correcto?
- ¿Firewall está abierto?

### "Not joined to a room"
- Asegúrate de enviar `join` como primer mensaje

### "Only host can sync"
- Solo el host puede sincronizar
- Un invitado que se promueve debe recargar la sala

### WebSocket URL en móviles
- Usa `ws://` para local dev
- Usa `wss://` (SSL) para producción
- El endpoint debe ser CORS-compatible

## Performance

- Soporta ~100 rooms simultáneas en un servidor t2.micro (AWS)
- Cada room usa ~2KB de memoria base
- Cada peer agrega ~1KB de memoria
- Heartbeat cada 30s, state updates cada 2s

## Security Notes

- No hay autenticación por defecto (agregar si es necesario)
- Los room IDs son públicos (código 6-char)
- No hay encriptación de señal (usar WSS en producción)
- Los peers pueden ver el nombre de todos en la sala
