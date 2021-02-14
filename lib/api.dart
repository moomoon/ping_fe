import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class Api {
  final String httpBaseUrl;
  final String rsocketUrl;

  const Api({@required this.httpBaseUrl, @required this.rsocketUrl});

  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    final resp = await http
        .post(httpBaseUrl + path,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 5));
    return jsonDecode(resp.body);
  }

  static const Api instance = Api(
    httpBaseUrl: 'http://localhost:8080',
    rsocketUrl: 'ws://localhost:8080',
  );
}

extension ApiExt on BuildContext {
  Api get api => Api.instance;
}
