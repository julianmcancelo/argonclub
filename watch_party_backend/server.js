const express = require('express');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const PORT = process.env.PORT || 3000;
const HEARTBEAT_INTERVAL = 30000;
const ROOM_TIMEOUT = 3600000; // 1 hour
const STATE_SYNC_INTERVAL = 2000;

// Room state model
class Room {
  constructor(roomId) {
    this.roomId = roomId;
    this.hostId = null;
    this.peers = new Map(); // peerId -> { socket, name, joinedAt }
    this.readyPeers = new Set();
    this.chat = [];
    this.playbackStarted = false;
    this.mediaState = {
      mediaKey: '',
      currentUrl: '',
      isPlaying: false,
      positionMs: 0,
      lastUpdateMs: 0,
    };
    this.createdAt = Date.now();
    this.lastActivityAt = Date.now();
  }

  isValid() {
    return Date.now() - this.createdAt < ROOM_TIMEOUT;
  }

  broadcast(messageType, payload, excludePeerId = null) {
    const message = JSON.stringify({
      type: messageType,
      timestamp: Date.now(),
      payload,
    });

    for (const [peerId, peer] of this.peers.entries()) {
      if (excludePeerId && peerId === excludePeerId) continue;
      if (peer.socket.readyState === WebSocket.OPEN) {
        peer.socket.send(message);
      }
    }
  }

  getRosterSnapshot() {
    return Array.from(this.peers.entries()).map(([peerId, peer]) => ({
      peerId,
      name: peer.name,
      isHost: peerId === this.hostId,
      joinedAt: peer.joinedAt,
    }));
  }

  getStateSnapshot() {
    return {
      ...this.mediaState,
      roster: this.getRosterSnapshot(),
      readyPeerIds: Array.from(this.readyPeers),
      chat: this.chat.slice(-30),
      playbackStarted: this.playbackStarted,
    };
  }
}

const rooms = new Map(); // roomId -> Room
const pairingSessions = new Map(); // pairingCode -> { tvSocket, phoneSocket, phoneDevice }

// Cleanup invalid rooms
setInterval(() => {
  for (const [roomId, room] of rooms.entries()) {
    if (!room.isValid() || room.peers.size === 0) {
      console.log(`[CLEANUP] Removing room ${roomId}`);
      rooms.delete(roomId);
    }
  }
}, 60000);

// HTTP routes for health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    roomsActive: rooms.size,
  });
});

app.get('/stats', (req, res) => {
  const stats = {
    totalRooms: rooms.size,
    totalPeers: Array.from(rooms.values()).reduce((sum, r) => sum + r.peers.size, 0),
    rooms: Array.from(rooms.entries()).map(([roomId, room]) => ({
      roomId,
      peerCount: room.peers.size,
      hostId: room.hostId,
      createdAt: new Date(room.createdAt).toISOString(),
    })),
  };
  res.json(stats);
});

