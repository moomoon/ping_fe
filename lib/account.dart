import 'dart:async';
import 'package:path/path.dart';
import 'package:ping_fe/api.dart';
import 'package:sqflite/sqflite.dart';

import 'package:flutter/material.dart';

class Account {
  final String username;
  final String token;

  Account({this.username, this.token});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account && username == other.username;
  }

  @override
  int get hashCode => hashValues(Account, username);
}

class AccountStore {
  StreamController<Account> _streamController = StreamController<Account>();
  Stream<Account> _stream;
  Account _value;
  Account get value {
    return _value;
  }

  set value(Account account) {
    _value = account;
    _streamController.add(account);
  }

  Stream<Account> get stream async* {
    if (_value != null) yield _value;
    yield* (_stream ??= _streamController.stream.asBroadcastStream());
  }

  static AccountStore instance = AccountStore();
}

extension AccountExt on BuildContext {
  AccountStore get accountStore {
    return AccountStore.instance;
  }
}

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
        "CREATE TABLE messages(id INTEGER PRIMARY KEY, sender TEXT, content TEXT, chat_id TEXT, timestamp INTEGER)",
      );
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

extension AccountPersistentStoreOps on AccountPersistentStore {

}