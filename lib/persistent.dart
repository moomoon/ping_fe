import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/protos/chat.pb.dart';
import 'package:sqflite/sqflite.dart';

class AccountPersistentStore {
  final Account account;
  final Database db;
  bool _closing = false;
  bool get closing => _closing;

  AccountPersistentStore({@required this.account, @required this.db});

  close() async {
    if (closing) return;
    _closing = true;
    await db.close();
  }

  static AccountPersistentStore instance;
}

extension PersistencyExt on Account {
  Future<AccountPersistentStore> get newPersistentStore async {
    final db =
        await openDatabase(join(await getDatabasesPath(), '$username.db'),
            onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE messages(id INTEGER PRIMARY KEY, sender TEXT, content TEXT, chat_id TEXT, timestamp INTEGER, local_id INTEGER)',
      );
      await db.execute(
          'CREATE INDEX messages_chat_id_timestamp_idx on messages(chat_id, id)');
    }, version: 1);
    return AccountPersistentStore(account: this, db: db);
  }
}

extension AccountPersistentStoreExt on Stream<Account> {
  static Stream<AccountPersistentStore> _stream;
  Stream<AccountPersistentStore> get persistentStore async* {
    if (null != AccountPersistentStore.instance)
      yield AccountPersistentStore.instance;
    yield* _stream ??= transform(
        StreamTransformer<Account, AccountPersistentStore>.fromHandlers(
            handleData: (account, sink) async {
      if (account == AccountPersistentStore.instance?.account) return;
      await AccountPersistentStore.instance?.close();
      final oldStore = AccountPersistentStore.instance;
      final newStore = await account.newPersistentStore;
      if (identical(AccountPersistentStore.instance, oldStore)) {
        sink.add(AccountPersistentStore.instance = newStore);
      } else {
        await newStore.close();
      }
    })).asBroadcastStream();
  }
}

abstract class Encoder<T> {
  Map<String, dynamic> encode(T value);
}

abstract class Decoder<T> {
  T decode(Map<String, dynamic> map);
}

class MessageCodec with Encoder<Message>, Decoder<Message> {
  const MessageCodec();
  @override
  Message decode(Map<String, dynamic> map) {
    return Message()
      ..id = Int64(map['id'])
      ..chatId = map['chat_id']
      ..content = map['content']
      ..senderId = map['sender']
      ..localId = Int64(map['local_id']);
  }

  @override
  Map<String, dynamic> encode(Message value) {
    return {
      'id': value.id.toInt(),
      'chat_id': value.chatId,
      'content': value.content,
      'sender': value.senderId,
      'local_id': value.localId.toInt(),
    };
  }
}

extension AccountPersistentStoreOps on AccountPersistentStore {
  Future<void> upsertMessage(Message value,
      {Encoder<Message> encoder: const MessageCodec()}) {
    return db.insert('messages', encoder.encode(value),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Message> latestMessage(
      {Decoder<Message> decoder: const MessageCodec()}) async {
    final raw = await db.query('messages', orderBy: 'id desc', limit: 1);
    if (raw.isEmpty) return null;
    return decoder.decode(raw[0]);
  }

  Future<List<Message>> loadMessagesBefore(
      {String chatId,
      Int64 messageId,
      int limit: 100,
      Decoder<Message> decoder: const MessageCodec()}) async {
    print('loadMessages before $chatId, $messageId, $limit');
    String where = '';
    List whereArgs = [];
    if (chatId?.isNotEmpty == true) {
      where += 'chat_id = ?';
      whereArgs.add(chatId);
    }
    if (messageId >= 0) {
      if (where.isNotEmpty) where += ' and ';
      where += 'id < ?';
      whereArgs.add(messageId.toInt());
    }
    final raw = await db.query(
      'messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'id desc',
      limit: limit,
    );
    return raw.reversed.map(decoder.decode).toList();
  }
}
