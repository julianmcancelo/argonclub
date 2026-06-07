import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final embedUrl = 'https://server.bixplay.online/server-nuevo-v2/?d=XtYIS26PYVWnbSZ7m7pf6zCzM4YpMHHNIxJsADZlpVe0jqCA5PZWWIQBrhP841jDpVj_V_pnP-q6b_sYioRWZ7MHG_N41EyeyJqitw';
  final userAgent = 'Mozilla/5.0 (Linux; Android 9; G011A Build/PI) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/68.0.3440.70 Mobile Safari/537.36 buscari/53';

  try {
    final response = await dio.get<String>(
      embedUrl,
      options: Options(
        headers: {
          'User-Agent': userAgent,
          'Referer': 'https://appnew2.bixplay.online/',
        },
      ),
    );
    final html = response.data ?? '';
    
    // Let's find preload-zone in HTML
    final preloadZoneRegex = RegExp(r'<div\s+class="preload-zone"[\s\S]*?</div>', caseSensitive: false);
    final zoneMatch = preloadZoneRegex.firstMatch(html);
    if (zoneMatch != null) {
      print('=== PRELOAD ZONE ===');
      print(zoneMatch.group(0));
    } else {
      print('Preload zone not found directly. Let us search for iframe tags:');
      final iframeReg = RegExp(r'<iframe[\s\S]*?>', caseSensitive: false);
      for (var m in iframeReg.allMatches(html)) {
        print('-> ' + (m.group(0) ?? ''));
      }
    }

    // Let's find the decrypt function definition
    final decryptRegex = RegExp(r'function\s+decrypt\([\s\S]*?\}', caseSensitive: false);
    final decryptMatch = decryptRegex.firstMatch(html);
    if (decryptMatch != null) {
      print('\n=== DECRYPT FUNCTION ===');
      print(decryptMatch.group(0));
    }

    // Let's find the script block where CryptoJS is defined/referenced
    final cryptoBlock = RegExp(r'const\s+key\s*=\s*[\s\S]*?;', caseSensitive: false);
    final cryptoMatch = cryptoBlock.firstMatch(html);
    if (cryptoMatch != null) {
      print('\n=== KEY OR CRYPTO MATCH ===');
      print(cryptoMatch.group(0));
    }
    
    // Print all matches of decrypt calls or AES keys
    final aesKeyRegex = RegExp(r"CryptoJS\.AES\.decrypt\([\s\S]*?\)", caseSensitive: false);
    final aesMatch = aesKeyRegex.firstMatch(html);
    if (aesMatch != null) {
      print('\n=== AES DECRYPT MATCH ===');
      print(aesMatch.group(0));
    }
  } catch (e) {
    print('Error: $e');
  }
}
