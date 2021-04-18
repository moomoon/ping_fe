import 'dart:math';

import 'package:flutter/material.dart';
import '../foundation.dart';

class WidgetThrower extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return WidgetThrowerState();
  }
}

class WidgetThrowerState extends State<WidgetThrower>
    with TickerProviderStateMixin {
  AnimationController controller;

  @override
  dispose() {
    controller?.dispose();
    super.dispose();
  }

  Widget buildFlinger(Widget child) {
    final phoneInterval =
        CurveTween(curve: const Interval(0.82, 1, curve: Curves.easeIn));
    final reversePhoneInterval =
        phoneInterval.chain(Tween<double>(begin: 1, end: 0));

    final phoneRotationTween = Tween<double>(begin: -pi / 8, end: -pi / 3);
    final phoneRotationAnimation = controller.drive(TweenSequence([
      TweenSequenceItem(
          tween: phoneRotationTween.chain(phoneInterval), weight: 1),
      TweenSequenceItem(
          tween: phoneRotationTween.chain(reversePhoneInterval), weight: 1),
    ]));
    Widget phoneRotated = AnimatedBuilder(
      child: Icon(Icons.smartphone_rounded, color: Colors.white, size: 32),
      animation: phoneRotationAnimation,
      builder: (context, child) => Transform(
        transform: Matrix4.rotationZ(phoneRotationAnimation.value),
        alignment: Alignment.center,
        child: child,
      ),
    );

    final phoneShakeTween = Tween<double>(begin: 0, end: -pi / 4);
    final phoneShakeAnimation = controller.drive(TweenSequence([
      TweenSequenceItem(tween: phoneShakeTween.chain(phoneInterval), weight: 1),
      TweenSequenceItem(
          tween: phoneShakeTween.chain(reversePhoneInterval), weight: 1),
    ]));
    Widget phoneShaked = AnimatedBuilder(
      child: Container(
          width: 56,
          height: 56,
          child: phoneRotated,
          alignment: Alignment.topLeft),
      animation: phoneShakeAnimation,
      builder: (context, child) => Transform(
        transform: Matrix4.rotationZ(phoneShakeAnimation.value),
        alignment: Alignment.centerRight,
        child: child,
      ),
    );

    final emojiInterval = const Interval(0.46, 0.6);
    final emojiMotionCurve = CurveTween(curve: emojiInterval);
    final emojiHorizTween = Tween<double>(begin: 0, end: -160);
    final emojiVertTween = Tween<double>(begin: 0, end: 20);

    final emojiHorizAnimation =
        controller.drive(emojiHorizTween.chain(emojiMotionCurve));
    final emojiVertAnimation = controller.drive(emojiVertTween
        .chain(CurveTween(curve: Curves.easeInCubic))
        .chain(emojiMotionCurve));
    final emojiRotationAnimation = controller.drive(TweenSequence(List.generate(
        4,
        (index) => TweenSequenceItem(
            tween: Tween<double>(begin: 0, end: -2 * pi), weight: 1))));

    final emojiOpacityTransitionWeight = 0.04;
    final emojiOpacityAnimation = controller.drive(TweenSequence([
      TweenSequenceItem(
          tween: ConstantTween<double>(0.0),
          weight: emojiInterval.begin - emojiOpacityTransitionWeight / 2),
      TweenSequenceItem(
          tween:
              Tween(begin: 0.0, end: 1).chain(CurveTween(curve: Curves.easeIn)),
          weight: emojiOpacityTransitionWeight),
      TweenSequenceItem(
          tween: ConstantTween(1.0),
          weight: emojiInterval.end -
              emojiInterval.begin -
              emojiOpacityTransitionWeight),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: emojiOpacityTransitionWeight),
      TweenSequenceItem(
          tween: ConstantTween(0.0),
          weight: 1.0 - emojiInterval.end - emojiOpacityTransitionWeight / 2),
    ]));

    Widget bullet = AnimatedBuilder(
        child: child,
        animation: controller,
        builder: (context, child) {
          return Transform(
            alignment: Alignment.center,
            child: Opacity(
              child: child,
              opacity: emojiOpacityAnimation.value,
            ),
            transform: Matrix4.identity()
              ..translate(emojiHorizAnimation.value, emojiVertAnimation.value)
              ..rotateZ(emojiRotationAnimation.value),
          );
        });

    return Container(
        width: 100,
        height: 56,
        child: Stack(alignment: Alignment.centerRight, children: [
          Positioned(right: 30, child: bullet),
          Positioned(right: 0, child: phoneShaked),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Widget>(
        stream: context
            .peekInherited<Stream<Widget>, WidgetThrower>()
            .distinct((l, r) => (l != null) == (r != null)),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            controller = AnimationController(
                vsync: this, duration: const Duration(seconds: 4));
            controller.value = 0.28;
            controller.repeat();
            return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: buildFlinger(StreamBuilder<Widget>(
                  initialData: snapshot.data,
                  stream: context
                      .peekInherited<Stream<Widget>, WidgetThrower>()
                      .distinct(),
                  builder: (context, snapshot) =>
                      snapshot.data ?? const SizedBox(),
                )));
          } else {
            controller?.dispose();
            controller = null;
            return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: const SizedBox(
                  width: 100,
                  height: 56,
                ));
          }
        });
  }
}
