import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/remote_control_service.dart';
import 'dashboard_screen.dart' show DashboardScreen;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/remote_control_service.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final RemoteControlService _service = RemoteControlService();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _connecting = false;
  bool _paired = false;
  String? _pairingCode;
  String? _error;
  Timer? _retryTimer;
  StreamSubscription? _pairingCodeSub;
  StreamSubscription? _pairingStatusSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await _service.connect();
      
      _pairingCodeSub = _service.pairingCodeStream.listen((code) {
        if (mounted) {
          setState(() {
            _pairingCode = code;
          });
        }
      });

      _pairingStatusSub = _service.pairingStatusStream.listen((paired) {
        if (mounted) {
          setState(() {
            _paired = paired;
            if (paired) _error = null;
          });
        }
      });

      setState(() {
        _connecting = false;
      });

      // If running on a TV/Desktop (wide viewport), automatically register as TV to show code
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final isTV = MediaQuery.of(context).size.width > 960;
          if (isTV) {
            _service.registerTv();
            // Retry every 5 seconds if code is still null
            _retryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
              if (_pairingCode == null && _service.isConnected) {
                _service.registerTv();
              } else if (_pairingCode != null) {
                timer.cancel();
              }
            });
          }
        }
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _error = 'Error de conexión: $e';
      });
    }
  }

  void _pair() {
    final code = _codeController.text.trim();
    if (code.length != 4) {
      setState(() {
        _error = 'El código debe tener 4 dígitos';
      });
      return;
    }
    _service.pairPhone(code);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _pairingCodeSub?.cancel();
    _pairingStatusSub?.cancel();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTV = MediaQuery.of(context).size.width > 960;
    
    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isTV ? 'Vincular Control Remoto' : 'Control Remoto TV',
          style: GoogleFonts.sora(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _connecting
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFF97316),
                  ),
                )
              : isTV
                  ? _buildTVUI()
                  : (_paired ? _buildRemoteUI() : _buildMobilePairingUI()),
        ),
      ),
    );
  }

  // TV View: Displays pairing code to be entered on mobile
  Widget _buildTVUI() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xB3121215), // colorGlass
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
             BoxShadow(color: Colors.white.withOpacity(0.05), blurRadius: 40)
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _paired ? Icons.phonelink_ring_rounded : Icons.settings_remote_rounded,
              size: 72,
              color: _paired ? const Color(0xFF4ADE80) : const Color(0xFFF97316),
            ),
            const SizedBox(height: 24),
            Text(
              _paired ? '¡Dispositivo Vinculado!' : 'Control Remoto Virtual',
              style: GoogleFonts.sora(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _paired
                  ? 'Puedes controlar la interfaz de tu Smart TV usando la pantalla de tu celular.'
                  : 'Navega de forma más fácil y escribe las búsquedas desde tu celular.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (!_paired) ...[
              Text(
                'CÓDIGO DE VINCULACIÓN',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                  boxShadow: _pairingCode != null ? [
                    BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 20)
                  ] : [],
                ),
                child: _pairingCode != null
                  ? Text(
                      _pairingCode!,
                      style: GoogleFonts.sora(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 16,
                        color: Colors.white,
                      ),
                    )
                  : _error != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 12),
                            Text(
                              'Error de Conexión',
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _connect,
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                              label: Text(
                                'Reintentar',
                                style: GoogleFonts.sora(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF97316),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Conectando...',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
              ),
              const SizedBox(height: 24),
              Text(
                'Entra a la aplicación en tu celular (o visita https://www.argonapp.lat), ve a Ajustes > Control Remoto e ingresa este código.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'v1.4.3+14 (Vidaa Web Vercel)',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Listo para usar. Navega desde tu celular.',
                      style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Mobile View: Link screen
  Widget _buildMobilePairingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.tv_off_rounded,
          size: 80,
          color: Colors.white.withOpacity(0.2),
        ),
        const SizedBox(height: 24),
        Text(
          'Vincular con tu Smart TV',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Introduce el código de 4 dígitos que aparece en la pantalla de tu televisor.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            hintText: '0000',
            hintStyle: GoogleFonts.sora(
              color: Colors.white.withOpacity(0.2),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFF97316), width: 2),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.redAccent,
              fontSize: 14,
            ),
          ),
        ],
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _pair,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF97316),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            'VINCULAR AHORA',
            style: GoogleFonts.sora(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Mobile View: Remote control D-pad interface
  Widget _buildRemoteUI() {
    return Column(
      children: [
        // Status Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4ADE80).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
              const SizedBox(width: 8),
              Text(
                'Vinculado al televisor',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),

        // D-Pad Controller
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.02),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Stack(
              children: [
                // Up Button
                Align(
                  alignment: Alignment.topCenter,
                  child: IconButton(
                    iconSize: 48,
                    icon: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white.withOpacity(0.8)),
                    onPressed: () => _service.sendKey('ArrowUp'),
                  ),
                ),
                // Down Button
                Align(
                  alignment: Alignment.bottomCenter,
                  child: IconButton(
                    iconSize: 48,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.8)),
                    onPressed: () => _service.sendKey('ArrowDown'),
                  ),
                ),
                // Left Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    iconSize: 48,
                    icon: Icon(Icons.keyboard_arrow_left_rounded, color: Colors.white.withOpacity(0.8)),
                    onPressed: () => _service.sendKey('ArrowLeft'),
                  ),
                ),
                // Right Button
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    iconSize: 48,
                    icon: Icon(Icons.keyboard_arrow_right_rounded, color: Colors.white.withOpacity(0.8)),
                    onPressed: () => _service.sendKey('ArrowRight'),
                  ),
                ),
                // OK Button (Center)
                Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => _service.sendKey('Enter'),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFFF97316), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x44F97316),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'OK',
                          style: GoogleFonts.sora(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),

        // Extra action controls (Back, Home)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(Icons.arrow_back_rounded, 'Atrás', () {
              _service.sendKey('Backspace');
            }),
            _buildActionButton(Icons.refresh_rounded, 'Recargar', () {
              _service.sendKey('Backspace');
            }),
          ],
        ),
        const Spacer(),

        // Search Input (Real-time TV typing)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.outfit(color: Colors.white),
            decoration: InputDecoration(
              icon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5)),
              hintText: 'Escribe aquí para buscar en TV...',
              hintStyle: GoogleFonts.outfit(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
            ),
            onChanged: (val) {
              _service.sendSearch(val);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
