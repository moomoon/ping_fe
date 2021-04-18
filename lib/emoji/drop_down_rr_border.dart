import 'dart:math';

import 'package:flutter/material.dart';

class DropdownRRBorder extends ShapeBorder {
  final double upperRadius;
  final double lowerRadius;

  DropdownRRBorder({@required this.upperRadius, @required this.lowerRadius});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection textDirection}) =>
      _createPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection textDirection}) {}

  @override
  ShapeBorder scale(double t) =>
      DropdownRRBorder(upperRadius: upperRadius, lowerRadius: lowerRadius);

  Path _createPath(Rect rect) {
    return Path()
      ..moveTo(rect.left, rect.top)
      ..arcTo(
        Rect.fromCircle(
            center: Offset(rect.left, rect.top + upperRadius),
            radius: upperRadius),
        -pi / 2,
        pi / 2,
        false,
      )
      ..lineTo(rect.left + upperRadius, rect.bottom - lowerRadius)
      ..arcTo(
        Rect.fromCircle(
            center: Offset(rect.left + upperRadius + lowerRadius,
                rect.bottom - lowerRadius),
            radius: lowerRadius),
        -pi,
        -pi / 2,
        false,
      )
      ..lineTo(rect.right - upperRadius - lowerRadius, rect.bottom)
      ..arcTo(
          Rect.fromCircle(
              center: Offset(rect.right - upperRadius - lowerRadius,
                  rect.bottom - lowerRadius),
              radius: lowerRadius),
          pi / 2,
          -pi / 2,
          false)
      ..lineTo(rect.right - upperRadius, rect.top - upperRadius)
      ..arcTo(
          Rect.fromCircle(
              center: Offset(rect.right, rect.top + upperRadius),
              radius: upperRadius),
          -pi,
          pi / 2,
          false)
      ..lineTo(rect.left, rect.top)
      ..close();
  }
}
