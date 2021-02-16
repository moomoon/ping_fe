import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rsocket/metadata/composite_metadata.dart';
import 'package:rsocket/payload.dart';

class ValueNotification<T, Slot> extends Notification {
  final T value;

  ValueNotification(this.value);
}

class InheritedValue<T, Slot> extends InheritedWidget {
  final T value;

  InheritedValue({@required this.value, Key key, @required Widget child})
      : super(key: key, child: child);
  @override
  bool updateShouldNotify(InheritedValue<T, Slot> oldWidget) {
    return value != oldWidget.value;
  }
}

abstract class ValueRegistry<T> {
  register(T value);

  factory ValueRegistry.from(Function(T v) f) => _ValueRegistry(f);
}

class _ValueRegistry<T> implements ValueRegistry<T> {
  final Function(T v) f;

  _ValueRegistry(this.f);

  @override
  register(T value) {
    return this.f(value);
  }
}

extension Foundation on BuildContext {
  registerValue<T, Slot>(T value) {
    return peekInherited<ValueRegistry<T>, Slot>()?.register(value);
  }

  registerSingleTap(VoidCallback c) =>
      this.registerValue<VoidCallback, SingleTap>(c);

  T dependOnInherited<T, Slot>() {
    return dependOnInheritedWidgetOfExactType<InheritedValue<T, Slot>>()?.value;
  }

  T peekInherited<T, Slot>() {
    final widget =
        getElementForInheritedWidgetOfExactType<InheritedValue<T, Slot>>()
            ?.widget;
    if (null != widget) return (widget as InheritedValue<T, Slot>).value;
    return null;
  }
}

class SingleTap {}

extension Inheriting on Widget {
  Widget inheritingDefaultSlot<T>(T t) {
    return inheriting<T, dynamic>(t);
  }

  Widget inheriting<T, Slot>(T t) {
    return InheritedValue<T, Slot>(value: t, child: this);
  }

  Widget capture<T, Slot>(BuildContext context) {
    return inheriting<T, Slot>(context.dependOnInherited<T, Slot>());
  }

  Widget notify<T extends Notification>(BuildContext context) =>
      NotificationListener<T>(
          onNotification: (notification) {
            notification.dispatch(context);
            return true;
          },
          child: this);

  Widget valueRegistry<T, Slot>(f(T v)) =>
      this.inheriting<ValueRegistry<T>, Slot>(ValueRegistry.from(f));
  Widget singleTap(f(VoidCallback c)) =>
      this.valueRegistry<VoidCallback, SingleTap>(f);
}

class Var<T> {
  final T Function() _getter;
  final Function(T) _setter;

  T get value => _getter();
  set value(T v) => _setter(v);

  const Var({@required T get(), @required set(T)})
      : this._getter = get,
        this._setter = set;
}

class ShaderMaskCompat extends StatelessWidget {
  final ShaderCallback shaderCallback;
  final BlendMode blendMode;
  final Widget child;

  const ShaderMaskCompat(
      {Key key, @required this.shaderCallback, this.blendMode, this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    return ShaderMask(
      key: key,
      shaderCallback: shaderCallback,
      blendMode: blendMode,
      child: child,
    );
  }
}

class FadingEdges extends StatelessWidget {
  final Widget child;

  const FadingEdges({Key key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShaderMaskCompat(
      shaderCallback: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0, 0.05, 0.95, 1],
        colors: <Color>[
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent
        ],
      ).createShader,
      blendMode: BlendMode.modulate,
      child: child,
    );
  }
}

extension CollectionOps<E> on Iterable<E> {
  Iterable<T> scan<T>(T initial, T f(T last, E element)) =>
      _ScannedIterable<E, T>(this, initial, f);
}

class _ScannedIterable<E, T> extends Iterable<T> {
  final Iterable<E> _iterable;
  final T Function(T, E) _f;
  final T initial;

  factory _ScannedIterable(Iterable<E> iterable, T initial, T function(T, E)) {
    return _ScannedIterable<E, T>._(iterable, initial, function);
  }

