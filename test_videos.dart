import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://appnew2.bixplay.online/rest-api/v100/',
    headers: {
      'API-KEY': '1997c52cf132adc5ab840337fde468b8',
    },
  ));

  try {
    final detailsRes = await dio.get('single_details_new', queryParameters: {'type': 'movie', 'id': '21100'});
    
    if (detailsRes.data is Map) {
      final details = detailsRes.data;
      if (details['videos'] != null) {
         print(jsonEncode(details['videos']));
      }
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
