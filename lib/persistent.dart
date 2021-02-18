import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:ping_fe/account.dart';
import 'package:ping_fe/api.dart';
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

extension on Account {
  Future<AccountPersistentStore> get persistentStore async {
    final db =
        await openDatabase(join(await getDatabasesPath(), '$username.db'),
            onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE messages(id INTEGER PRIMARY KEY, sender TEXT, content TEXT, chat_id TEXT, timestamp INTEGER)',
      );
      await db.execute(
          'CREATE INDEX messages_timestamp_idx on messages(timestamp)');
      await db.execute(
          'CREATE INDEX messages_chat_id_timestamp_idx on messages(chat_id, timestamp)');
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
      final newStore = await account.persistentStore;
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
  decode(Map<String, dynamic> map) {}

  @override
  Map<String, dynamic> encode(value) {}
}

extension AccountPersistentStoreOps on AccountPersistentStore {
  Future<void> upsertMessage(Message value,
      {Encoder<Message> encoder: const MessageCodec()}) {
    return db.insert('messages', encoder.encode(value),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<Message> latestMessage() async {
    
  }
}
