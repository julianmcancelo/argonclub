import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://appnew2.bixplay.online/rest-api/v100/',
    headers: {'API-KEY': '1997c52cf132adc5ab840337fde468b8'},
  ));

  try {
    print('Testing live_tv_channel_category...');
    final res = await dio.get('live_tv_channel_category');
    print(res.data.toString());
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
