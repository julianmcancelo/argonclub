import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final url = 'https://server.bixplay.online/server-nuevo-v2/?d=CMSoxwxUENI37QNihFGDHEeBysP7K734Q9CsPU9UAWCpgv_IUgdeGitFEmxPxC_GVj9fQsrqNIQ9q-TzwlzR8xER8Hde7T4tqfTSUQ';
  
  try {
    print('Fetching web player without headers...');
    var res = await dio.get(url);
    print('Length: ' + res.data.toString().length.toString());
    print(res.data.toString().substring(0, 500));
  } catch (e) {
    print('Failed without headers: ' + e.toString());
  }

  try {
    print('\nFetching web player WITH headers...');
    var res = await dio.get(
      url,
      options: Options(headers: {
        'Referer': 'https://appnew2.bixplay.online/'
      }),
    );
    print('Length: ' + res.data.toString().length.toString());
    print(res.data.toString().substring(0, 500));
  } catch (e) {
    print('Failed with headers: ' + e.toString());
  }
}
