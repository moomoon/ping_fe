import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:device_info/device_info.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'drop_down_rr_border.dart';
import 'emoji_store.dart';
import 'fade_button.dart';
import 'noto_emojis.dart';
import 'row_snapping_phisics.dart';
import 'shake.dart';
import 'shortcut_bar.dart';
import 'package:vibration/vibration.dart';
import './base_emoji.dart';
import './emoji_list.dart';
import '../foundation.dart';
import 'gesture_detector.dart';

typedef Compatible = bool Function(Emoji emoji, String systemVersion);

class EmojiDataSource {
  Stream<List<Emoji>> get latest => null;
  Future<List<MapEntry<EmojiCategory, List<Emoji>>>> get emojis => null;

  factory EmojiDataSource.shared() => const _EmojiDataSource();
}

class _EmojiDataSource implements EmojiDataSource {
  const _EmojiDataSource();
  @override
  Future<List<MapEntry<EmojiCategory, List<Emoji>>>> get emojis async {
    final _deviceInfoPlugin = DeviceInfoPlugin();

    Compatible isCompatible;
    String systemVersion;
    // final notoC = noto_emojis.values
    //     .expand((e) => e)
    //     .expand((e) => [e, ...e.diversityChildren])
    //     .length;
    // final c = emojiList.map((e) => [e, ...e.diversityChildren]).length;
    // print('c = $c, notoC = $notoC');
    //
    if (kIsWeb) {
      isCompatible = (_, __) => true;
    } else {
      if (Platform.isAndroid) {
        return noto_emojis.entries.toList();
      } else if (Platform.isIOS) {
        systemVersion ??= (await _deviceInfoPlugin.iosInfo).systemVersion;
        isCompatible = Emoji.isIOSCompatible;
      } else {
        isCompatible = (_, __) => true;
      }
    }

    return EmojiCategory.values
        .map((cat) => MapEntry(
            cat,
            emojiList
                .where((emoji) => emoji.category == cat)
                // .where((emoji) => isCompatible(emoji, systemVersion))
                // .map((emoji) => emoji.copyWith(
                //     diversityChildren: emoji.diversityChildren
                //         .where((e) => isCompatible(e, systemVersion))
                //         .toList()))
                .toList()))
        .toList();
  }

  @override
  Stream<List<Emoji>> get latest async* {
    yield [];
  }
}

class EmojiKeyboard extends StatefulWidget {
  final int column;
  final bool collapsed;

  const EmojiKeyboard({
    Key key,
    this.column: 7,
    @required this.collapsed,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return EmojiKeyboardState();
  }
}

class EmojiKeyboardState extends State<EmojiKeyboard> {
  final GlobalKey<ShortcutBarState> shortcutKey = GlobalKey();
  final GlobalKey<EmojiPanelState> emojiPanelKey = GlobalKey();
  bool shortcutTriggeredAction = false;

  Widget build(BuildContext context) {
    return SizedBox(
      height: 264,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            // const EmojiActionRow(),
            Expanded(
              child: FutureBuilder<List<MapEntry<EmojiCategory, List<Emoji>>>>(
                initialData: [],
                future: context.dataSource.emojis,
                builder: (context, snapshot) => EmojiPanel(
                  key: emojiPanelKey,
                  emojis: snapshot.data ?? [],
                  columns: widget.column,
                  onScroll: (controller) {
                    if (shortcutTriggeredAction == true) return;
                    final shortcut = shortcutKey.currentState;
                    if (shortcut?.scrolling != false) return;
                    final cat = emojiPanelKey.currentState?.category;
                    if (cat == null) return;
                    shortcut.selected = cat;
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            FutureBuilder<List<MapEntry<EmojiCategory, List<Emoji>>>>(
              initialData: [],
              future: context.dataSource.emojis,
              builder: (context, snapshot) {
                Widget content = ShortcutBar<EmojiCategory>(
                  key: shortcutKey,
                  shortcuts: snapshot.data?.map((e) => e.key)?.toList() ?? [],
                  selected: snapshot.data?.isEmpty == false
                      ? snapshot.data[0].key
                      : null,
                  builder: (context, t) {
                    return Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        t.icon,
                        size: 18,
                        color: Colors.white.withAlpha(200),
                      ),
                    );
                  },
                  dimmedBuilder: (context, t) {
                    return Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        t.dimmedIcon,
                        size: 18,
                        color: Colors.white.withAlpha(80),
                      ),
                    );
                  },
                );
                content = Row(
                  children: [
                    SpacebarButton(),
                    Expanded(child: content),
                    FadeButton(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.backspace_outlined,
                        size: 18,
                        color: Colors.white.withAlpha(200),
                      ),
                      onPressed: () {
                        ValueNotification(BackspaceEvent()).dispatch(context);
                      },
                    ),
                  ],
                );
                content = content
                    .onNotification<SelectionChanged<EmojiCategory>>((n) {
                  () async {
                    shortcutTriggeredAction = true;
                    if (n.scolling) {
                      await emojiPanelKey.currentState?.jumpToCategory(n.value);
                    } else {
                      await emojiPanelKey.currentState
                          ?.scrollToCategory(n.value);
                    }
                    shortcutTriggeredAction = false;
                  }();
                  return true;
                });
                content = Container(
                  child: content,
                  // color: Color.lerp(Colors.white, Colors.black, 0.762),
                );
                return content;
              },
            ),
          ],
        ),
      ),
    ).inheritingDefaultSlot(widget);
  }
}

