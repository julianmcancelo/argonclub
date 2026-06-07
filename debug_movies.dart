import 'package:dio/dio.dart';
import 'dart:convert';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://appnew2.bixplay.online/rest-api/v100/',
    headers: {'API-KEY': '1997c52cf132adc5ab840337fde468b8'},
    validateStatus: (s) => true,
  ));

  try {
    // 1. Test search for "avengers"
    print('=== SEARCH: avengers ===');
    final s1 = await dio.get('search/avengers/1');
    print('Status: ' + s1.statusCode.toString());
    if (s1.data is Map) {
      final keys = (s1.data as Map).keys.toList();
      print('Keys: ' + keys.toString());
      for (var k in keys) {
        if (s1.data[k] is List) {
          print(k + ' count: ' + (s1.data[k] as List).length.toString());
          if ((s1.data[k] as List).isNotEmpty) {
            print(k + '[0] title: ' + (s1.data[k][0]['title'] ?? s1.data[k][0]['tv_name'] ?? 'N/A').toString());
          }
        }
      }
    } else {
      print('Data type: ' + s1.data.runtimeType.toString());
      print('Data: ' + s1.data.toString().substring(0, s1.data.toString().length > 300 ? 300 : s1.data.toString().length));
    }

    // 2. Get genres/categories
    print('\n=== GENRES ===');
    final g1 = await dio.get('all_genre');
    print('Status: ' + g1.statusCode.toString());
    if (g1.data is List && (g1.data as List).isNotEmpty) {
      print('Genres count: ' + (g1.data as List).length.toString());
      for (var i = 0; i < 5 && i < (g1.data as List).length; i++) {
        print('Genre ' + i.toString() + ': ' + (g1.data[i]['name'] ?? g1.data[i]['genre_name'] ?? g1.data[i].toString()));
      }
    } else if (g1.data is Map) {
      print('Genre keys: ' + (g1.data as Map).keys.toList().toString());
    }

    // 3. Try other genre endpoints
    print('\n=== genre ===');
    final g2 = await dio.get('genre');
    print('Status: ' + g2.statusCode.toString());
    if (g2.data is List && (g2.data as List).isNotEmpty) {
      print('count: ' + (g2.data as List).length.toString());
      print('first: ' + g2.data[0].toString());
    } else if (g2.data is Map) {
      print('keys: ' + (g2.data as Map).keys.toList().toString());
    }

    // 4. Try country endpoints
    print('\n=== all_country ===');
    final c1 = await dio.get('all_country');
    print('Status: ' + c1.statusCode.toString());
    if (c1.data is List && (c1.data as List).isNotEmpty) {
      print('count: ' + (c1.data as List).length.toString());
      print('first: ' + c1.data[0].toString());
    }

    // 5. Get a movie details to see the Multiple Rapido server
    print('\n=== MOVIE DETAILS (type=movie, id=21100) ===');
    final m1 = await dio.get('single_details_new', queryParameters: {'type': 'movie', 'id': '21100'});
    if (m1.data is Map && m1.data['videos'] is List) {
      final vids = m1.data['videos'] as List;
      print('Videos count: ' + vids.length.toString());
      for (var i = 0; i < vids.length; i++) {
        final v = vids[i];
        print('  Server ' + i.toString() + ': label=' + (v['label'] ?? 'N/A').toString() +
            ' file_type=' + (v['file_type'] ?? 'N/A').toString() +
            ' url=' + (v['file_url'] ?? 'N/A').toString().substring(0, (v['file_url'] ?? '').toString().length > 80 ? 80 : (v['file_url'] ?? '').toString().length));
      }
    }

    // 6. Try movies by genre
    print('\n=== content_by_genre_id ===');
    final bg = await dio.get('content_by_genre_id', queryParameters: {'id': '1', 'page': 1});
    print('Status: ' + bg.statusCode.toString());
    if (bg.data is Map) print('keys: ' + (bg.data as Map).keys.toList().toString());

    // 7. Try movies_by_genre
    print('\n=== movies_by_genre ===');
    final mg = await dio.get('movies_by_genre', queryParameters: {'id': '1', 'page': 1});
    print('Status: ' + mg.statusCode.toString());
    if (mg.data is Map) print('keys: ' + (mg.data as Map).keys.toList().toString());

  } catch (e) {
    print('GLOBAL ERROR: ' + e.toString());
  }
}