  _ScannedIterable._(this._iterable, this.initial, this._f);

  Iterator<T> get iterator =>
      new _ScannedIterator<E, T>(_iterable.iterator, initial, _f);

  // Length related functions are independent of the mapping.
  int get length => _iterable.length + 1;
  bool get isEmpty => false;

  // Index based lookup can be done before transforming.
  T get first => initial;
}

class _ScannedIterator<E, T> implements Iterator<T> {
  final Iterator<E> _iterator;
  final T Function(T, E) _f;
  T _current;
  T get current => _current;
  bool _moved = false;

  _ScannedIterator(this._iterator, this._current, this._f);

  @override
  bool moveNext() {
    if (!_moved) {
      _moved = true;
      return true;
    }
    if (_iterator.moveNext()) {
      _current = _f(_current, _iterator.current);
    }
    return false;
  }
}

T identity<T>(T _) => _;

typedef T Decorator<T>(T _);

extension MapLoader<K, V> on Map<K, FutureOr<V>> {
  FutureOr<V> getOrLoad(K key, FutureOr<V> load()) async {
    FutureOr<V> current = this[key];
    if (null != current) return current;
    Completer<V> completer = Completer<V>();
    Future<V> future = completer.future;
    this[key] = future;
    try {
      V v = await load();
      completer.complete(v);
      this[key] = v;
    } catch (e) {
      completer.completeError(e);
      remove(key);
    }
    return future;
  }
}

extension LiveMapLoader<K, V> on Map<K, LiveObject<V>> {
  LiveObject<V> getLiveObject(K key, FutureOr<V> load()) =>
      putIfAbsent(key, () => LiveObject.fromLoader(load));
}

class _LiveObject<T> with LiveObject<T> {
  final FutureOr<T> Function() loader;
  final bool Function(T) _filter;

  _LiveObject(this.loader, this._filter);

  @override
  FutureOr<T> load() => loader();

  @override
  bool filter(T t) => _filter(t);
}

extension StreamExt<T> on Stream<T> {
  Stream<T> log(String tag) => map((event) {
        print("$tag $event");
        return event;
      });
}

abstract class LiveObject<T> {
  T _value;
  DateTime _lastUpdateTime;
  Future<T> _future;
  StreamController<T> _streamController = StreamController<T>();
  Stream<T> _stream;

  factory LiveObject.fromLoader(FutureOr<T> loader(),
          {bool Function(T) filter}) =>
      _LiveObject<T>(loader, filter ?? defaultFilter);

  static bool defaultFilter<T>(T t) => t != null;
  T get value => _value;
  set value(T v) {
    _value = v;
    _lastUpdateTime = DateTime.now();
    if (filter(v) == true) _streamController.add(v);
  }

  FutureOr<T> refresh({bool emitCurrent = false}) async {
    if (null != _future) return _future;
    if (null != _value && emitCurrent == true) {
      try {
        return _value;
      } finally {
        value = _value;
      }
    }
    Completer<T> completer = Completer<T>();
    _future = completer.future;
    try {
      final v = await load();
      completer.complete(v);
      value = v;
    } catch (e) {
      completer.completeError(e);
      _streamController.addError(e);
    } finally {
      _future = null;
    }
    return completer.future;
  }

  Stream<T> stream(
      {bool loadIfUnInitialized = true,
      bool yieldCurrent = true,
      Duration refreshIfOlderThan,
      bool log}) async* {
    if (yieldCurrent != true || (loadIfUnInitialized && value == null)) {
      refresh();
    } else if (null != refreshIfOlderThan &&
        (null == _lastUpdateTime ||
            DateTime.now().difference(_lastUpdateTime) >= refreshIfOlderThan)) {
      // delay error
      if (log == true) {
        print('delay refresh');
      }
      Future.delayed(Duration(milliseconds: 100), () async {
        await refresh();
        if (log == true) {
          print('after refresh');
        }
      });
    }
    if (yieldCurrent == true) {
      if (null != value) {
        if (log == true) {
          print('yielding initial value $value');
        }
        yield value;
      } else if (log == true) {
        print('no initial value');
      }
    }
    try {
      yield* (_stream ??= _streamController.stream.asBroadcastStream());
    } catch (e) {
      if (log == true) {
        print('got error $e');
      }
      throw e;
    }
  }

