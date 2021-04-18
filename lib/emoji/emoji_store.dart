import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../foundation.dart';

import 'base_emoji.dart';

class EmojiStore {
  final SharedPreferences sp;
  Map<Emoji, BehaviorSubject<int>> _variations = {};
  EmojiStore({@required this.sp});

  BehaviorSubject<int> variationStreamOf(Emoji emoji) {
    final key = '${emoji.name}_variation';
    return _variations.putIfAbsent(emoji, () {
      final subject = BehaviorSubject<int>();
      final index = sp.getInt(key) ?? 0;
      subject.value = index;
      subject.stream.listen((event) {
        sp.setInt(key, event);
      });
      return subject;
    });
  }

  static Completer<EmojiStore> _completer;
  static Future<EmojiStore> getInstance() async {
    if (_completer == null) {
      _completer = Completer<EmojiStore>();
      try {
        final sp = await SharedPreferences.getInstance();
        _completer.complete(EmojiStore(sp: sp));
      } on Exception catch (e) {
        _completer.completeError(e);
        final Future<EmojiStore> future = _completer.future;
        _completer = null;
        return future;
      }
    }
    return _completer.future;
  }
}
