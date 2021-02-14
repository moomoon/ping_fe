import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ping_fe/chat.dart';
import 'package:ping_fe/foundation.dart';
import 'package:rsocket/rsocket.dart';

class ChatListWidget extends StatelessWidget {
  const ChatListWidget({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    throw UnimplementedError();
  }
}

class ChatListStore with ListStore<Chat>, DEListStore {
  final RSocket socket;

  ChatListStore({@required this.socket});
  @override
  FutureOr<List<Chat>> fullRefresh() async {
    // socket.requestResponse('');
  }

  @override
  Object id(Chat v) => v.id;
  @override
  FutureOr<List<Chat>> loadMore() {
    // TODO: implement loadMore
    throw UnimplementedError();
  }
}
