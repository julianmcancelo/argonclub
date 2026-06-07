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
    print('--- Testing TV Series Details ---');
    final listRes = await dio.get('tvseries', queryParameters: {'page': 1});
    String seriesId = '';
    if (listRes.data is Map && listRes.data.containsKey('data')) {
      seriesId = listRes.data['data'][0]['videos_id']?.toString() ?? '';
    } else if (listRes.data is List && listRes.data.isNotEmpty) {
      seriesId = listRes.data[0]['videos_id']?.toString() ?? '';
    }
    
    print('Using TV Series ID: ' + seriesId);
    if (seriesId.isNotEmpty) {
      final res = await dio.get('single_details_new', queryParameters: {'type': 'tvseries', 'id': seriesId});
      print('Details keys: ' + res.data.keys.toString());
      if (res.data is Map && res.data.containsKey('season')) {
         final seasons = res.data['season'] as List;
         if (seasons.isNotEmpty) {
            final season = seasons[0];
            print('Season keys: ' + season.keys.toString());
            final episodes = season['episodes'] as List;
            if (episodes.isNotEmpty) {
               final ep = episodes[0];
               print('Episode keys: ' + ep.keys.toString());
               print('Episode contents: ' + jsonEncode(ep));
            }
         }
      }
    }
  } catch (e) {
    print('Global Error: \$e');
  }
}
