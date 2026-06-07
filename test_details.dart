import 'package:dio/dio.dart';
import 'dart:convert';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://appnew2.bixplay.online/rest-api/v100/',
    headers: {
      'API-KEY': '1997c52cf132adc5ab840337fde468b8',
    },
  ));

  try {
    print('Fetching movies...');
    final listRes = await dio.get('movies', queryParameters: {'page': 1});
    String id = '';
    if (listRes.data is List && listRes.data.isNotEmpty) {
      id = listRes.data[0]['movies_id']?.toString() ?? '';
    } else if (listRes.data is Map && listRes.data['data'] != null) {
      id = listRes.data['data'][0]['movies_id']?.toString() ?? '';
    }
    print('Movie ID: \$id');

    if (id.isNotEmpty) {
      final res = await dio.get('single_details_new', queryParameters: {'type': 'movies', 'id': id});
      print('Keys in response: \${res.data.keys}');
      if (res.data is Map) {
        if (res.data.containsKey('videos')) {
          print('Found videos directly!');
        } else if (res.data.containsKey('data')) {
          print('Found data! keys in data: \${res.data['data'].keys}');
        }
        print(jsonEncode(res.data).substring(0, 300));
      }
    }
  } catch (e) {
    print('Error: \$e');
  }
}
