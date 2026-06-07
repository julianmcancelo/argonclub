import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/error_logger.dart';
import 'remote_control_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _noteController = TextEditingController();
  bool _isSending = false;
  Map<String, dynamic>? _activeProfile;
  int _profilesCount = 0;

  // Custom tweak settings for style
  String _accentName = 'Mono';
  bool _atmosphere = false;
  late AnimationController _auroraController;

  // Custom design system constants
  static const Color colorBg = Color(0xFF0A0A0D);
  static const Color colorBg2 = Color(0xFF0D0D12);
  static const Color colorSurface = Color(0x0CFFFFFF);      // --surface: rgba(255,255,255,.045)
  static const Color colorSurface2 = Color(0x12FFFFFF);     // --surface-2: rgba(255,255,255,.07)
  static const Color colorLine = Color(0x17FFFFFF);         // --line: rgba(255,255,255,.09)
  static const Color colorLineStrong = Color(0x28FFFFFF);   // --line-strong: rgba(255,255,255,.16)
  static const Color colorInk = Color(0xFFF4F4F7);
  static const Color colorInk2 = Color(0xFFB7B7C2);
  static const Color colorInk3 = Color(0xFF7C7C89);

  // Profile avatar colors / gradients
  static const List<List<Color>> avatarGradients = [
    [Color(0xFF00B0FF), Color(0xFF6200EE)], // Blue-Purple
    [Color(0xFFE040FB), Color(0xFF8E24AA)], // Magenta-Pink
    [Color(0xFFFF5722), Color(0xFFE91E63)], // Orange-Red
    [Color(0xFFFFC107), Color(0xFFFF9800)], // Amber-Gold
    [Color(0xFF00E676), Color(0xFF00B0FF)], // Emerald-Cyan
  ];

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
    _tabController = TabController(length: 2, vsync: this);
    
    _auroraController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat(reverse: true);

    _loadAccountData();
    _loadTweakSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  Future<void> _loadAccountData() async {
    final prefs = await SharedPreferences.getInstance();
    final profilesJson = prefs.getStringList('argon_profiles') ?? [];
    final activeId = prefs.getString('argon_active_profile_id');

    final profiles = profilesJson
        .map((p) => Map<String, dynamic>.from(jsonDecode(p)))
        .toList(growable: false);

    Map<String, dynamic>? active;
    if (profiles.isNotEmpty) {
      active = profiles.firstWhere(
        (p) => p['id']?.toString() == activeId,
        orElse: () => profiles.first,
      );
    }

    if (!mounted) return;
    setState(() {
      _profilesCount = profiles.length;
      _activeProfile = active;
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
        content: Text('Nota guardada.', style: GoogleFonts.outfit(color: Colors.white)),
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
      await captureAndLogError(source: 'settings.whatsapp', error: e, stackTrace: st);
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
        final dx2 = -40.0 * val;
        final dy2 = 40.0 * val;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -260 + dy1,
              right: -140 + dx1,
              child: Container(
                width: 800,
                height: 800,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      currentAccentColor.withOpacity(0.08),
                      currentAccentColor.withOpacity(0.02),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -200 + dy2,
              left: -200 + dx2,
              child: Container(
                width: 700,
                height: 700,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      currentAccentColor.withOpacity(0.06),
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
    final isTv = MediaQuery.of(context).size.width > 960;
    final logs = ErrorLogger.entries;

    return Scaffold(
      backgroundColor: colorBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic atmosphere Aurora
          _buildAuroraBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Premium glassmorphic top header
                _buildHeader(isTv),

                // Tab selectors matching the main theme
                _buildTabSelectors(isTv),

                // Page contents
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAccountTab(isTv),
                      _buildErrorsTab(isTv, logs),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isTv) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0, vertical: 20.0),
      child: Row(
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
                    'Ajustes del Sistema',
                    style: GoogleFonts.sora(
                      color: colorInk,
                      fontSize: isTv ? 28 : 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Configuración general y diagnóstico de red',
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
          
          // Profile Indicator Chip
          if (_activeProfile != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: colorSurface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: colorLine, width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: avatarGradients[(_activeProfile!['gradientIndex'] as int? ?? 0) % avatarGradients.length],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _activeProfile!['avatar'] as String? ?? 'A',
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _activeProfile!['name'] as String? ?? 'Invitado',
                    style: GoogleFonts.outfit(
                      color: colorInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabSelectors(bool isTv) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorLine, width: 1.2),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: currentAccentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: currentAccentColor, width: 1.5),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: colorInk3,
          labelStyle: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Mi Cuenta'),
            Tab(text: 'Registro de Errores'),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountTab(bool isTv) {
    final profileName = (_activeProfile?['name'] ?? 'Invitado').toString();
    final avatar = (_activeProfile?['avatar'] ?? 'I').toString();
    final gradIndex = _activeProfile?['gradientIndex'] as int? ?? 0;
    final colors = avatarGradients[gradIndex % avatarGradients.length];

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0, vertical: 24.0),
      children: [
        // Glassmorphic Profile Card
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorLine, width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    width: isTv ? 72 : 54,
                    height: isTv ? 72 : 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      avatar,
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: isTv ? 28 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileName,
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontSize: isTv ? 22 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Perfil de reproducción premium · $_profilesCount perfiles activos',
                          style: GoogleFonts.outfit(color: colorInk2, fontSize: isTv ? 14 : 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 20),

        // System configuration details card
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorLine, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Información de la Aplicación',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: isTv ? 18 : 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSystemInfoRow('Versión', '1.0.0 (AAB Store Build)', isTv),
                  _buildSystemInfoRow('Modo de Interfaz', 'Smart TV Horizontal', isTv),
                  _buildSystemInfoRow('Acento de Color Activo', _accentName, isTv),
                  _buildSystemInfoRow('Fondo Atmósfera', _atmosphere ? 'Activado' : 'Desactivado', isTv),
                  _buildSystemInfoRow('Reportes y Soporte', 'WhatsApp +54 11 7163-1886', isTv),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 20),

        // Remote Control Pairing Card
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorLine, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Control Remoto',
                        style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: isTv ? 18 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.settings_remote_rounded,
                        color: currentAccentColor,
                        size: isTv ? 24 : 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isTv
                        ? 'Vincula tu celular para usarlo como control remoto, navegar y escribir más rápido en tu televisor.'
                        : 'Vincula tu celular con tu Smart TV para navegar y escribir búsquedas fácilmente.',
                    style: GoogleFonts.outfit(
                      color: colorInk2,
                      fontSize: isTv ? 14 : 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildActionBtn(
                    label: isTv ? 'Ver Código de Vinculación' : 'Vincular con Smart TV',
                    icon: Icons.phonelink_setup_rounded,
                    isTv: isTv,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RemoteControlScreen(),
                        ),
                      );
                    },
                    highlighted: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemInfoRow(String label, String value, bool isTv) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(color: colorInk2, fontSize: isTv ? 15 : 13, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(color: colorInk, fontSize: isTv ? 15 : 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorsTab(bool isTv, List<ErrorLogEntry> logs) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 48.0 : 16.0, vertical: 24.0),
      child: Column(
        children: [
          // Glassmorphic actions card
          ClipRRect(
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
                        hintText: 'Describe el error o guarda una nota temporal aquí',
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
                            label: 'Guardar Nota',
                            icon: Icons.save_outlined,
                            isTv: isTv,
                            onPressed: _saveNote,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionBtn(
                            label: _isSending ? 'Enviando...' : 'Enviar Reporte',
                            icon: Icons.send_rounded,
                            isTv: isTv,
                            onPressed: _isSending ? null : _sendWhatsappReport,
                            highlighted: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
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
                          icon: const Icon(Icons.copy_rounded, color: colorInk2, size: 16),
                          label: Text('Copiar al Portapapeles', style: GoogleFonts.outfit(color: colorInk2)),
                        ),
                        const SizedBox(width: 16),
                        TextButton.icon(
                          onPressed: () async {
                            await ErrorLogger.clear();
                            if (!mounted) return;
                            setState(() {});
                          },
                          icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 16),
                          label: Text('Limpiar Historial', style: GoogleFonts.outfit(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Historial de Diagnóstico (${logs.length})',
              style: GoogleFonts.sora(color: Colors.white, fontSize: isTv ? 18 : 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      'No hay logs de error registrados.',
                      style: GoogleFonts.outfit(color: colorInk3, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final item = logs[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorSurface,
                            borderRadius: BorderRadius.circular(12),
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
                                    style: GoogleFonts.outfit(color: colorInk3, fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                item.message,
                                style: GoogleFonts.outfit(color: colorInk, fontSize: isTv ? 15 : 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
