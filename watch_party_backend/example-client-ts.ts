// Example Watch Party Client (TypeScript)
// Can be used as reference for Flutter or web implementations

type MessageType = 'join' | 'sync' | 'set_media' | 'ping';

interface JoinPayload {
  room: string;
  peer: string;
  name: string;
  host: boolean;
}

interface SyncPayload {
  action: 'play' | 'pause' | 'seek';
  positionMs: number;
  isPlaying: boolean;
}

interface SetMediaPayload {
  mediaKey: string;
  currentUrl: string;
}

interface Message {
  type: MessageType;
  payload?: JoinPayload | SyncPayload | SetMediaPayload;
}

interface RoomState {
  mediaKey: string;
  currentUrl: string;
  isPlaying: boolean;
  positionMs: number;
  roster: Peer[];
}

interface Peer {
  peerId: string;
  name: string;
  isHost: boolean;
  joinedAt: number;
}

class WatchPartyClient {
  private ws: WebSocket | null = null;
  private roomId: string;
  private peerId: string;
  private name: string;
  private isHost: boolean;
  private endpoint: string;

  constructor(
    roomId: string,
    peerId: string,
    name: string,
    isHost: boolean,
    endpoint: string = 'ws://localhost:3000'
  ) {
    this.roomId = roomId.toUpperCase().trim();
    this.peerId = peerId;
    this.name = name;
    this.isHost = isHost;
    this.endpoint = endpoint;
  }

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        this.ws = new WebSocket(this.endpoint);

        this.ws.onopen = () => {
          console.log('Connected to Watch Party server');
          this.sendMessage({
            type: 'join',
            payload: {
              room: this.roomId,
              peer: this.peerId,
              name: this.name,
              host: this.isHost,
            },
          });
          resolve();
        };

        this.ws.onmessage = (event) => {
          const msg = JSON.parse(event.data);
          this.handleMessage(msg);
        };

        this.ws.onerror = (event) => {
          reject(new Error('WebSocket error'));
        };

        this.ws.onclose = () => {
          console.log('Disconnected from server');
        };
      } catch (err) {
        reject(err);
      }
    });
  }

  private sendMessage(msg: Message): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
    }
  }

  private handleMessage(msg: any): void {
    const { type, payload } = msg;

    switch (type) {
      case 'welcome':
        console.log('Welcome to room', payload.roomId);
        console.log('Your peer ID:', payload.peerId);
        console.log('You are:', payload.isHost ? 'HOST' : 'GUEST');
        console.log('Current state:', payload.state);
        break;

      case 'roster_updated':
        console.log('Roster updated:');
        (payload.roster as Peer[]).forEach((peer) => {
          console.log(`  - ${peer.name} ${peer.isHost ? '[HOST]' : ''}`);
        });
        break;

      case 'sync':
        console.log('Host sync:', {
          action: payload.action,
          position: payload.positionMs,
          playing: payload.isPlaying,
        });
        break;

      case 'media_changed':
        console.log('Media changed:', {
          mediaKey: payload.mediaKey,
          url: payload.currentUrl,
        });
        break;

      case 'host_changed':
        console.log('New host:', payload.hostId);
        break;

      case 'error':
        console.error('Server error:', payload.message);
        break;

      case 'pong':
        console.log('Pong received');
        break;
    }
  }

  // Host API
  public setMedia(mediaKey: string, currentUrl: string): void {
    if (!this.isHost) {
      console.warn('Only host can set media');
      return;
    }

    this.sendMessage({
      type: 'set_media',
      payload: { mediaKey, currentUrl },
    });
  }

  public sync(
    action: 'play' | 'pause' | 'seek',
    positionMs: number,
    isPlaying: boolean
  ): void {
    if (!this.isHost) {
      console.warn('Only host can sync');
      return;
    }

    this.sendMessage({
      type: 'sync',
      payload: { action, positionMs, isPlaying },
    });
  }

  public ping(): void {
    this.sendMessage({ type: 'ping' });
  }

  public close(): void {
    if (this.ws) {
      this.ws.close();
    }
  }

  public isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}

// Example usage
async function example() {
  const client = new WatchPartyClient('ABC123', 'peer-1', 'Juan', true);

  try {
    await client.connect();

    // Set the media being watched
    client.setMedia('movie:12345', 'https://example.com/movie.mp4');

    // Simulate playback control
    setTimeout(() => {
      client.sync('play', 0, true);
    }, 1000);

    setTimeout(() => {
      client.sync('pause', 45000, false);
    }, 5000);

    // Send ping every 20 seconds
    setInterval(() => {
      client.ping();
    }, 20000);
  } catch (err) {
    console.error('Connection error:', err);
  }
}

// Uncomment to run example
// example();

export { WatchPartyClient };
