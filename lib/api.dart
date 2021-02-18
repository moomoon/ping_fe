import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:ping_fe/account.dart';
import 'package:rsocket/payload.dart';
import 'package:rsocket/rsocket.dart';
import 'package:rsocket/rsocket_connector.dart';

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
    rsocketUrl: 'ws://localhost:8080/chat',
  );
}

class RSocketConn {
  final Account account;
  final RSocket rsocket;

  RSocketConn({@required this.account, @required this.rsocket});

  static RSocketConn instance;

  close() {
    rsocket.close();
  }
}

extension on Account {
  Future<RSocketConn> rsocket(String url) async {
    final rsocket = await RSocketConnector.create()
        .setupPayload(Payload.fromText('', token))
        .connect(url);
    return RSocketConn(account: this, rsocket: rsocket);
  }
}

extension RSocketExt on Stream<Account> {
  static Stream<RSocketConn> _stream;
  Stream<RSocketConn> rsockets({@required String url}) async* {
    if (RSocketConn.instance != null) yield RSocketConn.instance;
    yield* _stream ??= this.transform(
        StreamTransformer<Account, RSocketConn>.fromHandlers(
            handleData: (account, sink) async {
      if (RSocketConn.instance?.account == account) return;
      RSocketConn.instance?.close();
      sink.add(RSocketConn.instance = await account?.rsocket(url));
    })).asBroadcastStream();
  }
}

extension ApiExt on BuildContext {
  Api get api => Api.instance;
  Stream<RSocketConn> get rsockets =>
      accountStore.stream.rsockets(url: api.rsocketUrl);
}

// Future<RSocket> connectRSocket(String url, String token) async {
//   var connectionSetupPayload = ConnectionSetupPayload()
//     ..keepAliveInterval = 20000
//     ..keepAliveMaxLifetime = 90000
//     ..metadataMimeType = 'message/x.rsocket.composite-metadata.v0'
//     ..dataMimeType = 'application/json'
//     ..data = Uint8List.fromList(utf8.encode(token));

//   print('token = $token');
//   return WebSocket.connect(
//     url,
//   ).then((socket) => WebSocketDuplexConnection(socket)).then((conn) {
//     final rsocketRequester =
//         RSocketRequester('requester', connectionSetupPayload, conn);
//     rsocketRequester.responder = RSocket();
//     rsocketRequester.errorConsumer = null;
//     rsocketRequester.sendSetupPayload();
//     return rsocketRequester;
//   });
// }
