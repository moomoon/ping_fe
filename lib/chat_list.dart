import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/main_router.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:rsocket/rsocket.dart';

class ChatListWidget extends StatelessWidget {
  static const page =
      MaterialPage(key: ValueKey('chat_list'), child: ChatListWidget());

  const ChatListWidget({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    Widget content = StreamBuilder<List<Chat>>(
        stream: context.rsockets.chatList,
        builder: (context, snapshot) {
          return ListView.builder(
              itemCount: snapshot?.data?.length ?? 0,
              itemBuilder: (context, index) {
                return InkWell(
                    onTap: () {
                      context.mainRouter.pushChat(snapshot.data[index]);
                    },
                    child: Text(snapshot.data[index].id));
              });
        });
    return Scaffold(
        appBar: AppBar(
          title: Text('chat list'),
          actions: [
            StreamBuilder<RSocketConn>(
              stream: context.rsockets,
              builder: (context, snapshot) => snapshot.hasData
                  ? IconButton(
                      icon: Icon(Icons.add),
                      onPressed: () {
                        snapshot.requireData.rsocket
                            .fireAndForget('chats.random'.asRoute());
                      })
                  : const SizedBox(),
            ),
          ],
        ),
        body: content);
  }
}

class ChatListStore {
  final Account account;
  final RSocket rsocket;
  Stream<List<Chat>> _stream;
  StreamSubscription<List<Chat>> _remoteSubscription;

  ChatListStore({@required this.account, @required this.rsocket});

  Stream<List<Chat>> get stream => _stream ??= rsocket
      .requestStream('chats.stream'.asRoute())
      .map<Chat>((payload) => Chat.fromBuffer(payload.data))
      .scan<List<Chat>>(<Chat>[], (l, r) => l..add(r)).asBroadcastStream(
          onCancel: (s) => _remoteSubscription = s);

  Future<void> cancel() async {
    await _remoteSubscription.cancel();
  }

  static ChatListStore current;
}

extension on RSocketConn {
  ChatListStore get chatListStream =>
      ChatListStore(account: account, rsocket: rsocket);
}

extension ChatList on Stream<RSocketConn> {
  static Stream<List<Chat>> _stream;
  Stream<List<Chat>> get chatList {
    return _stream ??= transform(
        StreamTransformer<RSocketConn, ChatListStore>.fromHandlers(
            handleData: (conn, sink) async {
      if (conn?.account == ChatListStore.current?.account) return;
      await ChatListStore.current?.cancel();
      sink.add(ChatListStore.current = conn?.chatListStream);
    })).asyncExpand((holder) async* {
      if (holder == null)
        yield <Chat>[];
      else
        yield* holder.stream;
    }).asBroadcastStream();
  }
}
