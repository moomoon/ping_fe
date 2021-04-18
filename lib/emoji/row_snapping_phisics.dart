import 'package:flutter/material.dart';

class RowSnappingPhysics extends ScrollPhysics {
  final rowHeight;
  const RowSnappingPhysics({@required this.rowHeight, ScrollPhysics parent})
      : super(parent: parent);

  @override
  RowSnappingPhysics applyTo(ScrollPhysics ancestor) {
    return RowSnappingPhysics(
        rowHeight: rowHeight, parent: buildParent(ancestor));
  }

  @override
  Simulation createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // If we're out of range and not headed back in range, defer to the parent
    // ballistics, which should put us back in range at a page boundary.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent))
      return super.createBallisticSimulation(position, velocity);
    final parent = super.createBallisticSimulation(position, velocity);
    if (parent == null) {
      final target = (position.pixels / rowHeight).roundToDouble() * rowHeight;
      if ((target - position.pixels).abs() >= tolerance.distance)
        return ScrollSpringSimulation(spring, position.pixels, target, velocity,
            tolerance: tolerance);
      return null;
    }
    final parentTarget = parent.x(100);
    final target = (parentTarget / rowHeight).roundToDouble() * rowHeight;
    final ratio = target / parentTarget;
    return RatioSim(parent: parent, ratio: ratio);
  }

  @override
  bool get allowImplicitScrolling => false;
}

class RatioSim extends Simulation {
  final Simulation parent;
  final double ratio;

  RatioSim({this.parent, this.ratio});
  @override
  double dx(double time) {
    return parent.dx(time) * ratio;
  }

  @override
  bool isDone(double time) {
    return parent.isDone(time);
  }

  @override
  double x(double time) {
    return parent.x(time) * ratio;
  }
}
