import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/watch_party_service.dart';
import 'video_player_screen.dart';

class WatchPartyLobbyScreen extends StatefulWidget {
  final WatchPartySession session;
  final String videoUrl;
  final bool isDirect;
  final Map<String, String> headers;
  final List<Map<String, dynamic>> serverQueue;
  final List<dynamic>? episodesList;
  final int? currentEpisodeIndex;
  final String mediaTitle;
  final String mediaType;
  final String mediaId;
  final String mediaPosterUrl;
  final String playbackKey;
  final int startPositionSeconds;

  const WatchPartyLobbyScreen({
    super.key,
    required this.session,
    required this.videoUrl,
    required this.isDirect,
    required this.headers,
    required this.serverQueue,
    required this.mediaTitle,
    required this.mediaType,
    required this.mediaId,
    required this.mediaPosterUrl,
    required this.playbackKey,
    required this.startPositionSeconds,
    this.episodesList,
    this.currentEpisodeIndex,
  });

  @override
  State<WatchPartyLobbyScreen> createState() => _WatchPartyLobbyScreenState();
}

class _WatchPartyLobbyScreenState extends State<WatchPartyLobbyScreen> {
  static const Color _bg = Color(0xFF060606);
  static const Color _surface = Color(0xCC17171A);
  static const Color _surfaceSoft = Color(0xB3131316);
  static const Color _line = Color(0x22FFFFFF);
  static const Color _lineStrong = Color(0x44FFFFFF);
  static const Color _ink = Color(0xFFF4F1EA);
  static const Color _inkMuted = Color(0xFFD2CDC4);
  static const Color _muted = Color(0xFF8E877D);
  static const Color _crimson = Color(0xFFE63946);
  static const Color _fire = Color(0xFFF97316);
  WatchPartyService? _service;
  StreamSubscription<WatchPartyEvent>? _sub;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _chat = [];
  final Set<String> _readyPeerIds = <String>{};
  final List<Map<String, dynamic>> _roster = [];
  bool _ready = false;
  bool _connecting = true;
  bool _starting = false;
  bool _navigated = false;
  String _status = 'Conectando sala...';
  String _peerId = '';
  late String _currentVideoUrl;
  late String _currentMediaTitle;
  late String _currentMediaType;
  late String _currentMediaId;
  late String _currentPosterUrl;
  late String _currentPlaybackKey;
  late bool _currentIsDirect;
  late List<Map<String, dynamic>> _currentServerQueue;
  late Map<String, String> _currentHeaders;

  @override
  void initState() {
    super.initState();
    _currentVideoUrl = widget.videoUrl;
    _currentMediaTitle = widget.mediaTitle;
    _currentMediaType = widget.mediaType;
    _currentMediaId = widget.mediaId;
    _currentPosterUrl = widget.mediaPosterUrl;
    _currentPlaybackKey = widget.playbackKey;
    _currentIsDirect = widget.isDirect;
    _currentServerQueue = List<Map<String, dynamic>>.from(widget.serverQueue);
    _currentHeaders = Map<String, String>.from(widget.headers);
    _connect();
  }

  Future<void> _connect() async {
    try {
      final service = WatchPartyService(
        roomId: widget.session.roomId,
        peerId: '${DateTime.now().millisecondsSinceEpoch}-${widget.session.peerName}',
        peerName: widget.session.peerName,
        isHost: widget.session.isHost,
      );
      _sub = service.events.listen(_onEvent);
      await service.connect();
      if (widget.session.isHost && widget.videoUrl.isNotEmpty) {
        service.setMedia(
          mediaKey: '${widget.mediaType}:${widget.mediaId}',
          currentUrl: widget.videoUrl,
        );
      }
      setState(() {
        _service = service;
        _connecting = false;
        _status = widget.session.isHost
            ? 'Sala creada. Esperando participantes.'
            : 'Sala conectada. Esperando inicio del anfitrion.';
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _status = 'No se pudo conectar: $e';
      });
    }
  }

  void _onEvent(WatchPartyEvent event) {
    if (!mounted) return;
    if (event.type == 'welcome') {
      final payload = event.payload;
      _peerId = payload['peerId']?.toString() ?? _peerId;
      final state = Map<String, dynamic>.from(payload['state'] ?? {});
      _syncMediaFromState(state);
      final roster = (state['roster'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)).toList();
      final ready = (state['readyPeerIds'] as List? ?? const []).map((e) => e.toString()).toSet();
      final chat = (state['chat'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        _roster
          ..clear()
          ..addAll(roster);
        _readyPeerIds
          ..clear()
          ..addAll(ready);
        _chat
          ..clear()
          ..addAll(chat);
        _ready = _peerId.isNotEmpty && _readyPeerIds.contains(_peerId);
      });
      if (state['playbackStarted'] == true) {
        _openPlayer();
      }
      return;
    }
    if (event.type == 'roster_updated' || event.type == 'room_state') {
      _syncMediaFromState(event.payload);
      final roster = (event.payload['roster'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)).toList();
      final ready = (event.payload['readyPeerIds'] as List? ?? const []).map((e) => e.toString()).toSet();
      setState(() {
        _roster
          ..clear()
          ..addAll(roster);
        _readyPeerIds
          ..clear()
          ..addAll(ready);
        _ready = _peerId.isNotEmpty && _readyPeerIds.contains(_peerId);
      });
      if (event.payload['playbackStarted'] == true) {
        _openPlayer();
      }
      return;
    }
    if (event.type == 'chat_message') {
      setState(() {
        _chat.add(Map<String, dynamic>.from(event.payload));
      });
      return;
    }
    if (event.type == 'playback_started') {
      _openPlayer();
      return;
    }
    if (event.type == 'error') {
      setState(() {
        _status = event.payload['message']?.toString() ?? 'Error de sala';
      });
    }
  }

