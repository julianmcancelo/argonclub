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
    final listRes = await dio.get('tvseries', queryParameters: {'page': 1});
    String id = '';
    if (listRes.data is List && listRes.data.isNotEmpty) {
      id = listRes.data[0]['tv_series_id']?.toString() ?? '';
      print('Found ID: \$id');
    } else if (listRes.data is Map && listRes.data['data'] != null) {
      id = listRes.data['data'][0]['tv_series_id']?.toString() ?? '';
      print('Found ID from Map: \$id');
    }

    if (id.isNotEmpty) {
      final detailsRes = await dio.get('single_details_new', queryParameters: {'type': 'tvseries', 'id': id});
      print(jsonEncode(detailsRes.data['season']));
    }
  } catch (e) {
    print('Error: ' + e.toString());
  }
}
