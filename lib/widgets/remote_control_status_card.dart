import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/remote_control_service.dart';

class RemoteControlStatusCard extends StatefulWidget {
  final bool isTV;

  const RemoteControlStatusCard({super.key, required this.isTV});

  @override
  State<RemoteControlStatusCard> createState() =>
      _RemoteControlStatusCardState();
}

class _RemoteControlStatusCardState extends State<RemoteControlStatusCard> {
  final RemoteControlService _service = RemoteControlService();
  StreamSubscription<String>? _codeSub;
  StreamSubscription<bool>? _statusSub;
  StreamSubscription<String>? _deviceSub;
  StreamSubscription<String>? _keySub;
  late bool _paired;
  String? _code;
  late String _device;
  String? _lastKey;

  @override
  void initState() {
    super.initState();
    _paired = _service.isPaired;
    _code = _service.pairingCode;
    _device = _service.pairedDeviceLabel;
    _lastKey = _service.lastRemoteKey;
    _codeSub = _service.pairingCodeStream.listen((code) {
      if (mounted) setState(() => _code = code);
    });
    _statusSub = _service.pairingStatusStream.listen((paired) {
      if (mounted) setState(() => _paired = paired);
    });
    _deviceSub = _service.pairedDeviceStream.listen((device) {
      if (mounted) setState(() => _device = device);
    });
    _keySub = _service.remoteKeyStream.listen((key) {
      if (mounted) setState(() => _lastKey = key);
    });
  }

  @override
  void dispose() {
    _codeSub?.cancel();
    _statusSub?.cancel();
    _deviceSub?.cancel();
    _keySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _paired ? const Color(0xFF4ADE80) : const Color(0xFFF59E0B);
    final scale = widget.isTV ? 1.0 : 0.82;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      constraints: BoxConstraints(minWidth: widget.isTV ? 236 : 190),
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36 * scale,
            height: 36 * scale,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _paired
                  ? Icons.phonelink_ring_rounded
                  : Icons.settings_remote_rounded,
              color: accent,
              size: 21 * scale,
            ),
          ),
          SizedBox(width: 11 * scale),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _paired ? 'CONTROL CONECTADO' : 'VINCULAR CONTROL',
                    style: GoogleFonts.dmSans(
                      color: accent,
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 3 * scale),
              Text(
                _paired ? _device : 'PIN ${_code ?? '....'}',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: _paired ? 0 : 2.2,
                ),
              ),
              Text(
                _paired
                    ? 'Listo${_lastKey == null ? '' : ' · ${_labelForKey(_lastKey!)}'}'
                    : 'Ingresa este código en el celular',
                style: GoogleFonts.dmSans(
                  color: Colors.white70,
                  fontSize: 9 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _labelForKey(String key) {
    switch (key) {
      case 'ArrowUp':
        return '↑';
      case 'ArrowDown':
        return '↓';
      case 'ArrowLeft':
        return '←';
      case 'ArrowRight':
        return '→';
      case 'Enter':
        return 'OK';
      case 'Escape':
      case 'Backspace':
        return 'Atrás';
      default:
        return key;
    }
  }
}
