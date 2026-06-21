import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/error_logger.dart';
import '../theme/argon_theme.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({Key? key}) : super(key: key);

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> with TickerProviderStateMixin {
  final TextEditingController _noteController = TextEditingController();
  bool _isSending = false;

  // Custom tweak settings for style
  String _accentName = 'Mono';
  bool _atmosphere = false;
  late AnimationController _auroraController;

  // Custom design system constants
  static const Color colorBg = Color(0xFF020A14);
  static const Color colorBg2 = ArgonTheme.navy;
  static const Color colorSurface = Color(0x0CFFFFFF);      // --surface: rgba(255,255,255,.045)
  static const Color colorSurface2 = Color(0x12FFFFFF);     // --surface-2: rgba(255,255,255,.07)
  static const Color colorLine = Color(0x17FFFFFF);         // --line: rgba(255,255,255,.09)
  static const Color colorLineStrong = Color(0x28FFFFFF);   // --line-strong: rgba(255,255,255,.16)
  static const Color colorInk = ArgonTheme.white;
  static const Color colorInk2 = Color(0xFFD9ECF8);
  static const Color colorInk3 = Color(0xFF86A7C0);

  // Dynamic branding and accents based on user tweaks (Mono, Arena, Niebla)
  Color get currentAccentColor {
    switch (_accentName) {
      case 'Arena':
        return const Color(0xFFE3CCAB); // warm gold/sand
      case 'Niebla':
        return const Color(0xFFBCD0E5); // cool blue/mist
      case 'Mono':
      default:
        return const Color(0xFFF4F4F7); // clean light gray
    }
  }

  @override
  void initState() {
    super.initState();
    _auroraController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat(reverse: true);
    
    _loadTweakSettings();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _auroraController.dispose();
    super.dispose();
  }

  Future<void> _loadTweakSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accentName = prefs.getString('argon_tweak_accent') ?? 'Mono';
      _atmosphere = prefs.getBool('argon_tweak_atmosphere') ?? false;
    });
  }

  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    await ErrorLogger.addCustomNote(text);
    _noteController.clear();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nota temporal guardada.', style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: const Color(0xFF131320),
      ),
    );
  }

  Future<void> _sendWhatsappReport() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      final report = ErrorLogger.buildWhatsappReport();
      final encoded = Uri.encodeComponent(report);
      final uri = Uri.parse('https://wa.me/541171631886?text=$encoded');

      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: report));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir WhatsApp. Reporte copiado.', style: GoogleFonts.outfit(color: Colors.white)),
            backgroundColor: const Color(0xFF131320),
          ),
        );
      }
    } catch (e, st) {
      await captureAndLogError(source: 'diagnostics.whatsapp', error: e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar: $e', style: GoogleFonts.outfit(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildAuroraBackground() {
    if (!_atmosphere) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _auroraController,
      builder: (context, child) {
        final val = _auroraController.value;
        final dx1 = 50.0 * val;
        final dy1 = 30.0 * (1.0 - val);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -200 + dy1,
              left: -150 + dx1,
              child: Container(
                width: 800,
                height: 800,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      currentAccentColor.withOpacity(0.07),
                      currentAccentColor.withOpacity(0.01),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = ErrorLogger.entries;
    final isTv = MediaQuery.of(context).size.width > 960;

    return Scaffold(
      backgroundColor: colorBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic Aurora floating blobs
          _buildAuroraBackground(),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Premium glassmorphic top header
                  _buildHeader(isTv),
                  const SizedBox(height: 20),

                  // Diagnostics and options block
                  _buildDiagnosticForm(isTv),
                  const SizedBox(height: 24),

                  // Title of error logs
                  Text(
                    'Errores capturados (${logs.length})',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: isTv ? 20 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Error list view
                  Expanded(
                    child: logs.isEmpty
                        ? Center(
                            child: Text(
                              'No hay errores capturados todavía.',
                              style: GoogleFonts.outfit(color: colorInk3, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            itemCount: logs.length,
                            itemBuilder: (context, index) {
                              final item = logs[index];
                              return _buildErrorLogCard(item, isTv);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isTv) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: colorInk),
              onPressed: () => Navigator.maybePop(context),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnóstico y Logs',
                  style: GoogleFonts.sora(
                    color: colorInk,
                    fontSize: isTv ? 28 : 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Registro en vivo de excepciones y depuración',
                  style: GoogleFonts.outfit(
                    color: colorInk3,
                    fontSize: isTv ? 13 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        
        Row(
          children: [
            IconButton(
              tooltip: 'Copiar reporte',
              onPressed: () async {
                final report = ErrorLogger.buildWhatsappReport();
                await Clipboard.setData(ClipboardData(text: report));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Reporte copiado.', style: GoogleFonts.outfit(color: Colors.white)),
                    backgroundColor: const Color(0xFF131320),
                  ),
                );
              },
              icon: const Icon(Icons.copy_all_rounded, color: colorInk2),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Limpiar',
              onPressed: () async {
                await ErrorLogger.clear();
                if (!mounted) return;
                setState(() {});
              },
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosticForm(bool isTv) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorLine, width: 1.2),
          ),
          child: Column(
            children: [
              TextField(
                controller: _noteController,
                maxLines: isTv ? 3 : 2,
                cursorColor: currentAccentColor,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Añadir nota manual (ej: error en reproductor, link roto)',
                  hintStyle: GoogleFonts.outfit(color: colorInk3),
                  filled: true,
                  fillColor: colorBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: colorLine),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: currentAccentColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildActionBtn(
                      label: 'Guardar temporal',
                      icon: Icons.save_outlined,
                      isTv: isTv,
                      onPressed: _saveNote,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionBtn(
                      label: _isSending ? 'Enviando...' : 'Enviar a WhatsApp',
                      icon: Icons.send_rounded,
                      isTv: isTv,
                      onPressed: _isSending ? null : _sendWhatsappReport,
                      highlighted: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorLogCard(ErrorLogEntry item, bool isTv) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorLine, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.source,
                  style: GoogleFonts.sora(
                    color: currentAccentColor,
                    fontSize: isTv ? 14 : 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  item.timestampIso,
                  style: GoogleFonts.outfit(color: colorInk3, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              item.message,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: isTv ? 16 : 13),
            ),
            if (item.stackTrace.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorLine, width: 1),
                ),
                child: SelectableText(
                  item.stackTrace.split('\n').take(6).join('\n'),
                  style: GoogleFonts.outfit(
                    color: colorInk3,
                    fontSize: isTv ? 12 : 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required String label,
    required IconData icon,
    required bool isTv,
    required VoidCallback? onPressed,
    bool highlighted = false,
  }) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          if (onPressed != null) onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final buttonColor = highlighted 
              ? currentAccentColor 
              : Colors.transparent;
          final textColor = highlighted 
              ? Colors.black 
              : Colors.white;

          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: EdgeInsets.symmetric(vertical: isTv ? 14 : 10),
              decoration: BoxDecoration(
                color: focused 
                    ? currentAccentColor.withOpacity(highlighted ? 0.8 : 0.25)
                    : buttonColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused 
                      ? Colors.white 
                      : (highlighted ? Colors.transparent : colorLineStrong),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon, 
                    color: focused ? (highlighted ? Colors.black : currentAccentColor) : textColor, 
                    size: isTv ? 18 : 15,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: focused ? (highlighted ? Colors.black : Colors.white) : textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: isTv ? 15 : 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}
