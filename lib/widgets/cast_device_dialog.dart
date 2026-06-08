import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/casting_service.dart';

class CastDeviceDialog extends StatefulWidget {
  final String videoUrl;
  final String videoTitle;

  const CastDeviceDialog({
    Key? key,
    required this.videoUrl,
    required this.videoTitle,
  }) : super(key: key);

  @override
  State<CastDeviceDialog> createState() => _CastDeviceDialogState();
}

class _CastDeviceDialogState extends State<CastDeviceDialog> {
  final CastingService _castingService = CastingService();

  @override
  void initState() {
    super.initState();
    _castingService.addListener(_onServiceUpdate);
    _castingService.startDiscovery();
  }

  @override
  void dispose() {
    _castingService.removeListener(_onServiceUpdate);
    _castingService.stopDiscovery();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _connectToDevice(CastDeviceModel device) async {
    // Show loading while connecting
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFF97316)),
      ),
    );

    await _castingService.connectAndPlay(device, widget.videoUrl, widget.videoTitle);
    
    if (mounted) {
      Navigator.of(context).pop(); // Close loading
      Navigator.of(context).pop(); // Close dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xD91A1A1E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.cast_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Text(
                'Transmitir a TV',
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (_castingService.isSearching)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF97316)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (_castingService.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.tv_off_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text(
                    'Buscando dispositivos...',
                    style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: _castingService.devices.length,
              itemBuilder: (context, index) {
                final device = _castingService.devices[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _connectToDevice(device),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.tv_rounded,
                              color: const Color(0xFFF97316),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'DLNA/Smart TV',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
