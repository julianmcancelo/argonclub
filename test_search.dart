import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://appnew2.bixplay.online/rest-api/v100/',
    headers: {
      'API-KEY': '1997c52cf132adc5ab840337fde468b8',
    },
  ));

  try {
    print('Testing search...');
    final res = await dio.get('search/batman/1');
    print(res.data.toString().substring(0, 300));
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
