import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/emoji/emoji_input.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/persistent.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:rsocket/rsocket.dart';

class MessageSectionWidget extends StatelessWidget {
  final MessageSection section;

  const MessageSectionWidget({Key key, @required this.section})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExternalStatefulBuilder(
        state: section,
        builder: (context, section) {
          return Text(section.messages.map((e) => e.content).join());
        });
  }
}

class _MessageList extends StatefulWidget {
  final ChatMessageStore store;

  const _MessageList({Key key, this.store}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _MessageListState();
  }
}

class _MessageListState extends State<_MessageList>
    with ListChanged<MessageSection> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  VoidCallback _listDisposable;
  @override
  void initState() {
    super.initState();
    _listDisposable =
        widget.store.addListener(this).andThen(() => _listDisposable = null);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listDisposable?.call();
    _listDisposable =
        widget.store.addListener(this).andThen(() => _listDisposable = null);
  }

  @override
  void dispose() {
    _listDisposable?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
        key: _listKey,
        initialItemCount: widget.store.sections.length,
        itemBuilder: (context, index, animation) {
          return FadeTransition(
              opacity: animation,
              child:
                  MessageSectionWidget(section: widget.store.sections[index]));
        });
  }

  @override
  inserted(int index) {
    _listKey.currentState?.insertItem(index);
  }

  @override
  removed(int index, MessageSection previous) {
    _listKey.currentState?.removeItem(
        index,
        (context, animation) => FadeTransition(
            opacity: animation,
            child: MessageSectionWidget(section: previous)));
  }
}

class ChatDetail extends StatelessWidget {
  final String chatId;

  const ChatDetail({Key key, @required this.chatId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: BackButton(),
          title: Text('chat detail'),
        ),
        backgroundColor: Color.lerp(Colors.white, Colors.black, 0.7),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: StreamBuilder<MessageStore>(
                  stream: context.messageStore,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return _MessageList(store: snapshot.data.get(chatId));
                    }
                    return Center(
                      child: Text(snapshot.error?.toString() ?? 'no data'),
                    );
                  })),
          EmojiInput(),
        ])));
  }
}

class MessageStore {
  final Account account;
  final RSocket rsocket;
  final Map<String, ChatMessageStore> _messages;
  StreamSubscription _remoteSubscription;
  StreamSubscription _dbSubscription;
  AccountPersistentStore _store;
  MessageStore({@required this.account, @required this.rsocket})
      : _messages = Map<String, ChatMessageStore>();

  Future<void> cancel() async {
    await _remoteSubscription?.cancel();
    await _dbSubscription?.cancel();
  }

  Future<void> start(Future<AccountPersistentStore> storeFuture) async {
    _store =
        await Future.any([storeFuture, Future.delayed(Duration(seconds: 1))]);
    if (_store == null) {
      if (kDebugMode) {
        throw 'Could not create account store';
      }
    }
    final latestMessage = await _store?.latestMessage();
    final latestMessageId = latestMessage?.id ?? Int64(-1);
    final messageStream = rsocket
        .requestStream('messages.stream'.asRoute((StreamMessages()
              ..fromMessageId = latestMessageId)
            .writeToBuffer()))
        .map<Message>((payload) => Message.fromBuffer(payload.data))
        .asBroadcastStream(onListen: (sub) => _remoteSubscription = sub);
    messageStream.listen((message) async {
      print('got message $message');
      get(message.chatId).append(message);
    });
    if (_store != null) {
      _dbSubscription = messageStream.listen((message) async {
        await _store.upsertMessage(message);
      });
    }
  }

  ChatMessageStore get(String chatId) {
    return _messages[chatId] ??=
        ChatMessageStore(chatId: chatId, store: _store);
  }

  static MessageStore instance;
}

extension on RSocketConn {
  MessageStore get messageStore =>
      MessageStore(account: account, rsocket: rsocket);
}

extension MessageStoreExt on BuildContext {
  static Stream<MessageStore> _stream;
  Stream<MessageStore> get messageStore {
    return _stream ??= accountStore.stream
        .rsockets(url: api.rsocketUrl)
        .transform(StreamTransformer<RSocketConn, MessageStore>.fromHandlers(
            handleData: (conn, sink) async {
      if (MessageStore.instance?.account == conn?.account) return;
      await MessageStore.instance?.cancel();
      final store = MessageStore.instance = conn?.messageStore;
      await store?.start(accountStore.stream.persistentStore
          .firstWhere((store) => store.account == conn.account));
      if (identical(store, MessageStore.instance)) {
        sink.add(store);
      }
    })).asBroadcastStream();
  }

  Stream<ChatMessageStore> chatMessages(String chatId) {
    return messageStore.map((messageStore) => messageStore?.get(chatId));
  }
}

class MessageSection with ChangeNotifier {
  List<Message> messages = [];
  bool prepend(Message message) {
    if (messages.isEmpty) {
      messages.add(message);
      notifyListeners();
      return true;
    }
    final first = messages.first;
    if (first.senderId != message.senderId) {
      return false;
    }
    if (first.timestamp - message.timestamp > 30) {
      return false;
    }
    messages.insert(0, message);
    notifyListeners();
    return true;
  }

  bool append(Message message) {
    if (messages.isEmpty) {
      messages.add(message);
      notifyListeners();
      return true;
    }
    final last = messages.last;
    if (last.senderId != message.senderId) {
      return false;
    }
    if (message.timestamp - last.timestamp > 30) {
      return false;
    }
    messages.add(message);
    notifyListeners();
    return true;
  }
}

class ChatMessageStore {
  final String chatId;
  final AccountPersistentStore store;
  List<MessageSection> sections = [];
  ListChanged<MessageSection> _listener;
  bool _sawStart = false;
  Future<void> _loadMoreFuture;

  ChatMessageStore({@required this.chatId, @required this.store})
      : _listener = ListChanged.empty<MessageSection>();

  VoidCallback addListener(ListChanged l) {
    _listener += l;
    return () => _listener -= l;
  }

  append(Message message) {
    if (sections.lastOrNull?.append(message) == true) {
      return;
    }
    final section = MessageSection();
    section.append(message);
    sections.add(section);
    _listener?.inserted(sections.length - 1);
  }

  loadMoreHistory() async {
    if (_sawStart) return;
    if (_loadMoreFuture != null) {
      return await _loadMoreFuture;
    }
    Completer<void> completer = Completer<void>();
    _loadMoreFuture = completer.future;
    try {
      final firstMessageId = sections.firstOrNull?.messages?.firstOrNull?.id;
      final messages = await store?.loadMessagesBefore(
            chatId: chatId,
            messageId: firstMessageId,
            limit: 100,
          ) ??
          [];
      var newSectionCount = 0;
      for (final message in messages.reversed) {
        if (sections.firstOrNull?.prepend(message) == true) continue;
        final section = MessageSection();
        section.prepend(message);
        sections.insert(0, section);
        newSectionCount++;
      }
      if (_listener != null)
        for (final index in Iterable<int>.generate(newSectionCount)) {
          _listener.inserted(index);
        }
    } catch (e) {
      completer.completeError(e);
      throw e;
    } finally {
      _loadMoreFuture = null;
    }
  }
}