  FutureOr<T> load();
  bool filter(T t);
}

mixin ListStore<T> {
  List<T> __value;
  StreamController<List<T>> _streamController = StreamController<List<T>>();

  Stream<List<T>> _stream;
  Completer<void> _refreshTask;
  Completer<void> _appendTask;
  bool _sawEnd = false;

  List<T> get value => __value;

  set _value(List<T> v) {
    __value = v;
    _streamController.add(v);
  }

  modify(List<T> block(List<T> value)) {
    _value = block(value);
  }

  Stream<List<T>> get stream async* {
    if (value != null) yield value;
    if (null == _stream) {
      _stream = _streamController.stream.asBroadcastStream();
    }
    yield* _stream;
  }

  FutureOr<List<T>> fullRefresh();

  clear() {
    _value = null;
    _refreshTask = null;
    _appendTask = null;
    _sawEnd = false;
  }

  close() => _streamController.close();

  Future<void> refresh() async {
    if (_refreshTask != null) return _refreshTask.future;
    _sawEnd = false;
    _appendTask?.complete();
    _appendTask = null;
    _refreshTask = Completer<void>();
    final future = _refreshTask.future;
    try {
      final v = await fullRefresh();
      _value = v;
      _refreshTask.complete();
    } catch (e) {
      _refreshTask.completeError(e);
    } finally {
      _refreshTask = null;
    }
    return future;
  }
}

mixin DEListStore<T> on ListStore<T> {
  Set<Object> _ids;

  FutureOr<List<T>> loadMore();
  Object id(T v);

  set _value(List<T> v) {
    _ids = v?.map(id)?.toSet();
    super._value = v;
  }

  Future<void> append() async {
    if (_sawEnd == true) return;
    if (_refreshTask != null) return _refreshTask.future;
    if (_appendTask != null) return _appendTask.future;
    final appendTask = Completer<void>();
    _appendTask = appendTask;
    try {
      final v = await loadMore();
      if (identical(_appendTask, appendTask)) {
        if (v?.isEmpty == true) {
          _sawEnd = true;
        }
        if (v?.isNotEmpty == true) {
          if (null != _ids) {
            v.retainWhere((e) => !_ids.contains(id(e)));
          }
          _value = [...?value, ...?v];
        }
        _appendTask.complete();
        _appendTask = null;
      }
    } catch (e) {
      if (identical(_appendTask, appendTask)) {
        _appendTask.completeError(e);
        _appendTask = null;
      }
    }
  }
}

extension BottomSheetExtension on Widget {
  Future<T> modalBottomSheet<T>(BuildContext context,
      {bool isScrollControlled = false,
      Color backgroundColor,
      bool useRootNavigator = false}) {
    final builder = keyboardInset(child: this).build;
    return showModalBottomSheet(
        useRootNavigator: useRootNavigator,
        context: context,
        isScrollControlled: isScrollControlled,
        backgroundColor: backgroundColor,
        builder: (innerContext) => InheritedValue<BuildContext, BottomSheet>(
            value: context, child: builder(innerContext)));
  }
}

Builder keyboardInset({@required Widget child}) => Builder(
      builder: (context) => SafeArea(
        child: Padding(
            padding: EdgeInsets.only(
                bottom: max(0, MediaQuery.of(context).viewInsets.bottom)),
            child: child),
      ),
    );

class StatefulAsyncWidgetBuilder<T> {
  final Widget Function(BuildContext context, AsyncSnapshot<T> oldSnapshot,
      AsyncSnapshot<T> snapshot) builder;
  final bool Function(AsyncSnapshot<T> snapshot) _shouldRetain;
  AsyncSnapshot<T> _retained;
  bool log;
  StatefulAsyncWidgetBuilder(this.builder,
      {bool shouldRetain(AsyncSnapshot<T> snapshot), this.log})
      : this._shouldRetain = shouldRetain ?? defaultShouldRetain;

