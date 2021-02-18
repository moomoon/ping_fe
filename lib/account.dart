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
