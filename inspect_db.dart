import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'dart:io';

void main() async {
  // SharedPreferences on Windows saves to a local JSON file in AppData or registry.
  // But wait, if we run it on the computer, it reads the Windows preferences, not the emulator preferences!
  // To read the emulator's preferences, we can run an adb command to dump the shared_prefs XML file!
  // The XML file on android is stored at: /data/data/com.argonapp/shared_prefs/FlutterSharedPreferences.xml
  print("Use adb to cat the shared preferences file...");
}
