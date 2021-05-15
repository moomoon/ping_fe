import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/avatar.dart';
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
    Widget content = StreamBuilder<List<ChatInfo>>(
        stream: context.rsockets.chatList,
        builder: (context, snapshot) {
          return ListView.builder(
              itemCount: snapshot?.data?.length ?? 0,
              itemBuilder: (context, index) {
                return InkWell(
                    onTap: () {
                      context.mainRouter.pushChat(snapshot.data[index]);
                    },
                    child: ChatCell(chat: snapshot.data[index]));
              });
        });
    content = Container(
        child: content, color: Color.lerp(Colors.white, Colors.black, 0.8));
    return Scaffold(
        appBar: AppBar(
          title: Text('chat list'),
          backgroundColor: Color.lerp(Colors.white, Colors.black, 0.9),
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

class ChatCell extends StatelessWidget {
  final ChatInfo chat;

  const ChatCell({Key key, @required this.chat}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final currUser = context.accountStore.value?.username;
    final other = chat.users.firstWhere(
      (e) => e.username != currUser,
      orElse: () => null,
    );
    return Row(
      children: [Avatar(profile: other)],
    );
  }
}

class ChatList with ListChangeNotifier<ChatCellData> {
  List<ChatInfo> _unapprovedByMe = [];
  List<ChatInfo> _initiatedByMeUnapproved = [];
  List<ChatInfo> _valid = [];
}

class ChatCellData {

}

class ChatListStore {
  final Account account;
  final RSocket rsocket;
  Stream<List<ChatInfo>> _stream;
  StreamSubscription<List<ChatInfo>> _remoteSubscription;
  List<ChatInfo> _chatInfo = [];
  List<ChatInfo> get chatInfo => _chatInfo;

  ChatListStore({@required this.account, @required this.rsocket});

  Stream<List<ChatInfo>> get stream => _stream ??= rsocket
          .requestStream('chats.stream'.asRoute())
          .map<ChatInfo>((payload) => ChatInfo.fromBuffer(payload.data))
          .scan<List<ChatInfo>>(
        <ChatInfo>[],
        (l, r) => l..add(r),
      ).asBroadcastStream(onCancel: (s) => _remoteSubscription = s)
            ..listen((event) {
              _chatInfo = event;
            });

  Future<void> cancel() async {
    await _remoteSubscription.cancel();
  }

  static ChatListStore current;
}

extension on RSocketConn {
  ChatListStore get chatListStream =>
      ChatListStore(account: account, rsocket: rsocket);
}

extension ChatStreams on Stream<RSocketConn> {
  static Stream<List<ChatInfo>> _stream;
  Stream<List<ChatInfo>> get chatList async* {
    if (ChatListStore.current?.chatInfo != null) {
      yield ChatListStore.current.chatInfo;
    }
    yield* _stream ??= transform(
        StreamTransformer<RSocketConn, ChatListStore>.fromHandlers(
            handleData: (conn, sink) async {
      if (conn?.account == ChatListStore.current?.account) return;
      await ChatListStore.current?.cancel();
      sink.add(ChatListStore.current = conn?.chatListStream);
    })).asyncExpand((holder) async* {
      if (holder == null)
        yield <ChatInfo>[];
      else
        yield* holder.stream;
    }).asBroadcastStream();
  }
}