  Widget call(BuildContext context, AsyncSnapshot<T> snapshot) {
    if (log == true) {
      print('calling with $snapshot, $_retained');
    }
    Widget widget = builder(context, _retained, snapshot);
    if (_shouldRetain(snapshot)) {
      _retained = snapshot;
    }
    return widget;
  }

  static bool defaultShouldRetain<T>(AsyncSnapshot<T> snapshot) =>
      snapshot.data != null;
}

class SingleRowRichText extends StatelessWidget {
  final InlineSpan text;

  const SingleRowRichText({Key key, this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      Iterable<Widget> expand(InlineSpan span, [TextStyle style]) sync* {
        if (span is TextSpan) {
          final s = span.style ?? style;
          if (span.text != null) {
            yield Text(span.text, style: s);
          }
          if (span.children != null)
            for (final child in span.children) {
              yield* expand(child, s);
            }
        } else if (span is WidgetSpan) {
          assert(span.child != null);
          yield span.child;
        }
      }

      return Row(
        children: expand(text).toList(),
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        mainAxisSize: MainAxisSize.min,
      );
    } else {
      return RichText(
        textAlign: TextAlign.left,
        maxLines: 1,
        text: text,
        softWrap: false,
      );
    }
  }
}

extension Effects on Widget {
  Widget polyplopia(int count, {double offset = 6}) {
    assert(count > 0);
    if (count == 1) return this;
    int median = count ~/ 2;
    Widget padded = Container(
        padding: EdgeInsets.only(
            left: median * offset, right: (count - median - 1) * offset),
        child: this);
    Widget content = Stack(
      alignment: Alignment.center,
      children: [
        for (var i in Iterable.generate(count))
          if (i == median)
            padded
          else
            Positioned(left: i * offset, child: this),
      ],
    );
    return content;
  }

  Widget withBadge({Widget badge}) {
    badge ??= Positioned(
        top: -4,
        right: -8,
        child: Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: Colors.red, shape: BoxShape.circle)));
    return Stack(
      overflow: Overflow.visible,
      fit: StackFit.passthrough,
      children: [
        this,
        badge is Positioned ? badge : Positioned(top: 0, right: 0, child: badge)
      ],
    );
  }

  Widget withBadgeState(BehaviorSubject<bool> state, {Widget badge}) {
    return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => state.value = false,
        child: StreamBuilder<bool>(
            stream: state.stream,
            initialData: state.value,
            builder: (context, snapshot) =>
                snapshot.data == true ? withBadge(badge: badge) : this));
  }
}