  Future<void> _toggleReady() async {
    final next = !_ready;
    _service?.setReady(next);
    setState(() {
      _ready = next;
      if (_peerId.isNotEmpty) {
        if (next) {
          _readyPeerIds.add(_peerId);
        } else {
          _readyPeerIds.remove(_peerId);
        }
      }
    });
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _service?.sendChatMessage(text);
    _chatController.clear();
  }

  Future<void> _hostStart() async {
    if (_starting) return;
    setState(() => _starting = true);
    _service?.startPlayback();
    await Future.delayed(const Duration(milliseconds: 250));
    _openPlayer();
  }

  Future<void> _copyRoomCode() async {
    await Clipboard.setData(
      ClipboardData(text: widget.session.normalizedRoomId),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Codigo de sala copiado.')),
    );
  }

  Future<void> _leaveLobby() async {
    await _sub?.cancel();
    await _service?.dispose();
    _service = null;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openPlayer() async {
    if (_navigated || !mounted) return;
    if (_currentVideoUrl.isEmpty) {
      setState(() {
        _status = 'La sala todavia no publico el contenido. Esperando al anfitrion.';
      });
      return;
    }
    _navigated = true;
    await _sub?.cancel();
    await _service?.dispose();
    _service = null;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: _currentVideoUrl,
          isDirect: _currentIsDirect,
          headers: _currentHeaders,
          serverQueue: _currentServerQueue,
          episodesList: widget.episodesList,
          currentEpisodeIndex: widget.currentEpisodeIndex,
          mediaTitle: _currentMediaTitle,
          mediaType: _currentMediaType,
          mediaId: _currentMediaId,
          mediaPosterUrl: _currentPosterUrl,
          playbackKey: _currentPlaybackKey,
          startPositionSeconds: widget.startPositionSeconds,
          initialWatchPartySession: widget.session,
        ),
      ),
    );
  }

  void _syncMediaFromState(Map<String, dynamic> state) {
    final currentUrl = (state['currentUrl'] ?? '').toString().trim();
    if (currentUrl.isEmpty) return;
    _currentVideoUrl = currentUrl;
    _currentIsDirect = currentUrl.contains('.m3u8') || currentUrl.contains('.mp4');
    _currentHeaders = const <String, String>{};
    _currentServerQueue = <Map<String, dynamic>>[
      {
        'url': currentUrl,
        'headers': <String, String>{},
        'server_name': 'Watch Party',
      }
    ];
    final mediaKey = (state['mediaKey'] ?? '').toString();
    if (mediaKey.isNotEmpty && mediaKey.contains(':')) {
      final parts = mediaKey.split(':');
      if (parts.length >= 2) {
        _currentMediaType = parts.first;
        _currentMediaId = parts.sublist(1).join(':');
        _currentPlaybackKey = mediaKey;
      }
    }
    if (_currentMediaTitle.isEmpty || _currentMediaTitle == 'Sala compartida') {
      _currentMediaTitle = 'Sala compartida';
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _sub?.cancel();
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.of(context).size.width > 960;
    final width = MediaQuery.of(context).size.width;
    final tvScale = isTv ? (width / 1920).clamp(0.82, 1.18) : 1.0;
    final useCompactTv = isTv && width < 1500;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Sala ${widget.session.normalizedRoomId}',
          style: GoogleFonts.bebasNeue(
            color: _ink,
            fontSize: isTv ? 30 * tvScale : 22,
            letterSpacing: 0.8,
          ),
        ),
        backgroundColor: _bg,
        actions: [
          TextButton.icon(
            onPressed: _copyRoomCode,
            icon: const Icon(Icons.copy_all_rounded, color: _ink),
            label: Text('Copiar codigo', style: GoogleFonts.dmSans(color: _ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _leaveLobby,
            icon: const Icon(Icons.close_rounded, color: _inkMuted),
            label: Text('Salir', style: GoogleFonts.dmSans(color: _inkMuted, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(isTv ? 20 * tvScale : 12),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: (useCompactTv
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildLobbyMainColumn(isTv, tvScale)),
                    SizedBox(height: 16 * tvScale),
                    Expanded(flex: 2, child: _buildLobbyChatColumn(isTv, tvScale)),
                  ],
                )
              : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _buildLobbyMainColumn(isTv, tvScale),
            ),
            SizedBox(width: 20 * tvScale),
            Expanded(
              flex: 2,
              child: _buildLobbyChatColumn(isTv, tvScale),
            ),
          ],
        )),
        ),
      ),
    );
  }

  Widget _buildLobbyMainColumn(bool isTv, double tvScale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.mediaTitle,
          style: GoogleFonts.bebasNeue(
            color: _ink,
            fontSize: isTv ? 34 * tvScale : 24,
            letterSpacing: 0.6,
          ),
        ),
        SizedBox(height: 8 * tvScale),
        Text(
          _status,
          style: GoogleFonts.dmSans(
            color: _inkMuted,
            fontSize: isTv ? 14 * tvScale : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 16 * tvScale),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(14 * tvScale),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_surface, _surfaceSoft],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _lineStrong),
          ),
          child: Wrap(
            spacing: 12 * tvScale,
            runSpacing: 10 * tvScale,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _InfoChip(label: 'Codigo', value: widget.session.normalizedRoomId),
              _InfoChip(label: 'Rol', value: widget.session.isHost ? 'Anfitrion' : 'Invitado'),
              _InfoChip(label: 'Estado', value: _ready ? 'Listo' : 'Esperando'),
            ],
          ),
        ),
        SizedBox(height: 16 * tvScale),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12 * tvScale,
              runSpacing: 12 * tvScale,
              children: _roster.map((peer) {
                final peerId = peer['peerId']?.toString() ?? '';
                final isReady = _readyPeerIds.contains(peerId);
                final isHost = peer['isHost'] == true;
                return Container(
                  width: isTv ? 220 * tvScale : 180,
                  padding: EdgeInsets.all(12 * tvScale),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_surface, _surfaceSoft],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isReady ? Colors.greenAccent : _line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer['name']?.toString() ?? 'Invitado',
                        style: GoogleFonts.dmSans(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: isTv ? 14 * tvScale : 14,
                        ),
                      ),
                      SizedBox(height: 6 * tvScale),
                      Text(
                        isHost ? 'Anfitrion' : 'Invitado',
                        style: GoogleFonts.dmSans(
                          color: _muted,
                          fontSize: isTv ? 12 * tvScale : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6 * tvScale),
                      Text(
                        isReady ? 'Listo' : 'Esperando',
                        style: GoogleFonts.dmSans(
                          color: isReady ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: isTv ? 12 * tvScale : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        SizedBox(height: 14 * tvScale),
        Wrap(
          spacing: 12 * tvScale,
          runSpacing: 12 * tvScale,
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: ElevatedButton.icon(
                onPressed: _connecting ? null : _toggleReady,
                icon: Icon(_ready ? Icons.check_circle_outline : Icons.radio_button_unchecked),
                label: Text(_ready ? 'Quitar listo' : 'Estoy listo'),
              ),
            ),
            if (widget.session.isHost)
              FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: ElevatedButton.icon(
                  onPressed: _connecting ? null : _hostStart,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_starting ? 'Iniciando...' : 'Iniciar reproduccion'),
                ),
              ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: OutlinedButton.icon(
                onPressed: _copyRoomCode,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar codigo'),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: OutlinedButton.icon(
                onPressed: _leaveLobby,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Salir de la sala'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLobbyChatColumn(bool isTv, double tvScale) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_surface, _surfaceSoft],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
            ),
            child: ListView.builder(
              padding: EdgeInsets.all(12 * tvScale),
              itemCount: _chat.length,
              itemBuilder: (context, index) {
                final item = _chat[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: 10 * tvScale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name']?.toString() ?? 'Invitado',
                        style: GoogleFonts.dmSans(
                          color: _inkMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: isTv ? 13 * tvScale : 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['text']?.toString() ?? '',
                        style: GoogleFonts.dmSans(
                          color: _ink,
                          fontSize: isTv ? 14 * tvScale : 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: 10 * tvScale),
        FocusTraversalOrder(
          order: const NumericFocusOrder(10),
          child: TextField(
            controller: _chatController,
            style: GoogleFonts.dmSans(color: _ink, fontSize: isTv ? 14 * tvScale : 14, fontWeight: FontWeight.w600),
            onSubmitted: (_) => _sendChat(),
            decoration: InputDecoration(
              hintText: 'Escribir mensaje',
              hintStyle: GoogleFonts.dmSans(color: _muted),
              filled: true,
              fillColor: _surfaceSoft,
              suffixIcon: IconButton(
                onPressed: _sendChat,
                icon: const Icon(Icons.send, color: _ink),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _lineStrong),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _crimson),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  static const Color _surface = Color(0xCC17171A);
  static const Color _surfaceSoft = Color(0xB3131316);
  static const Color _line = Color(0x22FFFFFF);
  static const Color _ink = Color(0xFFF4F1EA);
  static const Color _muted = Color(0xFF8E877D);
  final String label;
  final String value;

  const _InfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_surface, _surfaceSoft]),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: GoogleFonts.dmSans(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.dmSans(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
