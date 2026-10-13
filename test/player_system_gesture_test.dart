import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/player_controls.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

void main() {
  late ScriptedPlayer platform;
  late Player player;
  late PlayerInteractions interactions;
  late List<int> episodes;
  late List<double> brightness;

  setUp(() {
    episodes = [];
    brightness = [];
    platform = ScriptedPlayer();
    platform.state = platform.state.copyWith(
      playing: true,
      volume: 50,
      position: const Duration(seconds: 60),
      duration: const Duration(minutes: 2),
    );
    player = Player(platformPlayer: platform);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppDevice.channel, (call) async {
          if (call.method == 'getBrightness') return 0.5;
          if (call.method == 'setBrightness') {
            brightness.add((call.arguments as Map)['brightness'] as double);
          }
          return null;
        });
  });

  tearDown(() async {
    interactions.dispose();
    await player.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppDevice.channel, null);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double bottomInset = 0,
    double navigationInset = 0,
    bool shortDrama = true,
    Rect? pane,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.view.systemGestureInsets = FakeViewPadding(bottom: bottomInset * 2);
    tester.view.viewPadding = FakeViewPadding(bottom: navigationInset * 2);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetSystemGestureInsets();
      tester.view.resetViewPadding();
    });
    interactions = PlayerInteractions(
      player: player,
      available: () => true,
      baseSpeed: () => 1,
      shortDramaMode: () => shortDrama,
      onTogglePlayback: () {},
      onFullscreen: () {},
      onEpisode: (direction) {
        episodes.add(direction);
        return '';
      },
    );
    final controls = PlayerControls(
      player: player,
      interactions: interactions,
      enabled: true,
      fullscreen: pane == null,
      showOnPlaybackReady: false,
      onFullscreen: () {},
      onBack: () {},
      onPrevious: null,
      onNext: null,
      title: 'Synthetic player',
      onTogglePlayback: () {},
      onEpisodes: () async {},
      onSpeed: () async {},
      onQuality: () async {},
      speed: 1,
      qualityLabel: '',
      onFocusSurface: () {},
      swipeEnabled: true,
      shortDramaMode: shortDrama,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Stack(
            children: [
              if (pane == null)
                Positioned.fill(child: controls)
              else
                Positioned.fromRect(rect: pane, child: controls),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> swipe(WidgetTester tester, Offset start, Offset delta) async {
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(delta / 2);
    await tester.pump(const Duration(milliseconds: 10));
    await gesture.moveBy(delta / 2);
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets(
    'immersive bottom home swipe leaves the episode unchanged and interior swipes still work',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(195, 830), const Offset(0, -220));
      expect(episodes, isEmpty);
      expect(platform.state.position, const Duration(seconds: 60));
      expect(platform.state.volume, 50);
      expect(brightness, isEmpty);
      await swipe(tester, const Offset(195, 600), const Offset(0, -160));
      expect(episodes, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'landscape uses the reported system gesture inset in logical pixels',
    (tester) async {
      await mount(tester, size: const Size(844, 390), bottomInset: 72);
      await swipe(tester, const Offset(420, 330), const Offset(0, -180));
      expect(episodes, isEmpty);
      await swipe(tester, const Offset(420, 317), const Offset(0, -150));
      expect(episodes, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'navigation view padding remains protected when gesture insets are zero',
    (tester) async {
      await mount(tester, navigationInset: 60);
      await swipe(tester, const Offset(195, 790), const Offset(0, -200));
      expect(episodes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'bottom of an inline video is not confused with the bottom of the screen',
    (tester) async {
      await mount(tester, pane: const Rect.fromLTWH(0, 80, 390, 300));
      await swipe(tester, const Offset(195, 365), const Offset(0, -180));
      expect(episodes, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ordinary mode ignores bottom brightness volume seek and multitasking hold gestures',
    (tester) async {
      await mount(tester, shortDrama: false);
      await swipe(tester, const Offset(100, 830), const Offset(0, -300));
      await swipe(tester, const Offset(300, 830), const Offset(0, -300));
      await swipe(tester, const Offset(100, 830), const Offset(180, -5));
      final gesture = await tester.startGesture(const Offset(195, 830));
      await tester.pump(const Duration(milliseconds: 500));
      expect(platform.rates, isEmpty);
      await gesture.moveBy(const Offset(0, -200));
      await gesture.cancel();
      await tester.pump();
      expect(episodes, isEmpty);
      expect(brightness, isEmpty);
      expect(platform.state.volume, 50);
      expect(platform.state.position, const Duration(seconds: 60));
      await swipe(tester, const Offset(300, 600), const Offset(0, -240));
      expect(platform.state.volume, greaterThan(50));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