class Logo extends StatelessWidget {
  const Logo({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Image.asset('assets/icon.png');
}

class BehaviorSubject<T> {
  StreamController<T> __streamController;
  StreamController<T> get _streamController =>
      __streamController ??= StreamController<T>();
  Stream<T> _stream;
  T _value;
  T get value => _value;
  set value(T v) {
    _value = v;
    _streamController.add(v);
  }

  Stream<T> get stream async* {
    yield value;
    yield* _stream ??= _streamController.stream.asBroadcastStream();
  }

  dispose() {
    __streamController?.close();
  }
}

extension Behavior on BuildContext {
  BehaviorSubject<T> behaviorSubject<T>() =>
      dependOnInherited<BehaviorSubject<T>, dynamic>();

  behaviorStreamBuilder<T>(
          Widget builder(BuildContext context, AsyncSnapshot<T> snapshot)) =>
      StreamBuilder<T>(
        stream: behaviorSubject<T>().stream,
        builder: builder,
      );
}

extension Tap on BuildContext {
  @Deprecated(
      'broken if GestureDetector.excludeFromSemantics == true, which is the default behavior of FlatButton')
  tap() {
    if (ModalRoute.of(this)?.isCurrent != true) return;
    final renderObj = findRenderObject();
    if (renderObj is RenderBox) {
      final hitTestResult = BoxHitTestResult();
      final result = renderObj.hitTest(hitTestResult,
          position: renderObj.size.center(Offset.zero));
      if (result == true) {
        for (final entry in hitTestResult.path)
          if (entry.target is RenderSemanticsGestureHandler) {
            (entry.target as RenderSemanticsGestureHandler).onTap();
            break;
          }
      }
    }
  }
}

extension MultiMap<K, V> on Map<K, List<V>> {
  add(K key, V v) =>
      update(key, (value) => <V>[...?value, v], ifAbsent: () => [v]);
}

class PointerKey<T> extends LocalKey {
  const PointerKey(this.value);
  final T value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is PointerKey<T> && identical(other.value, value);
  }

  @override
  int get hashCode => hashValues(runtimeType, value);

  @override
  String toString() {
    final String valueString = T == String ? "<'$value'>" : '<$value>';
    return '[$T $valueString]';
  }
}

VoidCallback debounce(
  VoidCallback callback, {
  Duration duration = const Duration(milliseconds: 100),
}) {
  var counter = 0;
  return () async {
    counter++;
    await Future.delayed(duration);
    counter--;
    if (counter == 0) callback();
  };
}

extension Disposable on Listenable {
  VoidCallback addListenerDisposable(VoidCallback listener) {
    addListener(listener);
    return () {
      removeListener(listener);
    };
  }
}

extension PublishValue<T> on ValueNotifier<T> {
  VoidCallback publishTo(BehaviorSubject<T> subject) {
    subject.value = value;
    return addListenerDisposable(() {
      subject.value = value;
    });
  }
}

Future<T> retry<T>(int times, Future<T> run()) async {
  dynamic _e;
  for (final _ in Iterable.generate(times))
    try {
      return await run();
    } catch (e) {
      _e = e;
    }
  throw _e ?? 'empty error';
}

extension ListenableStatefulBuilderExtension<T extends Listenable> on T {
  Widget buildStatefully(Widget builder(BuildContext contex), {Key key}) =>
      ListenableStatefulBuilder(key: key, builder: builder, listenable: this);
}

class ListenableStatefulBuilder<T extends Listenable> extends StatefulWidget {
  final Widget Function(BuildContext) builder;
  final T listenable;

