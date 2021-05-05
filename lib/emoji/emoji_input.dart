import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fade_button.dart';
import 'base_emoji.dart';
import '../foundation.dart';
import 'emoji_keyboard.dart';
import 'emoji_store.dart';

class EmojiInput extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return EmojiInputState();
  }
}

class EmojiInputState extends State<EmojiInput> {
  TextEditingController _controller = TextEditingController();
  GlobalKey _textFieldKey = GlobalKey();
  FocusNode _focusNode = FocusNode();

  EmojiVibration vibration = EmojiVibration();
  VariationState variationState = VariationState();

  @override
  Widget build(BuildContext context) {
    BehaviorSubject<bool> collapsed =
        context.peekInherited<BehaviorSubject<bool>, EmojiCollapsed>();
    final collapsedWidget = CollapsedInput();
    final expandedWidget = buildExpanded(context);
    Widget content = StreamBuilder<bool>(
        stream: collapsed.stream.distinct().asBroadcastStream(),
        initialData: false,
        builder: (context, snapshot) {
          return AnimatedCrossFade(
              firstChild: collapsedWidget,
              secondChild: expandedWidget,
              crossFadeState: snapshot.data != true
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200));
        });
    final streamed = content;
    content = FutureBuilder<EmojiStore>(
      future: EmojiStore.getInstance(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return streamed.inheritingDefaultSlot(snapshot.data);
        } else {
          return streamed;
        }
      },
    );
    content = content
        .inheritingDefaultSlot(variationState..newTracker())
        .inheriting(vibration)
        .inheritingDefaultSlot(EmojiDataSource.shared())
        .onValueNotificationDefaultSlot<SpacebarEvent>((n) {
      _insertText(' ');
      _hideToolbar();
      return true;
    }).onValueNotificationDefaultSlot<EnterEvent>((n) {
      _insertText('\n');
      _hideToolbar();
      return true;
    }).onValueNotificationDefaultSlot<BackspaceEvent>((n) {
      _backspace();
      _hideToolbar();
      return true;
    }).onValueNotificationDefaultSlot<EmojiInputEvent>((n) {
      if (n.fromThrow) {
        ValueNotification<String, EmojiInput>(n.emoji.text).dispatch(context);
      } else {
        _insertText(n.emoji.text);
        _hideToolbar();
        collapsed.value = false;
      }
      return true;
    });
    return content;
  }

  Widget buildExpanded(BuildContext context) {
    BehaviorSubject<bool> collapsed =
        context.peekInherited<BehaviorSubject<bool>, EmojiCollapsed>();
    Widget content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          height: 0.5,
          color: Colors.white10,
        ),
        Container(
          color: Color.lerp(Colors.white, Colors.black, 0.85),
          padding: EdgeInsets.only(top: 8, right: 16, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FadeButton(
                  padding: EdgeInsets.only(left: 16, right: 12),
                  child: Icon(
                    Icons.keyboard_hide_outlined,
                    color: Colors.white.withAlpha(200),
                    size: 22,
                  ),
                  onPressed: () {
                    collapsed.value = true;
                  }),
              Expanded(
                child: Stack(
                  children: [
                    _AutofillGroup(
                      child: TextField(
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          fillColor:
                              Color.lerp(Colors.white, Colors.black, 0.8),
                          filled: true,
                          isDense: true,
                          focusColor: Colors.red,
                          border:
                              OutlineInputBorder(borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.only(
                            top: 4,
                            left: 4,
                            bottom: 4,
                            right: 40,
                          ),
                        ),
                        key: _textFieldKey,
                        controller: _controller,
                        autofillHints: ['dummy'],
                        minLines: 1,
                        style: TextStyle(
                          fontSize: 28,
                          fontFamilyFallback: (!kIsWeb && Platform.isAndroid)
                              ? <String>[
                                  'NotoColorEmoji',
                                ]
                              : null,
                        ),
                        maxLines: 4,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: FadeButton(
                        padding: EdgeInsets.zero,
                        child: Icon(
                          Icons.send,
                          color: Colors.white.withAlpha(200),
                          size: 18,
                        ),
                        onPressed: () {
                          if (_controller.text?.isNotEmpty == true) {
                            ValueNotification<String, EmojiInput>(
                                    _controller.text)
                                .dispatch(context);
                            _controller.text = '';
                          }
                        },
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 0.5,
          color: Colors.white10,
        ),
        const EmojiKeyboard(),
      ],
    );
    content = SafeArea(child: content);
    return content;
    // .inheritingDefaultSlot(emojis)
    // .inheriting<Stream<Widget>, WidgetThrower>(emojis.stream
    //     .map((event) => event == null
    //         ? null
    //         : Text(event.text,
    //             style: TextStyle(
    //               fontSize: 28,
    //               fontFamilyFallback: (!kIsWeb && Platform.isAndroid)
    //                   ? <String>[
    //                       'NotoColorEmoji',
    //                     ]
    //                   : null,
    //             )))
    //     .asBroadcastStream());
  }

  void _insertText(String t) {
    _focusNode.requestFocus();
    final textSelection = _controller.selection;
    if (textSelection.isValid) {
      final newText = _controller.text.replaceRange(
        textSelection.start,
        textSelection.end,
        t,
      );
      _controller.text = newText;
      final len = t.length;
      _controller.selection = textSelection.copyWith(
        baseOffset: textSelection.start + len,
        extentOffset: textSelection.start + len,
      );
    } else {
      _controller.text += t;
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
    }
  }

  static bool _hideToolbarFailed = false;
  void _hideToolbar() {
    if (_hideToolbarFailed) return;
    try {
      (_textFieldKey?.currentState as dynamic)
          ?.editableTextKey
          ?.currentState
          ?.hideToolbar();
    } catch (e) {
      _hideToolbarFailed = true;
    }
  }

  void _backspace() {
    final text = _controller.text;
    final textSelection = _controller.selection;
    final selectionLength = textSelection.end - textSelection.start;
    // There is a selection.
    if (selectionLength > 0) {
      final newText = text.replaceRange(
        textSelection.start,
        textSelection.end,
        '',
      );
      _controller.text = newText;
      _controller.selection = textSelection.copyWith(
        baseOffset: textSelection.start,
        extentOffset: textSelection.start,
      );
      return;
    }
    // The cursor is at the beginning.
    if (textSelection.start == 0) {
      return;
    }

    // Delete the previous character
    final deleted = text
        .substring(0, textSelection.start)
        .characters
        .skipLast(1)
        .toString();
    final newStart = deleted.length;
    final newText = deleted + text.substring(textSelection.start);
    _controller.text = newText;
    _controller.selection = textSelection.copyWith(
      baseOffset: newStart,
      extentOffset: newStart,
    );
  }
}

// marker for behaviorsubject
class EmojiCollapsed {}

class CollapsedInput extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    BehaviorSubject<bool> collapsed =
        context.peekInherited<BehaviorSubject<bool>, EmojiCollapsed>();
    EmojiDataSource dataSource = context.peekInheritedDefaultSlot();
    Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        FadeButton(
            padding: EdgeInsets.only(left: 16, right: 12),
            child: Icon(
              Icons.keyboard_outlined,
              color: Colors.white.withAlpha(200),
              size: 22,
            ),
            onPressed: () {
              collapsed.value = false;
            }),
        ...List.generate(
            6,
            (index) => StreamBuilder<Emoji>(
                stream: dataSource.latestOfIndex(index),
                builder: (context, snapshot) => Expanded(
                    child:
                        DynamicEmojiCell(index: index, emoji: snapshot.data))))
      ],
    );
    content = SafeArea(child: content);
    content = Container(
        color: Color.lerp(Colors.white, Colors.black, 0.85),
        padding: EdgeInsets.only(top: 8, right: 16, bottom: 8),
        child: content);

    return content;
  }
}

