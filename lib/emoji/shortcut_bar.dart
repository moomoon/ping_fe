import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../foundation.dart';

typedef Widget WidgetBuilder<T>(BuildContext context, T t);
typedef C FN<A, B, C>(A a, B b);

extension<A, B, C> on FN<A, B, C> {
  FN<A, B, D> andThen<D>(D f(C c)) => (a, b) => f(this(a, b));
}

class ShortcutBar<T> extends StatefulWidget {
  final List<T> shortcuts;
  final T selected;
  final WidgetBuilder<T> builder;
  final WidgetBuilder<T> dimmedBuilder;
  final WidgetBuilder<List<Widget>> layoutBuilder;
  final WidgetBuilder<List<Widget>> dimmedLayoutBuilder;

  ShortcutBar({
    Key key,
    this.selected,
    @required this.shortcuts,
    @required this.builder,
    WidgetBuilder<T> dimmedBuilder,
    WidgetBuilder<List<Widget>> layoutBuilder,
    WidgetBuilder<List<Widget>> dimmedLayoutBuilder,
  })  : this.dimmedBuilder = dimmedBuilder ??
            builder.andThen((c) => Opacity(opacity: 0.5, child: c)),
        this.layoutBuilder = layoutBuilder ??
            ((context, children) => ShortcutLayout(
                  children: children,
                )),
        this.dimmedLayoutBuilder = dimmedLayoutBuilder ??
            ((context, children) => ShortcutLayoutDimmed(
                  children: children,
                )),
        super(key: key);

  @override
  State<StatefulWidget> createState() {
    return ShortcutBarState<T>();
  }
}

class ShortcutLayout extends StatelessWidget {
  final List<Widget> children;

  const ShortcutLayout({Key key, @required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.lerp(Colors.white, Colors.black, 0.6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: children,
      ),
    );
  }
}

class ShortcutLayoutDimmed extends StatelessWidget {
  final List<Widget> children;

  const ShortcutLayoutDimmed({Key key, @required this.children})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: children,
    );
  }
}

