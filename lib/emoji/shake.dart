import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors/sensors.dart';

/// Callback for phone shakes
typedef Null PhoneShakeCallback();

/// ShakeDetector class for phone shake functionality
class ShakeDetector {
  /// User callback for phone shake
  final PhoneShakeCallback onPhoneShake;

  /// Shake detection threshold
  final double shakeThresholdGravity;

  /// Minimum time between shake
  final int shakeSlopTimeMS;
  final int throwTimeMS;

  int mShakeTimestamp = DateTime.now().millisecondsSinceEpoch;
  int throwStart;

  bool _started = false;

  /// StreamSubscription for Accelerometer events
  StreamSubscription streamSubscription;

  /// This constructor waits until [startListening] is called
  ShakeDetector.waitForStart(
      {@required this.onPhoneShake,
      this.shakeThresholdGravity = 2.7,
      this.throwTimeMS = 100,
      this.shakeSlopTimeMS = 300});

  /// This constructor automatically calls [startListening] and starts detection and callbacks.\
  ShakeDetector.autoStart(
      {@required this.onPhoneShake,
      this.shakeThresholdGravity = 2.7,
      this.throwTimeMS = 100,
      this.shakeSlopTimeMS = 300}) {
    startListening();
  }

  /// Starts listening to accelerometer events
  void startListening() {
    _started = true;
    streamSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (!_started) return;
      double x = event.x;
      double y = event.y;
      double z = event.z;

      double gX = x / 9.80665;
      double gY = y / 9.80665;
      double gZ = z / 9.80665;

      // gForce will be close to 1 when there is no movement.
      double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      if (gForce > shakeThresholdGravity) {
        if (throwStart == null) {
          throwStart = DateTime.now().millisecondsSinceEpoch;
        }
      } else {
        if (throwStart == null) return;
        // ignore shake events too close to each other (500ms)
        var now = DateTime.now().millisecondsSinceEpoch;
        final throwDuration = now - throwStart;
        throwStart = null;
        if (throwDuration < throwTimeMS) return;
        if (mShakeTimestamp + shakeSlopTimeMS > now) {
          return;
        }
        mShakeTimestamp = now;

        onPhoneShake();
      }
    });
  }

  /// Stops listening to accelerometer events
  void stopListening() {
    _started = false;
    streamSubscription?.cancel();
    streamSubscription = null;
  }
}
