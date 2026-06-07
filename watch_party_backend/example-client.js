// Example Watch Party Client (Node.js)
// Demonstrates how to interact with the Watch Party backend

const WebSocket = require('ws');
const readline = require('readline');

const WS_URL = process.env.WS_URL || 'ws://localhost:3000';

class WatchPartyClient {
  constructor(roomId, peerId, name, isHost = false) {
    this.roomId = roomId;
    this.peerId = peerId;
    this.name = name;
    this.isHost = isHost;
    this.ws = null;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      try {
        this.ws = new WebSocket(WS_URL);

        this.ws.on('open', () => {
          console.log('✓ Connected to server');

          // Send join message
          this.send({
            type: 'join',
            payload: {
              room: this.roomId.toUpperCase(),
              peer: this.peerId,
              name: this.name,
              host: this.isHost,
            },
          });

          resolve();
        });

        this.ws.on('message', (data) => {
          this.handleMessage(JSON.parse(data));
        });

        this.ws.on('error', (err) => {
          console.error('✗ WebSocket error:', err.message);
          reject(err);
        });

        this.ws.on('close', () => {
          console.log('✗ Connection closed');
        });
      } catch (err) {
        reject(err);
      }
    });
  }

  send(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  handleMessage(msg) {
    const { type, payload, timestamp } = msg;

    if (type === 'welcome') {
      console.log('\n--- Welcome to room ---');
      console.log(`Room: ${payload.roomId}`);
      console.log(`Your ID: ${payload.peerId}`);
      console.log(`You are: ${payload.isHost ? 'HOST' : 'GUEST'}`);
      console.log(`Current state:`, payload.state);
      console.log('');
    }

    if (type === 'roster_updated') {
      console.log('\n--- Roster updated ---');
      const roster = payload.roster || [];
      roster.forEach((peer) => {
        const badge = peer.isHost ? '[HOST]' : '[GUEST]';
        console.log(`  ${badge} ${peer.name}`);
      });
      console.log('');
    }

    if (type === 'sync') {
      console.log(`\n[SYNC] Host action: ${payload.action}`);
      console.log(`       Position: ${payload.positionMs}ms`);
      console.log(`       Playing: ${payload.isPlaying}`);
      console.log('');
    }

    if (type === 'media_changed') {
      console.log(`\n[MEDIA] Changed to: ${payload.mediaKey}`);
      console.log(`        URL: ${payload.currentUrl}`);
      console.log('');
    }

    if (type === 'host_changed') {
      console.log(`\n[HOST] Changed to: ${payload.hostId}`);
      console.log('');
    }

    if (type === 'error') {
      console.error(`✗ Error: ${payload.message}`);
    }

    if (type === 'pong') {
      console.log('pong');
    }
  }

  // Host actions
  setMedia(mediaKey, url) {
    if (!this.isHost) {
      console.warn('Only host can set media');
      return;
    }
    this.send({
      type: 'set_media',
      payload: { mediaKey, currentUrl: url },
    });
    console.log(`→ Set media: ${mediaKey}`);
  }

  sync(action, positionMs, isPlaying) {
    if (!this.isHost) {
      console.warn('Only host can sync');
      return;
    }
    this.send({
      type: 'sync',
      payload: {
        action, // 'play' | 'pause' | 'seek'
        positionMs,
        isPlaying,
      },
    });
    console.log(`→ Sync: ${action} @ ${positionMs}ms (playing: ${isPlaying})`);
  }

  ping() {
    this.send({ type: 'ping' });
  }

  close() {
    if (this.ws) {
      this.ws.close();
    }
  }
}

// Interactive CLI
async function main() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const question = (prompt) =>
    new Promise((resolve) => rl.question(prompt, resolve));

  console.log('=== Watch Party Client ===\n');

  const roomId = await question('Room ID (e.g., AB12CD): ');
  const peerId = await question('Peer ID (e.g., peer-1): ');
  const name = await question('Your name: ');
  const isHostStr = await question('Are you host? (y/n): ');
  const isHost = isHostStr.toLowerCase() === 'y';

  console.log(`\nConnecting to ${WS_URL}...`);

  const client = new WatchPartyClient(roomId, peerId, name, isHost);

  try {
    await client.connect();

    console.log('Commands:');
    if (isHost) {
      console.log('  play <pos>       - Play from position (ms)');
      console.log('  pause <pos>      - Pause at position (ms)');
      console.log('  media <key> <url> - Set media');
      console.log('  ping             - Send ping');
    } else {
      console.log('  ping             - Send ping');
    }
    console.log('  exit             - Exit\n');

    while (true) {
      const input = await question('> ');
      const [cmd, ...args] = input.trim().split(' ');

      if (cmd === 'exit') {
        client.close();
        process.exit(0);
      }

      if (cmd === 'play' && isHost) {
        const pos = parseInt(args[0]) || 0;
        client.sync('play', pos, true);
      } else if (cmd === 'pause' && isHost) {
        const pos = parseInt(args[0]) || 0;
        client.sync('pause', pos, false);
      } else if (cmd === 'media' && isHost) {
        const key = args[0];
        const url = args.slice(1).join(' ');
        if (key && url) {
          client.setMedia(key, url);
        }
      } else if (cmd === 'ping') {
        client.ping();
      } else {
        console.log('Unknown command');
      }
    }
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  }
}

main();
