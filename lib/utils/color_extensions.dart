import 'package:flutter/material.dart';

extension ColorExtensions on Color {
  /// Mirrors Flutter 3.22's `withValues` helper by applying only the provided
  /// components. Currently we only need alpha adjustments.
  Color withValues({double? alpha}) {
    if (alpha == null) {
      return this;
    }
    final clampedAlpha = alpha.clamp(0.0, 1.0);
    return withOpacity(clampedAlpha);
  }

  /// Convenience alias for `value`; older code used `toARGB32`.
  int toARGB32() => value;
}
