import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cast/cast.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';

enum CastDeviceType { chromecast, dlna }

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
  CastSession? _castSession;
  DLNADevice? _dlnaDevice;

  StreamSubscription? _dlnaSub;

  void startDiscovery() {
    if (kIsWeb) return; // Not supported on web
    isSearching = true;
    devices.clear();
    notifyListeners();

    _discoverChromecasts();
    _discoverDLNA();
  }

  void stopDiscovery() {
    isSearching = false;
    _dlnaSub?.cancel();
    notifyListeners();
  }

  Future<void> _discoverChromecasts() async {
    try {
      final castDevices = await CastDiscoveryService().search();
      for (var device in castDevices) {
        if (!devices.any((d) => d.id == device.host)) {
          devices.add(CastDeviceModel(
            id: device.host,
            name: device.name,
            type: CastDeviceType.chromecast,
            originalDevice: device,
          ));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error discovering Chromecast: $e");
    }
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
      if (device.type == CastDeviceType.chromecast) {
        final castDevice = device.originalDevice as CastDevice;
        _castSession = await CastSessionManager().startSession(castDevice);
        
        var message = {
          'type': 'LOAD',
          'autoPlay': true,
          'currentTime': 0,
          'media': {
            'contentId': videoUrl,
            'contentType': videoUrl.endsWith('.m3u8') ? 'application/x-mpegurl' : 'video/mp4',
            'streamType': 'BUFFERED',
            'metadata': {
              'type': 0,
              'metadataType': 0,
              'title': title,
            }
          }
        };
        _castSession?.sendMessage('urn:x-cast:com.google.cast.media', message);

      } else if (device.type == CastDeviceType.dlna) {
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
      _castSession?.close();
      _dlnaDevice?.stop();
    } catch (_) {}
    connectedDevice = null;
    _castSession = null;
    _dlnaDevice = null;
    notifyListeners();
  }
}
