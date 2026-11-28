import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/app/theme/app_theme.dart';
import 'package:time_tracker/models/activity.dart';
import 'package:time_tracker/models/app_settings.dart';
import 'package:time_tracker/repositories/settings_repository.dart';
import 'package:time_tracker/services/tracking/time_range.dart';
import 'package:time_tracker/services/widget/switcher_widget.dart';
import 'package:time_tracker/widgets/activities/activity_tile.dart';

import '../../support/tracking_fixture.dart';

Activity _activity({String? icon, String name = 'Work'}) => Activity(
  id: 7,
  name: name,
  color: 0xFFFF9800,
  position: 1,
  isSystem: false,
  createdAt: DateTime.utc(2026),
  deletedAt: null,
  icon: icon,
);

/// Decoded RGBA pixels of [png].
Future<(ByteData, int)> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  final width = image.width;
  image.dispose();
  return (data, width);
}

Color _at(ByteData data, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

/// The pixel at logical [at].
Future<Color> _pixel(Uint8List png, Offset at) async {
  final (data, width) = await _decode(png);
  return _at(
    data,
    width,
    (at.dx * SwitcherWidget.defaultPixelRatio).round(),
    (at.dy * SwitcherWidget.defaultPixelRatio).round(),
  );
}

/// PNG pixels have 8 bits per channel.
bool _close(Color a, Color b) =>
    (a.r - b.r).abs() < 2 / 255 &&
    (a.g - b.g).abs() < 2 / 255 &&
    (a.b - b.b).abs() < 2 / 255 &&
    (a.a - b.a).abs() < 2 / 255;

Matcher _closeTo(Color expected) =>
    predicate<Color>((c) => _close(c, expected), 'close to $expected');

/// Pixels in the central 24 x 24 area that differ from [fill].
Future<int> _drawnInCentre(Uint8List png, Color fill) async {
  final (data, width) = await _decode(png);
  final c =
      SwitcherWidget.tileSize.center(Offset.zero) *
      SwitcherWidget.defaultPixelRatio;
  const half = 8 * SwitcherWidget.defaultPixelRatio;
  var count = 0;
  for (var y = (c.dy - half).round(); y < c.dy + half; y++) {
    for (var x = (c.dx - half).round(); x < c.dx + half; x++) {
      if (!_close(_at(data, width, x, y), fill)) count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheme = buildTheme(
    AppearanceMode.dark,
    AccentPalette.teal,
  ).colorScheme;

  Future<Uint8List> render(
    Activity a, {
    bool active = false,
    bool neon = false,
  }) =>
      SwitcherWidget.renderTile(a, active: active, scheme: scheme, neon: neon);

  group('tile image', () {
    test('has the widget tile size', () async {
      final png = await render(_activity(icon: 'work'));
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect(
        image.width,
        SwitcherWidget.tileSize.width * SwitcherWidget.defaultPixelRatio,
      );
      expect(
        image.height,
        SwitcherWidget.tileSize.height * SwitcherWidget.defaultPixelRatio,
      );
    });

    test('is flatter with the timer on, with the icon still centred', () async {
      const size = SwitcherWidget.timerTileSize;
      final png = await SwitcherWidget.renderTile(
        _activity(icon: 'work'),
        active: false,
        scheme: scheme,
        neon: false,
        size: size,
      );
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, size.width * SwitcherWidget.defaultPixelRatio);
      expect(image.height, size.height * SwitcherWidget.defaultPixelRatio);
      image.dispose();
      final fill = ActivityTile.fillFor(scheme, _activity(), false);
      expect(await _pixel(png, const Offset(35, 5)), _closeTo(fill));
      expect(await _pixel(png, const Offset(35, 22)), _closeTo(fill));
      var drawn = 0;
      for (var x = 28.0; x <= 42; x += 0.5) {
        if (!_close(await _pixel(png, Offset(x, 13.5)), fill)) drawn++;
      }
      expect(drawn, greaterThan(4), reason: 'icon across the middle');
    });

    test('is filled like the app tile: full colour when active, muted '
        'otherwise', () async {
      final a = _activity();
      // A point inside the tile but away from the centred label.
      const probe = Offset(SwitcherWidget.padding + 6, 18);
      expect(
        await _pixel(await render(a, active: true), probe),
        _closeTo(ActivityTile.fillFor(scheme, a, true)),
      );
      expect(
        await _pixel(await render(a), probe),
        _closeTo(ActivityTile.fillFor(scheme, a, false)),
      );
    });

    test('glows outside the tile only with Neon on the active tile', () async {
      final a = _activity(icon: 'work');
      // In the padding, beside the tile edge.
      const outside = Offset(1.5, 18);
      expect((await _pixel(await render(a, active: true), outside)).a, 0);
      expect((await _pixel(await render(a, neon: true), outside)).a, 0);
      expect(
        (await _pixel(await render(a, active: true, neon: true), outside)).a,
        greaterThan(0),
      );
    });

    test('is grey in Grayscale, coloured otherwise', () async {
      final a = _activity();
      const probe = Offset(SwitcherWidget.padding + 6, 18);
      bool grey(Color c) =>
          (c.r - c.g).abs() < 3 / 255 && (c.g - c.b).abs() < 3 / 255;
      final coloured = await _pixel(await render(a, active: true), probe);
      expect(grey(coloured), isFalse);
      final png = await SwitcherWidget.renderTile(
        a,
        active: true,
        scheme: scheme,
        neon: false,
        filter: styleFilter(AppStyle.grayscale),
      );
      final c = await _pixel(png, probe);
      expect(grey(c), isTrue, reason: '$c');
      expect(c.a, greaterThan(0.99));
    });

    test('draws the icon or the first letter in the centre', () async {
      for (final a in [_activity(icon: 'work'), _activity(name: 'reading')]) {
        for (final active in [false, true]) {
          final fill = ActivityTile.fillFor(scheme, a, active);
          expect(
            await _drawnInCentre(await render(a, active: active), fill),
            greaterThan(40),
            reason: '${a.icon ?? a.name}, active: $active',
          );
        }
      }
    });

    test('an empty slot is an outline with "+", no fill', () async {
      final png = await SwitcherWidget.renderTile(
        null,
        active: false,
        scheme: scheme,
        neon: false,
      );
      const inside = Offset(SwitcherWidget.padding + 6, 18);
      expect((await _pixel(png, inside)).a, 0);
      const edge = Offset(SwitcherWidget.padding + 0.5, 18);
      expect((await _pixel(png, edge)).a, greaterThan(0));
      expect(await _drawnInCentre(png, Colors.transparent), greaterThan(40));
    });
  });

  group('tile size', () {
    test('fills a slot of the reported widget size', () {
      // The emulator's 4 x 1 widget: flat slots.
      expect(
        SwitcherWidget.tileSizeFor(const Size(300, 75), timer: false),
        const Size(75, 37),
      );
      expect(
        SwitcherWidget.tileSizeFor(const Size(300, 75), timer: true),
        const Size(75, 27),
      );
    });

    test('is never taller than an app tile', () {
      final tall = SwitcherWidget.tileSizeFor(
        const Size(320, 600),
        timer: true,
      );
      expect(tall, const Size(80, 70));
      expect(SwitcherWidget.maxTileHeight, 70);
    });

    test('falls back to the 4 x 1 default before a size is reported', () {
      expect(
        SwitcherWidget.tileSizeFor(null, timer: false),
        SwitcherWidget.tileSize,
      );
      expect(
        SwitcherWidget.tileSizeFor(null, timer: true),
        SwitcherWidget.timerTileSize,
      );
    });

    test('every widget size reported, each drawn once', () {
      // Home screen and two lock-screen widgets, two of the same size.
      expect(
        SwitcherWidget.reportedSizes('8=379x130;11=300x200;17=300x200'),
        {'379x130', '300x200'},
      );
      expect(SwitcherWidget.reportedSizes(null), isEmpty);
      expect(SwitcherWidget.reportedSizes('8=x;9=0x5;bad'), isEmpty);
      expect(SwitcherWidget.parseSize('379x130'), const Size(379, 130));
      expect(SwitcherWidget.imageKey(3), 'slot_3_image');
      expect(SwitcherWidget.imageKey(3, '379x130'), 'slot_3_image_379x130');
    });

    test(
      'icons are as in the app on app-sized tiles, smaller in flat ones',
      () {
        expect(SwitcherWidget.labelSize(64, 26, 0.68), 26);
        expect(SwitcherWidget.labelSize(31, 26, 0.68), closeTo(21.1, 0.1));
      },
    );
  });

  group('state from the database', () {
    test('grid by position, the running activity and the look', () async {
      final f = await TrackingFixture.create(DateTime.utc(2026, 11, 12, 8));
      addTearDown(f.db.close);
      await SettingsRepository(f.db).save(
        const AppSettings(
          appearance: AppearanceMode.light,
          style: AppStyle.neon,
        ),
      );
      await f.service.reconcile();
      f.clock.advance(const Duration(minutes: 5));
      await f.service.switchTo(f.study);

      final state = await SwitcherState.load(f.db);
      expect(state.at(1)?.id, f.freeTime);
      expect(state.at(2)?.id, f.gaming);
      expect(state.at(3)?.id, f.study);
      expect(state.at(4), isNull);
      expect(state.activeId, f.study);
      expect(state.style, AppStyle.neon);
      expect(state.colorScheme.brightness, Brightness.light);
      expect(state.timer, isNull, reason: 'the timer is off by default');
    });

    test('timer: session start and today\'s closed time', () async {
      final f = await TrackingFixture.create(DateTime.utc(2026, 11, 12, 8));
      addTearDown(f.db.close);
      await SettingsRepository(f.db).save(const AppSettings(widgetTimer: true));
      await f.service.reconcile();
      await f.service.switchTo(f.study);
      f.clock.advance(const Duration(minutes: 20));
      await f.service.switchTo(f.gaming);
      f.clock.advance(const Duration(minutes: 5));
      await f.service.switchTo(f.study);
      final started = f.clock.now();
      f.clock.advance(const Duration(minutes: 3));

      final timer = (await SwitcherState.load(f.db)).timer!;
      expect(timer.sessionStart, started);
      expect(timer.closedToday, const Duration(minutes: 20));
      expect(timer.dayEnd, nextLocalMidnight(started));
    });
  });

  test('tap links', () {
    expect(switchTargetId(Uri.parse('timetracker://switch?id=12')), 12);
    expect(switchTargetId(Uri.parse('timetracker://switch?id=x')), isNull);
    expect(switchTargetId(Uri.parse('timetracker://open?id=12')), isNull);
    expect(switchTargetId(Uri.parse('https://switch?id=12')), isNull);
    expect(switchTargetId(null), isNull);
  });
}
