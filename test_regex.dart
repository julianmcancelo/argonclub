import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final url = 'https://server.bixplay.online/server-nuevo-v2/?d=xztHKy6WdEyozbVEiEJI7mbxSJnGnr6Fw8Vsjol9jYZduwr6rA2k6qydjkQ4W6Erp2wRym3B_KALnTxRNO1lz2aPwOrnDibipAhx8g';
  
  try {
    print('Fetching web player...');
    var res = await dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://appnew2.bixplay.online/'
      }),
    );
    String html = res.data.toString();
    print('HTML length: \${html.length}');
    
    // Search for m3u8
    final regex = RegExp(r'(https?://[^"\'\s]+\.m3u8[^"\'\s]*)');
    final matches = regex.allMatches(html);
    
    if (matches.isNotEmpty) {
      print('FOUND M3U8 DIRECTLY IN HTML:');
      for (var match in matches) {
        print(match.group(1));
      }
    } else {
      print('No m3u8 found in HTML.');
      // print first 1000 chars to see what it is
      print(html.substring(0, 1000));
    }
  } catch (e) {
    print('Failed: ' + e.toString());
  }
}
