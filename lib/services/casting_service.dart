import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';

enum CastDeviceType { dlna }

class CastDeviceModel {
  final String id;
  final String name;
  final CastDeviceType type;
  final dynamic originalDevice;

  CastDeviceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.originalDevice,
  });
}

class CastingService extends ChangeNotifier {
  static final CastingService _instance = CastingService._internal();
  factory CastingService() => _instance;
  CastingService._internal();

  List<CastDeviceModel> devices = [];
  bool isSearching = false;
  CastDeviceModel? connectedDevice;
  DLNADevice? _dlnaDevice;
  StreamSubscription? _dlnaSub;

  void startDiscovery() {
    if (kIsWeb) return; // Not supported on web
    isSearching = true;
    devices.clear();
    notifyListeners();

    _discoverDLNA();
  }

  void stopDiscovery() {
    isSearching = false;
    _dlnaSub?.cancel();
    notifyListeners();
  }

  void _discoverDLNA() async {
    try {
      final dlnaManager = DLNAManager();
      final deviceManager = await dlnaManager.start();
      _dlnaSub = deviceManager.devices.stream.listen((deviceMap) {
        for (final device in deviceMap.values) {
          if (!devices.any((d) => d.id == device.info.friendlyName)) {
            devices.add(CastDeviceModel(
              id: device.info.friendlyName,
              name: device.info.friendlyName,
              type: CastDeviceType.dlna,
              originalDevice: device,
            ));
            notifyListeners();
          }
        }
      });
    } catch (e) {
      debugPrint("Error discovering DLNA: $e");
    }
  }

  Future<void> connectAndPlay(CastDeviceModel device, String videoUrl, String title) async {
    connectedDevice = device;
    notifyListeners();

    try {
      if (device.type == CastDeviceType.dlna) {
        _dlnaDevice = device.originalDevice as DLNADevice;
        await _dlnaDevice?.setUrl(videoUrl, title: title, type: PlayType.Video);
        await _dlnaDevice?.play();
      }
    } catch (e) {
      debugPrint("Error playing on cast: $e");
      connectedDevice = null;
      notifyListeners();
    }
  }

  void disconnect() {
    try {
      _dlnaDevice?.stop();
    } catch (_) {}
    connectedDevice = null;
    _dlnaDevice = null;
    notifyListeners();
  }
}
