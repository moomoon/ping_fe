import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/emoji/emoji_input.dart';
import 'package:ping_fe/emoji/widget_thrower.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/persistent.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:rsocket/rsocket.dart';

import 'emoji/base_emoji.dart';

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

class MessageWidget extends StatelessWidget {
  final MessageEntry message;

  const MessageWidget({Key key, @required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExternalStatefulBuilder<MessageEntry>(
        state: message,
        builder: (context, ChangeNotifier state) {
          MessageEntry entry = state;
          final text =
              entry.remoteMessage?.content ?? entry.localMessage?.content;
          if (text == null) return const SizedBox();
          Widget content = Text(text,
              style: TextStyle(
                fontSize: 28,
                fontFamilyFallback: (!kIsWeb && Platform.isAndroid)
                    ? <String>[
                        'NotoColorEmoji',
                      ]
                    : null,
              ));
          if (entry.remoteMessage == null) {
            content = Opacity(
              opacity: 0.6,
              child: content,
            );
          }
          return content;
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
    with ListChanged<MessageEntry> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  VoidCallback _listDisposable;
  VoidCallback _scrollControllerDisposable;
  @override
  void initState() {
    super.initState();
    _listDisposable =
        widget.store.addListener(this).andThen(() => _listDisposable = null);
    _scrollControllerDisposable = _scrollController.addListenerDisposable(() {
      if (_scrollController.offset <= 0) {
        widget.store.loadMoreHistory();
      }
    });
    widget.store.loadMoreHistory();
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
    _scrollControllerDisposable?.call();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
        controller: _scrollController,
        key: _listKey,
        initialItemCount: widget.store.messages.length,
        itemBuilder: (context, index, animation) {
          return FadeTransition(
              opacity: animation,
              child: MessageWidget(message: widget.store.messages[index]));
        });
  }

  @override
  inserted(int index) async {
    _listKey.currentState?.insertItem(index);
    if (widget.store.messages.length == index + 1) {
      await WidgetsBinding.instance.endOfFrame;
      _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.ease);
    }
  }

  @override
  removed(int index, MessageEntry previous) {
    _listKey.currentState?.removeItem(
        index,
        (context, animation) => FadeTransition(
            opacity: animation, child: MessageWidget(message: previous)));
  }
}

class ChatDetail extends StatefulWidget {
  final String chatId;

  const ChatDetail({Key key, @required this.chatId}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return ChatDetailState();
  }
}

class ChatDetailState extends State<ChatDetail> {
  BehaviorSubject<Emoji> throwingEmoji = BehaviorSubject();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Color.lerp(Colors.white, Colors.black, 0.9),
          leading: BackButton(),
          title: Text('chat detail'),
          actions: [
            WidgetThrower()
                .inheriting<Stream<Widget>, WidgetThrower>(throwingEmoji.stream
                    .map((event) => event == null
                        ? null
                        : Text(event.text,
                            style: TextStyle(
                              fontSize: 28,
                              fontFamilyFallback:
                                  (!kIsWeb && Platform.isAndroid)
                                      ? <String>[
                                          'NotoColorEmoji',
                                        ]
                                      : null,
                            )))
                    .asBroadcastStream())
          ],
        ),
        backgroundColor: Color.lerp(Colors.white, Colors.black, 0.8),
        body: StreamBuilder<MessageStore>(
            stream: context.messageStore,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                MessageStore store = snapshot.data;
                ChatMessageStore chatStore = store.get(widget.chatId);
                return SafeArea(
                    child: Column(children: [
                  Expanded(child: _MessageList(store: chatStore)),
                  EmojiInput().onValueNotification<String, EmojiInput>((n) {
                    () async {
                      MessageEntry entry = chatStore.appendLocal(
                          LocalMessage.from(
                              content: n, createdAt: DateTime.now()));
                      final message = await snapshot.data.rsocket
                          .requestResponse(
                              'messages.send'.asRoute((SendMessage()
                                    ..chatId = widget.chatId
                                    ..content = n
                                    ..localId = entry.localMessage.id)
                                  .writeToBuffer()))
                          .then((value) => Message.fromBuffer(value.data));
                      entry.updateRemote(message);
                    }();
                    return true;
                  }).inheritingDefaultSlot(throwingEmoji)
                ]));
              }
              return Center(
                child: Text(snapshot.error?.toString() ?? 'no data'),
              );
            }));
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
      get(message.chatId).appendRemote(message);
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
  Stream<MessageStore> get messageStore async* {
    if (MessageStore.instance != null) yield MessageStore.instance;
    yield* _stream ??= accountStore.stream
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

class MessageEntry extends ChangeNotifier {
  LocalMessage localMessage;
  Message remoteMessage;

  updateRemote(Message message) {
    this.remoteMessage = message;
    notifyListeners();
  }
}

class LocalMessage {
  final String content;
  final DateTime createdAt;
  final Int64 id;

  LocalMessage(
      {@required this.content, @required this.createdAt, @required this.id});

  factory LocalMessage.from({@required String content, @required createdAt}) {
    return LocalMessage(content: content, createdAt: createdAt, id: nextId);
  }

  static Int64 get nextId {
    return Int64(DateTime.now().millisecondsSinceEpoch);
  }
}

class ChatMessageStore {
  final String chatId;
  final AccountPersistentStore store;
  // List<MessageSection> sections = [];
  List<MessageEntry> messages = [];
  ListChanged<MessageEntry> _listener;
  Map<Int64, MessageEntry> localIdToMessage = {};
  bool _sawStart = false;
  Future<void> _loadMoreFuture;

  ChatMessageStore({@required this.chatId, @required this.store})
      : _listener = ListChanged.empty<MessageEntry>();

  VoidCallback addListener(ListChanged l) {
    _listener += l;
    messages.asMap().keys.forEach((i) {
      l.inserted(i);
    });
    return () => _listener -= l;
  }

  appendLocal(LocalMessage message) {
    final entry = MessageEntry()..localMessage = message;
    localIdToMessage[message.id] = entry;
    VoidCallback listener;
    listener = () {
      if (entry.remoteMessage != null) {
        entry.removeListener(listener);
      }
    };
    entry.addListener(listener);
    append(entry);
    return entry;
  }

  appendRemote(Message message) {
    if (localIdToMessage.containsKey(message.localId)) {
      localIdToMessage[message.localId].updateRemote(message);
    } else {
      final entry = MessageEntry()..remoteMessage = message;
      localIdToMessage[message.id] = entry;
      append(entry);
    }
  }

  append(MessageEntry message) {
    messages.add(message);
    // if (sections.lastOrNull?.append(message) == true) {
    //   return;
    // }
    // final section = MessageSection();
    // section.append(message);
    // sections.add(section);
    _listener?.inserted(messages.length - 1);
  }

  loadMoreHistory() async {
    if (_sawStart) return;
    if (_loadMoreFuture != null) {
      return await _loadMoreFuture;
    }
    Completer<void> completer = Completer<void>();
    _loadMoreFuture = completer.future;
    try {
      final firstMessageId = this
          .messages
          .map((e) => e.remoteMessage?.id)
          .firstWhere((e) => e != null, orElse: () => Int64(-1));
      final messages = await store?.loadMessagesBefore(
            chatId: chatId,
            messageId: firstMessageId,
            limit: 100,
          ) ??
          [];
      if (messages.isEmpty) _sawStart = true;
      this
          .messages
          .insertAll(0, messages.map((e) => MessageEntry()..remoteMessage = e));
      // var newSectionCount = 0;
      // for (final message in messages.reversed) {
      //   if (sections.firstOrNull?.prepend(message) == true) continue;
      //   final section = MessageSection();
      //   section.prepend(message);
      //   sections.insert(0, section);
      //   newSectionCount++;
      // }
      if (_listener != null)
        for (final index in Iterable<int>.generate(messages.length)) {
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
