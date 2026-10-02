import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The screen classes the SDK views adapt to.
enum ScreenClass {
  /// Small phones, or any screen with little height (phones in landscape).
  compact,

  /// Phones and tablets.
  regular,

  /// Kiosks, large tablets and desktop.
  large,
}

/// Sizes for the SDK views, from the screen they are drawn on.
abstract final class Responsive {
  /// Narrower than this is [ScreenClass.compact].
  static const compactWidth = 360.0;

  /// Shorter than this is [ScreenClass.compact].
  static const compactHeight = 500.0;

  /// A shortest side of at least this is [ScreenClass.large].
  static const largeShortestSide = 900.0;

  static ScreenClass of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < compactWidth || size.height < compactHeight) {
      return ScreenClass.compact;
    }
    if (size.shortestSide >= largeShortestSide) return ScreenClass.large;
    return ScreenClass.regular;
  }

  /// Picks the value for the current screen class.
  static T pick<T>(
    BuildContext context, {
    required T compact,
    required T regular,
    required T large,
  }) =>
      switch (of(context)) {
        ScreenClass.compact => compact,
        ScreenClass.regular => regular,
        ScreenClass.large => large,
      };

  /// The QR side: the size the app asked for, shrunk to fit [maxWidth] and
  /// under half of the screen height, so the QR and its buttons stay visible.
  static double qrSide(
    BuildContext context, {
    required double requested,
    required double maxWidth,
  }) {
    final height = MediaQuery.sizeOf(context).height;
    final limit = math.min(maxWidth, height * 0.45);
    return math.max(math.min(requested, limit), math.min(120, maxWidth));
  }
}