class ShortcutBarState<T> extends State<ShortcutBar<T>>
    with TickerProviderStateMixin {
  Tween<double> _left, _right;
  Map<T, State> _registry = {};
  T _selected;
  bool _scroll = false;
  AnimationController _controller;

  AnimationController get controller => _controller ??=
      AnimationController(duration: Duration(milliseconds: 200), vsync: this);

  Future<Rect> rectOf({@required T value}) async {
    int childCount = 0;
    RenderBox renderBox;
    Size childSize;
    while (
        ((renderBox = _registry[value]?.context?.findRenderObject()) == null ||
                (childSize = _registry[value]?.context?.size) == null) &&
            childCount++ < 10) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (renderBox == null || childSize == null) {
      return null;
    }
    BoxParentData parentData = renderBox.parentData;
    final left = parentData.offset.dx;
    final top = parentData.offset.dy;
    final width = childSize.width;
    final height = childSize.height;
    return Rect.fromLTWH(left, top, width, height);
  }

  T get selected => _selected;
  set selected(T value) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      select(value: value);
    });
  }

  bool get scrolling => _scroll;

  Future<bool> select({T value, bool scroll, bool shouldNotify}) async {
    if (value != null && value != _selected) {
      _selected = value;
      if (shouldNotify == true) {
        SelectionChanged(value, scroll != null ? scroll : (_scroll == true))
            .dispatch(context);
      }
    } else if (_scroll == (scroll == true)) {
      return true;
    }
    if (_scroll && scroll != false) {
      return true;
    }
    int parentCount = 0;
    Size parentSize;
    while ((parentSize = context?.size) == null && parentCount++ < 10) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (parentSize == null) {
      return false;
    }
    animateTo(double left, double right) {
      setState(() {
        _left = Tween(begin: _left?.evaluate(controller) ?? left, end: left);
        _right =
            Tween(begin: _right?.evaluate(controller) ?? right, end: right);
      });
    }

    if (!_scroll && scroll == true) {
      final left = 0.0;
      final right = parentSize.width;
      _scroll = true;
      animateTo(left, right);
      return true;
    }
    _scroll = false;
    final childRect = await rectOf(value: _selected);
    if (childRect == null) return false;
    animateTo(childRect.left, childRect.right);
    return true;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> selectOffset(Offset offset) async {
    for (final s in widget.shortcuts) {
      final rect = await rectOf(value: s);
      if (rect?.contains(offset) != true) continue;
      select(value: s, shouldNotify: true);
      return true;
    }
    return false;
  }

  @override
  initState() {
    super.initState();
    if (widget.selected != null) {
      selected = widget.selected;
    }
  }

  @override
  void didUpdateWidget(covariant ShortcutBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != null) {
      selected = widget.selected;
    }
  }

  @override
  Widget build(BuildContext context) {
    controller
      ..reset()
      ..forward();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (detail) {
        select(scroll: true);
      },
      onPanUpdate: (detail) {
        selectOffset(detail.localPosition);
      },
      onPanEnd: (detail) {
        select(scroll: false);
      },
      // onLongPressStart: (detail) {
      //   select(scroll: true);
      // },
      // onLongPressMoveUpdate: (detail) {
      //   selectOffset(detail.localPosition);
      // },
      // onLongPressEnd: (detail) {
      //   select(scroll: false);
      // },
      onTapDown: (detail) async {
        selectOffset(detail.localPosition);
      },
      child: Stack(
        children: [
          widget.dimmedLayoutBuilder(context, [
            for (T t in widget.shortcuts)
              _Tag(
                tag: t,
                child: widget.dimmedBuilder(
                  context,
                  t,
                ),
              ),
          ]),
          ClipRRect(
            child: widget.layoutBuilder(context, [
              for (T t in widget.shortcuts) widget.builder(context, t),
            ]),
            clipper: _controller.customClipper((animation, size) {
              final left = _left?.evaluate(animation) ?? 0;
              final right = _right?.evaluate(animation) ?? 0;
              return RRect.fromLTRBR(left, 0, right, size.height,
                  Radius.circular(size.height / 2));
            }),
          ),
        ],
      ),
    ).inheritingDefaultSlot(this);
  }

  VoidCallback register(T t, State state) {
    _registry[t] = state;
    return () => unregister(t, state);
  }

  unregister(T t, State state) {
    if (_registry[t] == state) {
      _registry.remove(t);
    }
  }
}

class _Tag<T> extends StatefulWidget {
  final T tag;
  final Widget child;

  const _Tag({Key key, @required this.tag, @required this.child})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _TagState<T>();
  }
}

class _TagState<T> extends State<_Tag<T>> {
  VoidCallback unregister;
  @override
  void initState() {
    super.initState();
    unregister = context
        .peekInheritedDefaultSlot<ShortcutBarState<T>>()
        .register(widget.tag, this);
  }

  @override
  void didUpdateWidget(covariant _Tag<T> oldWidget) {
    unregister?.call();
    super.didUpdateWidget(oldWidget);
    context
        .peekInheritedDefaultSlot<ShortcutBarState<T>>()
        .register(widget.tag, this);
  }

  @override
  void dispose() {
    unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class SelectionChanged<T> extends Notification {
  final T value;
  final bool scolling;

  SelectionChanged(this.value, this.scolling);
}

extension on Animation<double> {
  CustomClipper<T> customClipper<T>(
      T clipper(Animation<double> animation, Size size)) {
    return _AnimatedCustomClipper(animation: this, clipper: clipper);
  }
}

class _AnimatedCustomClipper<T> extends CustomClipper<T> {
  final Animation<double> animation;
  final T Function(Animation<double> animation, Size size) clipper;

  _AnimatedCustomClipper({this.clipper, this.animation})
      : super(reclip: animation);
  @override
  T getClip(Size size) {
    return clipper(animation, size);
  }

  @override
  bool shouldReclip(covariant CustomClipper<T> oldClipper) {
    return true;
  }
}
