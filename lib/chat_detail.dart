import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
import 'package:ping_fe/foundation.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:rsocket/rsocket.dart';

class MessageStore {
  final Account account;
  final RSocket rsocket;
  final Map<String, ChatMessageStore> _messages;
  StreamSubscription _remoteSubscription;
  MessageStore({@required this.account, @required this.rsocket})
      : _messages = Map<String, ChatMessageStore>();

  Future<void> cancel() async {
    await _remoteSubscription?.cancel();
  }

  Future<void> start() async {
    final messages = await loadMessagesBefore(messageId: null, limit: 1);
    final latestMessageId = messages.firstOrNull?.id ?? Int64(-1);
    _remoteSubscription = rsocket
        .requestStream('messages.stream'.asRoute((StreamMessages()
              ..fromMessageId = latestMessageId)
            .writeToBuffer()))
        .map<Message>((payload) => Message.fromBuffer(payload.data))
        .listen((message) {
      get(message.chatId).append(message);
    });
  }

  ChatMessageStore get(String chatId) {
    return _messages[chatId] ??= ChatMessageStore(chatId: chatId);
  }

  static MessageStore instance;
}

extension on RSocketConn {
  MessageStore get messageStore =>
      MessageStore(account: account, rsocket: rsocket);
}

extension MessageStoreExt on Stream<RSocketConn> {
  static Stream<MessageStore> _stream;
  Stream<MessageStore> get messageStore {
    return _stream ??= transform(
        StreamTransformer<RSocketConn, MessageStore>.fromHandlers(
            handleData: (conn, sink) async {
      if (MessageStore.instance?.account == conn?.account) return;
      await MessageStore.instance?.cancel();
      final store = MessageStore.instance = conn?.messageStore;
      await store?.start();
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
    return false;
  }

  bool append(Message message) {
    return false;
  }
}

class ChatMessageStore {
  final String chatId;
  List<MessageSection> sections = [];
  ListChanged _listener;
  bool _sawStart = false;
  Future<void> _loadMoreFuture;

  ChatMessageStore({@required this.chatId});
  addListener(ListChanged l) {
    _listener += l;
  }

  removeListener(ListChanged l) {
    _listener -= l;
  }

  append(Message message) {
    if (sections.lastOrNull?.append(message) == true) return;
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
      final messages = await loadMessagesBefore(
        chatId: chatId,
        messageId: firstMessageId,
        limit: 100,
      );
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

Future<List<Message>> loadMessagesBefore(
    {String chatId, @required Int64 messageId, @required int limit}) {}
