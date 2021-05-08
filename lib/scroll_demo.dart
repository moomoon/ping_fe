import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ping_fe/foundation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

enum TransitionState { initial, normal, deleting }

class StateOf<T> extends ChangeNotifier {
  T _state;
  final bool Function(T l, T r) accept;
  StateOf(T initial, {bool Function(T l, T r) accept})
      : this._state = initial,
        this.accept = accept ?? ((l, r) => true);

  T get state => _state;
  set state(T value) {
    if (accept(_state, value)) {
      _state = value;
      notifyListeners();
    }
  }
}

class TransitionWidget extends StatefulWidget {
  final Widget child;

  const TransitionWidget({Key key, @required this.child}) : super(key: key);
  @override
  State<StatefulWidget> createState() {
    return TransitionWidgetState();
  }
}

class TransitionWidgetState extends State<TransitionWidget> {
  StateOf<TransitionState> state;
  Completer<Null> _deleting;
  @override
  void initState() {
    super.initState();
    state = StateOf(TransitionState.initial,
        accept: (_old, _new) => _new.index > _old.index);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      state.state = TransitionState.normal;
    });
  }

  Future<Null> delete() {
    state.state = TransitionState.deleting;
    if (_deleting == null) {
      _deleting = Completer();
    }
    return _deleting.future;
  }

  @override
  Widget build(BuildContext context) {
    return ExternalStatefulBuilder(
        state: state,
        builder: (context, state) {
          if (state.state == TransitionState.deleting) {
            Future.delayed(const Duration(milliseconds: 201), () {
              if (_deleting.isCompleted == false) {
                _deleting.complete(null);
              }
            });
          }
          return AnimatedSwitcher(
            child: state.state == TransitionState.normal
                ? widget.child
                : const SizedBox(),
            duration: const Duration(milliseconds: 200),
          );
        });
  }
}

class PositionDemo extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return PositionState();
  }
}

class Transitioning<T> {
  GlobalKey<TransitionWidgetState> _key;
  GlobalKey<TransitionWidgetState> get key => _key ??= GlobalKey();
  final T value;
  Transitioning(this.value);

  Future<Null> delete() {
    if (_key?.currentState == null) {
      print('not displayed $value');
    }
    return _key?.currentState?.delete() ?? Future.sync(() => null);
  }
}

class PositionState extends State<PositionDemo> {
  List<Transitioning<String>> items = [];
  ItemScrollController c = ItemScrollController();

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
            onPressed: () async {
              int pos = Random.secure().nextInt(items.length + 1);
              final item =
                  Transitioning(Random.secure().nextInt(100).toString());
              setState(() {
                items.insert(pos, item);
              });
            },
            child: Text('add')),
        TextButton(
          onPressed: () async {
            if (items.isEmpty) return;
            final item = items[Random.secure().nextInt(items.length)];
            await item.delete();
            setState(() {
              items.remove(item);
            });
          },
          child: Text('remove'),
        ),
        TextButton(
          onPressed: () async {
            if (items.isEmpty) return;
            int p = Random.secure().nextInt(items.length);
            final item = items[p];
            print('scroll to $p, ${item.value}');
            c.scrollTo(index: p, duration: const Duration(milliseconds: 200));
          },
          child: Text('scroll'),
        ),
        Expanded(
            child: ListView.builder(
          physics: BouncingScrollPhysics(),
          // itemScrollController: c,
          shrinkWrap: true,
          itemCount: items.length,
          reverse: true,
          itemBuilder: (context, index) {
            final item = items[index];
            return TransitionWidget(
                child: Container(
                    margin: EdgeInsets.all(8),
                    padding: EdgeInsets.all(36),
                    color: Colors.amber,
                    child: Text(
                      item.value,
                      style: TextStyle(fontSize: 20),
                    )),
                key: item.key);
          },
        )),
      ],
    );
    return Scaffold(
        backgroundColor: Colors.white, body: Container(child: content));
  }
}