class EmojiInputEvent {
  final Emoji emoji;
  final bool fromThrow;

  EmojiInputEvent(this.emoji, this.fromThrow);
}

class BackspaceEvent {}

class SpacebarEvent {}

class EnterEvent {}

class SpacebarButton extends StatefulWidget {
  @override
  State<SpacebarButton> createState() {
    return SpacebarButtonState();
  }
}

class SpacebarButtonState extends State<SpacebarButton> {
  MoveTracker _tracker;
  GlobalKey<VariationSelectorState> _variationKey = GlobalKey();
  VoidCallback removeOverlays;

  @override
  Widget build(BuildContext context) {
    _tracker?.close();
    _tracker = MoveTracker();
    return FadeButton(
      padding: EdgeInsets.all(8),
      child: Icon(
        Icons.space_bar,
        size: 18,
        color: Colors.white.withAlpha(200),
      ),
      onPressed: () {
        ValueNotification(SpacebarEvent()).dispatch(context);
      },
      onLongPressStart: (detail) {
        removeOverlays?.call();
        const offset = Offset(0, -4);
        final cover = context.showOverlay(
          position: OverlayPosition.fill,
          offset: offset,
          margin: const EdgeInsets.only(top: 4),
          builder: (_) => Container(
            decoration: ShapeDecoration(
                shape: DropdownRRBorder(lowerRadius: 4, upperRadius: 8),
                color: Color.lerp(Colors.white, Colors.black, 0.6)),
          ),
        );
        final variations = context.showOverlay(
          position: OverlayPosition.centerAbove,
          offset: offset,
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: -5),
          builder: (_) => Container(
            padding: EdgeInsets.all(8),
            decoration: ShapeDecoration(
              color: Color.lerp(Colors.white, Colors.black, 0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: VariationSelector(
              key: _variationKey,
              offset: _tracker.move.map((event) => event.globalPosition),
              selectedIndex: 0,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationZ(-pi / 4),
                    child: Icon(
                      Icons.call_missed,
                      size: 18,
                      color: Colors.white.withAlpha(200),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.space_bar_outlined,
                    size: 18,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        );
        removeOverlays = () {
          removeOverlays = null;
          cover.remove();
          variations.remove();
        };
      },
      onLongPressMoveUpdate: (detail) {
        _tracker.addMove(detail);
      },
      onLongPressEnd: (detail) {
        removeOverlays?.call();
        final index = _variationKey?.currentState?.selectedIndex ?? 1;
        if (index == 0) {
          ValueNotification(EnterEvent()).dispatch(context);
        } else {
          ValueNotification(SpacebarEvent()).dispatch(context);
        }
      },
    );
  }
}

extension on EmojiCategory {
  IconData get icon {
    switch (this) {
      case EmojiCategory.people:
        return Icons.emoji_emotions_rounded;
      case EmojiCategory.nature:
        return Icons.emoji_nature_rounded;
      case EmojiCategory.food:
        return Icons.emoji_food_beverage_rounded;
      case EmojiCategory.activity:
        return Icons.emoji_events_rounded;
      case EmojiCategory.travel:
        return Icons.emoji_transportation_rounded;
      case EmojiCategory.objects:
        return Icons.emoji_objects_rounded;
      case EmojiCategory.symbols:
        return Icons.emoji_symbols_rounded;
      case EmojiCategory.flags:
        return Icons.emoji_flags_rounded;
    }
  }

  IconData get dimmedIcon {
    switch (this) {
      case EmojiCategory.people:
        return Icons.emoji_emotions_outlined;
      case EmojiCategory.nature:
        return Icons.emoji_nature_outlined;
      case EmojiCategory.food:
        return Icons.emoji_food_beverage_outlined;
      case EmojiCategory.activity:
        return Icons.emoji_events_outlined;
      case EmojiCategory.travel:
        return Icons.emoji_transportation_outlined;
      case EmojiCategory.objects:
        return Icons.emoji_objects_outlined;
      case EmojiCategory.symbols:
        return Icons.emoji_symbols_outlined;
      case EmojiCategory.flags:
        return Icons.emoji_flags_outlined;
    }
  }
}

extension on BuildContext {
  int get column => peekInheritedDefaultSlot<EmojiKeyboard>().column;
  EmojiDataSource get dataSource => peekInherited();
}

class EmojiActionRow extends StatelessWidget {
  const EmojiActionRow({Key key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final column = context.column;
    return StreamBuilder<List<Emoji>>(
        stream: context.dataSource.latest.asyncMap((latest) async {
          if (latest.length >= column - 1) return latest;
          final emojis = await context.dataSource.emojis;
          final copy = [...latest];
          for (final cat in emojis) {
            for (final emoji in cat.value)
              if (!copy.contains(emoji)) {
                copy.add(emoji);
                if (copy.length >= column - 1) return copy;
              }
          }
          return copy;
        }),
        initialData: const [],
        builder: (context, snapshot) {
          return Row(
            children: [
              for (int index in Iterable.generate(column - 1))
                EmojiCell(tag: index, emoji: snapshot.data?.getOrNull(index)),
              const EmojiActionButton(),
            ],
          );
        }).inheritingDefaultSlot<EmojiCellBuilder>(buildEmojiCell);
  }

  Widget buildEmojiCell(BuildContext context, Object tag, Emoji emoji) {
    final index = tag is int ? tag : 0;
    final delay = Duration(milliseconds: index * 100);
    final duration = Duration(milliseconds: 400);
    final start = delay.inMicroseconds / duration.inMicroseconds;
    return AnimatedSwitcher(
      duration: delay + duration,
      switchInCurve:
          Interval(start, 1, curve: Interval(0.5, 1, curve: Curves.ease)),
      switchOutCurve:
          Interval(start, 1, curve: Interval(0, 1, curve: Curves.easeIn)),
      reverseDuration: delay + duration,
      transitionBuilder: (context, animation) => AnimatedBuilder(
        animation: animation,
        child: EmojiWidget(
          emoji: emoji,
        ),
        builder: (context, child) =>
            Transform.scale(scale: animation.value, child: child),
      ),
    );
  }
}

class EmojiWidget extends StatelessWidget {
  final Emoji emoji;

  const EmojiWidget({Key key, this.emoji}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Text(emoji?.text);
  }
}

class EmojiActionButton extends StatelessWidget {
  const EmojiActionButton({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final collapsed =
        context.dependOnInheritedDefaultSlot<EmojiKeyboard>().collapsed;
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 400),
      child: IconButton(
        icon: Icon(collapsed ? Icons.keyboard : Icons.keyboard_arrow_down),
        onPressed: () {
          EmojiActionButtonTapped(collapsed: collapsed).dispatch(context);
        },
      ),
    );
  }
}

class EmojiPanel extends StatefulWidget {
  final List<MapEntry<EmojiCategory, List<Emoji>>> emojis;
  final Function(ScrollController c) onScroll;
  final int columns;
  const EmojiPanel(
      {@required this.emojis, Key key, @required this.columns, this.onScroll})
      : super(key: key);
  @override
  State<StatefulWidget> createState() {
    return EmojiPanelState();
  }
}

class MoveTracker {
  StreamController<LongPressMoveUpdateDetails> _moveDetails =
      StreamController();
  Stream<LongPressMoveUpdateDetails> _move;

  Stream<LongPressMoveUpdateDetails> get move =>
      _move ??= _moveDetails.stream.asBroadcastStream();

  addMove(LongPressMoveUpdateDetails detail) {
    _moveDetails.add(detail);
  }

  close() {
    _moveDetails.close();
  }
}

class EmojiPanelState extends State<EmojiPanel> {
  static final lineHeight = 44.0;
  ScrollController controller = ScrollController();
  List<MapEntry<int, EmojiCategory>> offset;
  List<Emoji> emojis;
  VoidCallback _signalLoaded;
  VoidCallback _signalFired;
  @override
  void initState() {
    super.initState();
    controller.addListener(onScroll);
    emojis = widget.emojis.expand((element) => element.value).toList();
    int len = 0;
    offset = [];
    for (final emoji in widget.emojis) {
      offset.add(MapEntry(len, emoji.key));
      len += emoji.value.length;
    }
  }

  @override
  void didUpdateWidget(covariant EmojiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    emojis = widget.emojis.expand((element) => element.value).toList();
    int len = 0;
    offset = [];
    for (final emoji in widget.emojis) {
      offset.add(MapEntry(len, emoji.key));
      len += emoji.value.length;
    }
  }

  Future<void> scrollToCategory(EmojiCategory cat) async {
    final target = offset
        .firstWhere((entry) => entry.value == cat, orElse: () => null)
        ?.key;
    if (target == null) return;
    var pos = target.toDouble() ~/ widget.columns * lineHeight; // pos = 20;
    return controller.animateTo(pos,
        duration: const Duration(milliseconds: 200), curve: Curves.ease);
  }

  Future<void> jumpToCategory(EmojiCategory cat) async {
    final target = offset
        .firstWhere((entry) => entry.value == cat, orElse: () => null)
        ?.key;
    if (target == null) return;
    var pos = target.toDouble() ~/ widget.columns * lineHeight; // pos = 20;
    return controller.jumpTo(pos);
  }

  EmojiCategory get category => offset
      .lastWhere(
          (entry) =>
              controller.offset >= entry.key ~/ widget.columns * lineHeight,
          orElse: () => null)
      ?.value;

  GlobalKey<VariationSelectorState> _variationKey = GlobalKey();
  MoveTracker _tracker;

  VoidCallback removeOverlays;
  bool _handledByThrow = false;
  ShakeDetector _shakeDetector;

  @override
  Widget build(BuildContext context) {
    _tracker?.close();
    _tracker = MoveTracker();
    EmojiStore store = context.peekInheritedDefaultSlot();
    return GridView.builder(
      controller: controller,
      itemCount: emojis.length,
      physics: RowSnappingPhysics(rowHeight: lineHeight),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          mainAxisExtent: lineHeight, crossAxisCount: widget.columns),
      itemBuilder: (context, index) {
        final emoji = emojis[index];

        dispatchResult(bool fromThrow) {
          var selected = _variationKey?.currentState?.selectedIndex;
          if (selected != null) {
            store.variationStreamOf(emoji).value = selected;
          }
          selected ??= 0;
          if (selected >= 1 && selected <= emoji.diversityChildren.length) {
            ValueNotification(EmojiInputEvent(
                    emoji.diversityChildren[selected - 1], fromThrow))
                .dispatch(context);
          } else {
            ValueNotification(EmojiInputEvent(emoji, fromThrow))
                .dispatch(context);
          }
        }

        final textStyle = DefaultTextStyle.of(context).style.copyWith(
              fontSize: 32,
              fontFamilyFallback: (!kIsWeb && Platform.isAndroid)
                  ? <String>[
                      'NotoColorEmoji',
                    ]
                  : null,
            );
        return DefaultTextStyle(
          style: textStyle,
          child: Builder(
            builder: (context) => PatchedGestureDetector(
              behavior: HitTestBehavior.opaque,
              child: Container(
                  alignment: Alignment.center,
                  child: store == null
                      ? Text(emoji.text)
                      : StreamBuilder<Emoji>(
                          initialData: emoji,
                          stream: store
                              .variationStreamOf(emoji)
                              .stream
                              .map((event) {
                            if (event > 0 &&
                                event <= emoji.diversityChildren.length)
                              return emoji.diversityChildren[event - 1];
                            return emoji;
                          }),
                          builder: (context, snapshot) {
                            return Text((snapshot.data ?? emoji).text);
                          })),
              onLongPressStart: store == null
                  ? null
                  : (detail) {
                      if (_signalLoaded == null) {
                        () async {
                          final hasVibration = await Vibration.hasVibrator();
                          if (hasVibration != true) {
                            _signalLoaded = () {};
                            _signalFired = () {};
                            return;
                          }
                          final hasPattern =
                              await Vibration.hasCustomVibrationsSupport();
                          final hasAmplitude =
                              await Vibration.hasAmplitudeControl();
                          if (hasPattern == true) {
                            _signalLoaded = () => Vibration.vibrate(
                                pattern: [0, 8, 160, 8],
                                intensities: [100, 160]);
                            _signalFired = () => Vibration.vibrate(
                                pattern: [0, 8], intensities: [255]);
                          } else if (hasAmplitude == true) {
                            _signalLoaded = () async {
                              await Vibration.vibrate(amplitude: 100);
                              await Vibration.vibrate(amplitude: 160);
                            };
                            _signalFired =
                                () => Vibration.vibrate(amplitude: 255);
                          } else {
                            _signalLoaded = () async {
                              await Vibration.vibrate();
                              await Vibration.vibrate();
                            };
                            _signalFired = () => Vibration.vibrate();
                          }
                          _signalLoaded();
                        }();
                      } else {
                        _signalLoaded();
                      }
                      removeOverlays?.call();
                      _handledByThrow = false;
                      final cover = context.showOverlay(
                          position: OverlayPosition.fill,
                          margin: const EdgeInsets.only(top: 4),
                          builder: (_) => Padding(
                              padding: emoji.hasChildren
                                  ? const EdgeInsets.symmetric(horizontal: 4)
                                  : EdgeInsets.zero,
                              child: Container(
                                decoration: ShapeDecoration(
                                    shape: DropdownRRBorder(
                                        lowerRadius: 4,
                                        upperRadius: emoji.hasChildren ? 4 : 8),
                                    color: Color.lerp(
                                        Colors.white, Colors.black, 0.6)),
                              )));
                      final variations = context.showOverlay(
                        position: OverlayPosition.centerAbove,
                        margin: const EdgeInsets.only(
                            left: 8, right: 8, bottom: -5),
                        builder: (_) => DefaultTextStyle(
                          style: textStyle,
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: ShapeDecoration(
                              color:
                                  Color.lerp(Colors.white, Colors.black, 0.6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: VariationSelector(
                              key: _variationKey,
                              offset: _tracker.move
                                  .map((event) => event.globalPosition),
                              selectedIndex:
                                  store.variationStreamOf(emoji).value,
                              onSelectionChanged: (selected) {
                                final subject =
                                    context.peekInheritedDefaultSlot<
                                        BehaviorSubject<Emoji>>();
                                if (selected >= 1 &&
                                    selected <=
                                        emoji.diversityChildren.length) {
                                  subject.value =
                                      emoji.diversityChildren[selected - 1];
                                } else {
                                  subject.value = emoji;
                                }
                              },
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(emoji.text),
                                ),
                                for (final child in emoji.diversityChildren)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    child: Text(child.text),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                      _shakeDetector = ShakeDetector.autoStart(
                          shakeThresholdGravity: 1.6,
                          onPhoneShake: () {
                            _signalFired?.call();
                            _handledByThrow = true;
                            dispatchResult(true);
                          });
                      removeOverlays = () {
                        removeOverlays = null;
                        cover.remove();
                        variations.remove();
                      };
                    },
              onLongPressEnd: store == null
                  ? null
                  : (detail) {
                      context
                          .peekInheritedDefaultSlot<BehaviorSubject<Emoji>>()
                          .value = null;

                      removeOverlays?.call();
                      _shakeDetector?.stopListening();
                      _shakeDetector = null;
                      if (!_handledByThrow) dispatchResult(false);
                    },
              onLongPressMoveUpdate: store == null
                  ? null
                  : (detail) {
                      _tracker.addMove(detail);
                    },
              onTap: store == null
                  ? null
                  : () {
                      final selected = store.variationStreamOf(emoji).value;
                      if (selected >= 1 &&
                          selected <= emoji.diversityChildren.length) {
                        ValueNotification(EmojiInputEvent(
                                emoji.diversityChildren[selected - 1], false))
                            .dispatch(context);
                      } else {
                        ValueNotification(EmojiInputEvent(emoji, false))
                            .dispatch(context);
                      }
                    },
            ),
          ),
        );
      },
    );
  }

  onScroll() {
    widget.onScroll?.call(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class VariationSelector extends StatefulWidget {
  final List<Widget> children;
  final Stream<Offset> offset;
  final ValueChanged<int> onSelectionChanged;
  final int selectedIndex;

  const VariationSelector(
      {Key key,
      this.children,
      this.offset,
      this.selectedIndex,
      this.onSelectionChanged})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return VariationSelectorState();
  }
}

class VariationSelectorState extends State<VariationSelector> {
  List<GlobalKey> keys = [];
  int _selectedIndexValue;
  StreamController<int> _selectedIndex = StreamController();
  int get selectedIndex => _selectedIndexValue;
  set selectedIndex(int value) {
    if (value == _selectedIndexValue) return;
    _selectedIndexValue = value;
    _selectedIndex.add(value);
    widget.onSelectionChanged?.call(value);
  }

  Stream<int> _selectedIndexStream;
  Stream<int> get selectedIndexStream =>
      _selectedIndexStream ??= _selectedIndex.stream.asBroadcastStream();
  StreamSubscription _offsetSubscription;

  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(covariant VariationSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  sync() {
    keys = List.generate(widget.children.length, (index) => GlobalKey());
    _offsetSubscription?.cancel();
    _offsetSubscription = widget.offset.listen((offset) async {
      for (final entry in keys.asMap().entries) {
        final rect = await rectOf(key: entry.value);
        if (rect == null) continue;
        if (rect.left <= offset.dx && rect.right >= offset.dx) {
          selectedIndex = entry.key;
          break;
        }
      }
    });
    selectedIndex = widget.selectedIndex;
  }

  @override
  void dispose() {
    super.dispose();
    _offsetSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in widget.children.asMap().entries)
          StatefulBuilder(
            key: keys[entry.key],
            builder: (context, setState) => Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: StreamBuilder<bool>(
                    stream:
                        selectedIndexStream.map((event) => event == entry.key),
                    initialData: selectedIndex == entry.key,
                    builder: (context, snapshot) {
                      return Container(
                        decoration:
                            widget.children.length == 1 || snapshot.data != true
                                ? null
                                : ShapeDecoration(
                                    color: Colors.blue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(0),
                  child: entry.value,
                ),
              ],
            ),
          )
      ],
    );
  }
}

Future<Rect> rectOf({@required GlobalKey key}) async {
  int childCount = 0;
  RenderBox renderBox;
  Size childSize;
  while (((renderBox = key.currentContext?.findRenderObject()) == null ||
          (childSize = key.currentContext?.size) == null) &&
      childCount++ < 10) {
    await WidgetsBinding.instance.endOfFrame;
  }
  if (renderBox == null || childSize == null) {
    return null;
  }
  final topLeft = renderBox.localToGlobal(Offset.zero);
  return topLeft & childSize;
}

// class EmojiCategoryRow extends StatefulWidget {
//   const EmojiCategoryRow();

//   @override
//   State<StatefulWidget> createState() {
//     return EmojiCategoryRowState();
//   }
// }

// class EmojiCategoryRowState extends State<EmojiCategoryRow> {
//   @override
//   Widget build(BuildContext context) {

//   }
// }

// class Emoji {
//   final String text;
//   final List<Emoji> variations;

//   Emoji({@required this.text, this.variations: const []});
// }

// class EmojiCategory {
//   final String name;

//   EmojiCategory({@required this.name});
// }

class A extends PopupMenuEntry {
  @override
  State<StatefulWidget> createState() {
    return new AState();
  }

  @override
  double get height => 100;

  @override
  bool represents(value) {
    return false;
  }
}

class AState extends State<A> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Text('A'),
      onTapUp: (detail) {
        print('tap up');
      },
      onPanEnd: (detail) {
        print('pan end');
      },
    );
  }
}

class EmojiCell extends StatelessWidget {
  final Object tag;
  final Emoji emoji;

  const EmojiCell({Key key, @required this.tag, @required this.emoji})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final builder = context.peekInheritedDefaultSlot<EmojiCellBuilder>();
    Widget content = builder(context, tag, emoji);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      child: content,
      onTap: () {
        // context.showContextualMenu(items: [A()]);
      },
    );
    // return CupertinoButton(
    //   child: content,
    //   onPressed: emoji == null
    //       ? null
    //       : () {
    //           EmojiTapped(emoji: emoji).dispatch(context);
    //         },
    // );
  }
}

typedef Widget EmojiCellBuilder(BuildContext context, Object tag, Emoji moji);

class EmojiActionButtonTapped extends Notification {
  final bool collapsed;

  const EmojiActionButtonTapped({@required this.collapsed});
}

class EmojiTapped extends Notification {
  final Emoji emoji;

  EmojiTapped({@required this.emoji});
}
