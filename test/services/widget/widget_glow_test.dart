import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/app/theme/app_theme.dart';
import 'package:time_tracker/models/app_settings.dart';
import 'package:time_tracker/services/widget/switcher_widget.dart';

/// The widget's Neon session views (D62) are generated with fixed glow
/// colours; they must stay the app's Neon primary colours.
void main() {
  final layout = File(
    'android/app/src/main/res/layout/switcher_widget.xml',
  ).readAsStringSync();
  final glows = {
    for (final m in RegExp(
      r'android:id="@\+id/timer_session_(\w+)"\s+'
      r'style="@style/WidgetTimerSession"\s+'
      r'android:shadowColor="#[0-9A-Fa-f]{2}([0-9A-Fa-f]{6})"',
    ).allMatches(layout))
      m.group(1)!: int.parse(m.group(2)!, radix: 16),
  };

  test('every accent and appearance has a glow in its primary colour', () {
    for (final accent in AccentPalette.values) {
      for (final appearance in AppearanceMode.values) {
        final name = SwitcherWidget.timerGlow(accent, appearance);
        final primary = buildTheme(
          appearance,
          accent,
          style: AppStyle.neon,
        ).colorScheme.primary;
        expect(
          glows[name],
          primary.toARGB32() & 0xFFFFFF,
          reason:
              '$name: update PRIMARY in tool/generate_widget_glow.py and run '
              'it again',
        );
      }
    }
  });

  test('no glow variants beyond the accents', () {
    expect(glows.length, AccentPalette.values.length * 2);
  });
}