class _AutofillGroup extends AutofillGroup {
  const _AutofillGroup({
    Key key,
    @required Widget child,
    AutofillContextAction onDisposeAction = AutofillContextAction.commit,
  })  : assert(child != null),
        super(key: key, child: child, onDisposeAction: onDisposeAction);

  @override
  AutofillGroupState createState() => _AutofillGroupState();
}

class _AutofillGroupState extends AutofillGroupState {
  @override
  TextInputConnection attach(
      TextInputClient trigger, TextInputConfiguration configuration) {
    return _TextInputConnection(super.attach(trigger, configuration));
  }
}

class _TextInputConnection implements TextInputConnection {
  final TextInputConnection delegate;

  _TextInputConnection(this.delegate);

  @override
  bool get attached => delegate.attached;

  @override
  void close() {
    delegate.close();
  }

  @override
  void connectionClosedReceived() {
    delegate.connectionClosedReceived();
  }

  @override
  void requestAutofill() {
    delegate.requestAutofill();
  }

  @override
  void setComposingRect(Rect rect) {
    delegate.setComposingRect(rect);
  }

  @override
  void setEditableSizeAndTransform(Size editableBoxSize, Matrix4 transform) {
    delegate.setEditableSizeAndTransform(editableBoxSize, transform);
  }

  @override
  void setEditingState(TextEditingValue value) {
    delegate.setEditingState(value);
  }

  @override
  void setStyle(
      {String fontFamily,
      double fontSize,
      FontWeight fontWeight,
      TextDirection textDirection,
      TextAlign textAlign}) {
    delegate.setStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      textDirection: textDirection,
      textAlign: textAlign,
    );
  }

  @override
  void show() {}

  @override
  void updateConfig(TextInputConfiguration configuration) {
    delegate.updateConfig(configuration);
  }
}