// WebSocket connection handler
wss.on('connection', (socket) => {
  let roomId = null;
  let peerId = null;
  let isHost = false;

  const logEvent = (event, data = {}) => {
    console.log(`[${roomId}] [${peerId}] ${event}`, data);
  };

  socket.on('message', (rawMessage) => {
    try {
      const message = JSON.parse(rawMessage.toString());
      const { type, payload } = message;

      if (!type) return;

      if (type === 'register_tv') {
        if (socket.pairingCode) {
          const previousSession = pairingSessions.get(socket.pairingCode);
          if (previousSession?.phoneSocket?.readyState === WebSocket.OPEN) {
            previousSession.phoneSocket.send(JSON.stringify({ type: 'tv_disconnected' }));
          }
          pairingSessions.delete(socket.pairingCode);
        }
        let code;
        do {
          code = Math.floor(1000 + Math.random() * 9000).toString();
        } while (pairingSessions.has(code));

        pairingSessions.set(code, { tvSocket: socket, phoneSocket: null });
        socket.pairingCode = code;
        socket.isTv = true;
        
        socket.send(JSON.stringify({
          type: 'tv_registered',
          payload: { code },
        }));
        console.log(`[PAIRING] TV registered with code: ${code}`);
        return;
      }

      if (type === 'pair_phone') {
        const targetCode = (payload?.code || '').toString().trim();
        const session = pairingSessions.get(targetCode);
        if (session) {
          const rawDevice = payload?.device || {};
          const phoneDevice = {
            name: (rawDevice.name || 'Argon Remote').toString().trim().substring(0, 40),
            platform: (rawDevice.platform || 'Móvil').toString().trim().substring(0, 24),
          };
          if (session.phoneSocket &&
              session.phoneSocket !== socket &&
              session.phoneSocket.readyState === WebSocket.OPEN) {
            session.phoneSocket.send(JSON.stringify({
              type: 'phone_disconnected',
              payload: { message: 'Otro teléfono tomó el control' },
            }));
            session.phoneSocket.close(1000, 'Replaced by another remote');
          }
          session.phoneSocket = socket;
          session.phoneDevice = phoneDevice;
          socket.pairingCode = targetCode;
          socket.isPhone = true;

          session.tvSocket.send(JSON.stringify({
            type: 'phone_paired',
            payload: { device: phoneDevice },
          }));

          socket.send(JSON.stringify({
            type: 'paired_to_tv',
            payload: { device: { name: 'Argon TV', platform: 'Web/Vidaa' } },
          }));
          console.log(`[PAIRING] Phone paired to TV code: ${targetCode}`);
        } else {
          socket.send(JSON.stringify({
            type: 'pair_error',
            payload: { message: 'Código inválido o TV no encontrada' },
          }));
        }
        return;
      }

      if (type === 'remote_key') {
        if (socket.pairingCode && socket.isPhone) {
          const session = pairingSessions.get(socket.pairingCode);
          if (session &&
              session.phoneSocket === socket &&
              session.tvSocket &&
              session.tvSocket.readyState === WebSocket.OPEN) {
            session.tvSocket.send(JSON.stringify({
              type: 'remote_key',
              payload: { key: payload.key },
            }));
          }
        }
        return;
      }

      if (type === 'remote_search') {
        if (socket.pairingCode && socket.isPhone) {
          const session = pairingSessions.get(socket.pairingCode);
          if (session &&
              session.phoneSocket === socket &&
              session.tvSocket &&
              session.tvSocket.readyState === WebSocket.OPEN) {
            session.tvSocket.send(JSON.stringify({
              type: 'remote_search',
              payload: { query: payload.query },
            }));
          }
        }
        return;
      }

      if (type === 'ping' && socket.pairingCode) {
        socket.send(JSON.stringify({
          type: 'pong',
          payload: { timestamp: Date.now(), serverTime: Date.now() },
        }));
        return;
      }

      // Initial connection message (must be first)
      if (type === 'join') {

        const { room, peer, name, host } = payload;
        if (!room || !peer || !name) {
          socket.send(JSON.stringify({
            type: 'error',
            payload: { message: 'Invalid join message' },
          }));
          return;
        }

        roomId = room.toUpperCase().trim();
        peerId = peer;
        isHost = host === true;

        // Create room if doesn't exist
        if (!rooms.has(roomId)) {
          rooms.set(roomId, new Room(roomId));
          logEvent('ROOM_CREATED');
        }

        const currentRoom = rooms.get(roomId);
        if (currentRoom.hostId === null && isHost) {
          currentRoom.hostId = peerId;
          logEvent('BECAME_HOST');
        }

        // Reject if join as host but room already has host (unless it's the same)
        if (isHost && currentRoom.hostId !== peerId && currentRoom.hostId !== null) {
          socket.send(JSON.stringify({
            type: 'error',
            payload: { message: 'Room already has a host' },
          }));
          return;
        }

        // Add peer
        currentRoom.peers.set(peerId, {
          socket,
          name: name.substring(0, 50),
          joinedAt: Date.now(),
        });
        currentRoom.readyPeers.delete(peerId);

        logEvent('PEER_JOINED', { name, host: isHost, rosterSize: currentRoom.peers.size });

        // Send welcome + state
        socket.send(JSON.stringify({
          type: 'welcome',
          payload: {
            roomId,
            peerId,
            isHost,
            state: currentRoom.getStateSnapshot(),
          },
        }));

        // Broadcast updated roster
        currentRoom.broadcast('roster_updated', {
          roster: currentRoom.getRosterSnapshot(),
          readyPeerIds: Array.from(currentRoom.readyPeers),
        });

        return;
      }

      // All other messages require prior join
      if (!roomId || !peerId) {
        socket.send(JSON.stringify({
          type: 'error',
          payload: { message: 'Not joined to a room' },
        }));
        return;
      }

      const currentRoom = rooms.get(roomId);
      if (!currentRoom) {
        socket.send(JSON.stringify({
          type: 'error',
          payload: { message: 'Room not found' },
        }));
        return;
      }

      currentRoom.lastActivityAt = Date.now();

      if (type === 'set_ready') {
        const ready = payload?.ready === true;
        if (ready) {
          currentRoom.readyPeers.add(peerId);
        } else {
          currentRoom.readyPeers.delete(peerId);
        }
        currentRoom.broadcast('room_state', {
          roster: currentRoom.getRosterSnapshot(),
          readyPeerIds: Array.from(currentRoom.readyPeers),
          playbackStarted: currentRoom.playbackStarted,
        });
        return;
      }

      if (type === 'chat_message') {
        const text = (payload?.text || '').toString().trim().substring(0, 250);
        if (!text) return;
        const entry = {
          peerId,
          name: currentRoom.peers.get(peerId)?.name || 'Invitado',
          text,
          at: Date.now(),
        };
        currentRoom.chat.push(entry);
        currentRoom.chat = currentRoom.chat.slice(-30);
        currentRoom.broadcast('chat_message', entry);
        return;
      }

      // Host-only messages
      if (isHost) {
        if (type === 'start_playback') {
          currentRoom.playbackStarted = true;
          currentRoom.broadcast('playback_started', {
            roomId,
            mediaKey: currentRoom.mediaState.mediaKey,
            currentUrl: currentRoom.mediaState.currentUrl,
          });
          return;
        }

        if (type === 'set_media') {
          const { mediaKey, currentUrl } = payload;
          currentRoom.mediaState.mediaKey = mediaKey || '';
          currentRoom.mediaState.currentUrl = currentUrl || '';
          currentRoom.mediaState.positionMs = 0;
          currentRoom.mediaState.isPlaying = false;
          currentRoom.mediaState.lastUpdateMs = Date.now();
          currentRoom.playbackStarted = false;

          logEvent('MEDIA_CHANGED', { mediaKey });

          currentRoom.broadcast('media_changed', {
            mediaKey: currentRoom.mediaState.mediaKey,
            currentUrl: currentRoom.mediaState.currentUrl,
          });
          return;
        }

        if (type === 'sync') {
          const { action, positionMs, isPlaying } = payload;
          currentRoom.mediaState.isPlaying = isPlaying === true;
          currentRoom.mediaState.positionMs = Math.max(0, positionMs || 0);
          currentRoom.mediaState.lastUpdateMs = Date.now();

          logEvent('SYNC', { action, pos: positionMs, playing: isPlaying });

          currentRoom.broadcast('sync', {
            action: action || (isPlaying ? 'play' : 'pause'),
            positionMs: currentRoom.mediaState.positionMs,
            isPlaying: currentRoom.mediaState.isPlaying,
            sentAtMs: currentRoom.mediaState.lastUpdateMs,
          });
          return;
        }
      }

      // Peer-initiated sync (not from host)
      if (type === 'sync' && !isHost) {
        logEvent('SYNC_FROM_GUEST', { rejected: true });
        socket.send(JSON.stringify({
          type: 'error',
          payload: { message: 'Only host can sync' },
        }));
        return;
      }

      // Heartbeat/ping
      if (type === 'ping') {
        socket.send(JSON.stringify({
          type: 'pong',
          payload: {
            timestamp: Date.now(),
            serverTime: Date.now(),
          },
        }));
        return;
      }
    } catch (error) {
      console.error(`[${roomId}] [${peerId}] Parse error:`, error.message);
      socket.send(JSON.stringify({
        type: 'error',
        payload: { message: 'Invalid message format' },
      }));
    }
  });

  socket.on('close', () => {
    if (socket.pairingCode) {
      const session = pairingSessions.get(socket.pairingCode);
      if (session) {
        if (socket.isTv) {
          if (session.phoneSocket && session.phoneSocket.readyState === WebSocket.OPEN) {
            session.phoneSocket.send(JSON.stringify({ type: 'tv_disconnected' }));
          }
          pairingSessions.delete(socket.pairingCode);
          console.log(`[PAIRING] TV disconnected, deleted session code: ${socket.pairingCode}`);
        } else if (socket.isPhone) {
          if (session.phoneSocket === socket) {
            if (session.tvSocket && session.tvSocket.readyState === WebSocket.OPEN) {
              session.tvSocket.send(JSON.stringify({ type: 'phone_disconnected' }));
            }
            session.phoneSocket = null;
            session.phoneDevice = null;
          }
          console.log(`[PAIRING] Phone disconnected from session code: ${socket.pairingCode}`);
        }
      }
    }

    if (roomId && peerId) {
      const room = rooms.get(roomId);

      if (room) {
        room.peers.delete(peerId);
        room.readyPeers.delete(peerId);
        logEvent('PEER_LEFT', { rosterSize: room.peers.size });

        // Broadcast updated roster
        room.broadcast('roster_updated', {
          roster: room.getRosterSnapshot(),
          readyPeerIds: Array.from(room.readyPeers),
        });

        // If host left, promote first remaining peer or delete room
        if (isHost && room.peers.size > 0) {
          const newHostId = Array.from(room.peers.keys())[0];
          room.hostId = newHostId;
          room.broadcast('host_changed', { hostId: newHostId });
          logEvent('HOST_CHANGED', { newHost: newHostId });
        }
      }
    }
  });

  socket.on('error', (error) => {
    console.error(`[${roomId}] [${peerId}] Socket error:`, error.message);
  });

  // Send pong in response to client pings
  socket.isAlive = true;
  socket.on('pong', () => {
    socket.isAlive = true;
  });
});

// Heartbeat to detect stale connections
const interval = setInterval(() => {
  wss.clients.forEach((socket) => {
    if (!socket.isAlive) {
      socket.terminate();
      return;
    }
    socket.isAlive = false;
    socket.ping();
  });
}, HEARTBEAT_INTERVAL);

server.on('close', () => {
  clearInterval(interval);
});

// Start server
server.listen(PORT, () => {
  console.log(`Argon realtime backend running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Stats: http://localhost:${PORT}/stats`);
});
