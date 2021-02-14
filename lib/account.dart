import 'dart:async';

import 'package:flutter/material.dart';

class Account {
  final String username;
  final String token;

  Account({this.username, this.token});
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