  const ListenableStatefulBuilder({Key key, this.builder, this.listenable})
      : super(key: key);
  @override
  State<StatefulWidget> createState() {
    return ListenableState();
  }
}

class ListenableState<T extends Listenable>
    extends State<ListenableStatefulBuilder<T>> {
  VoidCallback disposable;
  @override
  void initState() {
    super.initState();
    disposable = widget.listenable.addListenerDisposable(() => setState(() {}));
  }

  @override
  void didUpdateWidget(ListenableStatefulBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    disposable?.call();
    disposable = widget.listenable.addListenerDisposable(() => setState(() {}));
  }

  @override
  void dispose() {
    super.dispose();
    disposable?.call();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}

A Function(B) lazy<A, B>(A f(B b)) {
  bool invoked = false;
  A value;
  return (b) {
    if (invoked) return value;
    invoked = true;
    value = f(b);
    return value;
  };
}

class _Memoization<A, B> {
  final Duration ttl;
  final FutureOr<B> Function(A v) f;
  final Map<A, FutureOr<B>> cache = Map();

  _Memoization({this.ttl, this.f});

  FutureOr<B> call(A v) async {
    if (cache.containsKey(v)) {
      return await cache[v];
    }
    final future = f(v);
    cache[v] = future;
    final result = await future;
    if (ttl != null) {
      Future.delayed(ttl).then((_) => cache.remove(v));
    }
    return result;
  }
}

extension Memoization<A, B> on FutureOr<B> Function(A v) {
  LiveObject<B> Function(A v) memoized() {
    Map<A, LiveObject<B>> cache = {};
    return (a) => cache.getLiveObject(a, () => this(a));
  }
}

extension IdentityRoute on RouteInformationParser {
  static RouteInformationParser<RouteInformation> get identity =>
      const _IdentityRouteInformationParser();
}

class _IdentityRouteInformationParser
    extends RouteInformationParser<RouteInformation> {
  const _IdentityRouteInformationParser() : super();
  @override
  Future<RouteInformation> parseRouteInformation(
          RouteInformation routeInformation) =>
      Future.value(routeInformation);

  @override
  RouteInformation restoreRouteInformation(RouteInformation configuration) =>
      configuration;
}

extension StreamOps<T> on Stream<T> {
  Stream<R> scan<R>(R initial, R combine(R r, T t)) async* {
    yield initial;
    R sum = initial;
    yield* map<R>((element) {
      sum = combine(sum, element);
      return sum;
    });
  }
}

abstract class ListChanged<E> {
  inserted(int index);
  removed(int index, E previous);

  ListChanged<E> operator +(ListChanged<E> another) {
    return DelegatedListChanged(another, this);
  }

  ListChanged<E> operator -(ListChanged<E> e) {
    if (identical(this, e)) return null;
    return this;
  }

  static ListChanged<E> empty<E>() => _EmptyListener<E>();
}

class _EmptyListener<E> implements ListChanged<E> {
  const _EmptyListener();
  @override
  ListChanged<E> operator +(ListChanged<E> another) {
    return another;
  }

  @override
  ListChanged<E> operator -(ListChanged<E> e) {
    return this;
  }

  @override
  inserted(int index) {}

  @override
  removed(int index, E previous) {}
}

class DelegatedListChanged<E> extends ListChanged<E> {
  final ListChanged prev;

  final ListChanged delegate;

  DelegatedListChanged(this.delegate, [this.prev]);
  @override
  inserted(int index) {
    prev?.inserted(index);
    delegate.inserted(index);
  }

  @override
  removed(int index, E previous) {
    prev?.removed(index, previous);
    delegate.removed(index, previous);
  }

  @override
  ListChanged<E> operator -(ListChanged<E> e) {
    if (identical(delegate, e)) return prev;
    final removeSuper = super - e;
    if (identical(removeSuper, prev)) return this;
    return DelegatedListChanged(delegate, removeSuper);
  }
}

extension IterableOps<E> on Iterable<E> {
  E get firstOrNull {
    return isEmpty ? null : first;
  }

  E get lastOrNull {
    return isEmpty ? null : last;
  }
}

extension RSocketStringExt on String {
  Payload asRoute([Uint8List data]) =>
      Payload.from(RoutingMetadata(this, []).content, data);
}

extension on ChangeNotifier {
  VoidCallback listenDisposable(VoidCallback listener) {
    addListener(listener);
    return () => removeListener(listener);
  }
}

mixin ExternalState<T extends StatefulWidget> on State<T> {
  ChangeNotifier get externalState;
  VoidCallback _disposable;

  @override
  void initState() {
    super.initState();
    _disposable = externalState.listenDisposable(() {
      setState(() {});
    }).andThen(() {
      _disposable = null;
    });
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _disposable?.call();
    _disposable = externalState.listenDisposable(() {
      setState(() {});
    }).andThen(() {
      _disposable = null;
    });
  }

  @override
  void dispose() {
    _disposable?.call();
    super.dispose();
  }
}

class ExternalStatefulBuilder<T extends ChangeNotifier> extends StatefulWidget {
  final T state;
  final Widget Function(BuildContext context, T state) builder;

  const ExternalStatefulBuilder(
      {Key key, @required this.state, @required this.builder})
      : super(key: key);
  @override
  State<StatefulWidget> createState() {
    return _ExternalStatefulBuilderState();
  }
}

class _ExternalStatefulBuilderState<T extends ChangeNotifier>
    extends State<ExternalStatefulBuilder<T>> with ExternalState {
  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.state);
  }

  @override
  ChangeNotifier get externalState => widget.state;
}

extension VoidCallbackExt on VoidCallback {
  VoidCallback andThen(VoidCallback next) => () {
        this();
        next();
      };
}
