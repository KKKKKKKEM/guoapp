import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 800.0;
  const height = 400.0;
  late ScriptedPlayer platform;
  late PlayerInteractions interactions;
  late List<double> applied;
  var pointerId = 0;
  var speed = 1.0;
  var shortDramaMode = false;
  late List<int> episodes;

  setUp(() {
    speed = 1;
    applied = [];
    episodes = [];
    shortDramaMode = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppDevice.channel, (call) async {
          if (call.method == 'getBrightness') return 0.5;
          if (call.method == 'setBrightness') {
            applied.add((call.arguments as Map)['brightness'] as double);
          }
          return null;
        });
    platform = ScriptedPlayer();
    interactions = PlayerInteractions(
      player: Player(platformPlayer: platform),
      available: () => true,
      baseSpeed: () => speed,
      shortDramaMode: () => shortDramaMode,
      onTogglePlayback: () {},
      onFullscreen: () {},
      onEpisode: (direction) {
        episodes.add(direction);
        return '';
      },
    );
  });

  tearDown(() {
    interactions.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppDevice.channel, null);
  });

  /// 触摸左侧区域，依次移动到 [moves] 指定的偏移位置后抬起，返回过程中是否出现过亮度条。
  Future<bool> touchLeft(
    WidgetTester tester,
    List<Offset> moves, {
    Duration hold = Duration.zero,
  }) async {
    final id = ++pointerId;
    const start = Offset(100, 200);
    interactions.pointerDown(
      PointerDownEvent(
        pointer: id,
        kind: PointerDeviceKind.touch,
        position: start,
      ),
      swipeEnabled: true,
      width: width,
      height: height,
    );
    await tester.pump(const Duration(milliseconds: 1));
    var hudShown = interactions.isBrightnessActive;
    for (final move in moves) {
      interactions.pointerMove(
        PointerMoveEvent(
          pointer: id,
          kind: PointerDeviceKind.touch,
          position: start + move,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      hudShown |= interactions.isBrightnessActive;
    }
    if (hold > Duration.zero) await tester.pump(hold);
    interactions.pointerUp(
      PointerUpEvent(
        pointer: id,
        kind: PointerDeviceKind.touch,
        position: start + (moves.isEmpty ? Offset.zero : moves.last),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    return hudShown;
  }

  testWidgets('轻点左侧不显示亮度条也不改亮度', (tester) async {
    expect(await touchLeft(tester, const []), isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('手指轻微漂移（含纵向 <阈值）不改亮度', (tester) async {
    final shown = await touchLeft(tester, const [
      Offset(2, -8),
      Offset(3, -20),
      Offset(4, -30),
    ]);
    expect(shown, isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('横向滑动不改亮度', (tester) async {
    final shown = await touchLeft(tester, const [
      Offset(40, -10),
      Offset(120, -60),
      Offset(200, -70),
    ]);
    expect(shown, isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('明确的纵向滑动才调亮度，且从锁定点起算不跳变', (tester) async {
    final shown = await touchLeft(tester, const [
      Offset(0, -20),
      Offset(0, -60), // 越过阈值：仅锁定，不改亮度
      Offset(0, -60 - 48), // 再上滑 48px
    ]);
    expect(shown, isTrue);
    expect(applied.length, 1);
    // 48 / (400 * 0.6) = 0.2
    expect(applied.single, closeTo(0.7, 1e-9));
  });

  for (final x in [100.0, 700.0]) {
    for (final direction in [-1, 1]) {
      testWidgets(
        'short drama vertical swipe at $x switches episode $direction without changing levels',
        (tester) async {
          shortDramaMode = true;
          platform.state = platform.state.copyWith(volume: 50);
          interactions.pointerDown(
            PointerDownEvent(pointer: 50, position: Offset(x, 200)),
            swipeEnabled: true,
            width: width,
            height: height,
          );
          interactions.pointerMove(
            PointerMoveEvent(
              pointer: 50,
              position: Offset(x, 200 - direction * 100),
            ),
          );
          expect(episodes, isEmpty);
          interactions.pointerUp(const PointerUpEvent(pointer: 50));
          await tester.pump();
          expect(episodes, [direction]);
          expect(platform.state.volume, 50);
          expect(applied, isEmpty);
          await tester.pump(const Duration(seconds: 2));
        },
      );
    }
  }

  testWidgets(
    'ordinary right vertical gesture controls volume from its lock point and never switches episodes',
    (tester) async {
      platform.state = platform.state.copyWith(volume: 50);
      interactions.pointerDown(
        const PointerDownEvent(pointer: 51, position: Offset(600, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 51, position: Offset(600, 140)),
      );
      expect(platform.state.volume, 50);
      expect(interactions.hudState.type, SwipeAction.volume);
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 51, position: Offset(350, 92)),
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 51));
      await tester.pump();
      expect(platform.state.volume, closeTo(70, 1e-9));
      expect(applied, isEmpty);
      expect(episodes, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  for (final direction in [-1, 1]) {
    testWidgets(
      'ordinary volume gesture clamps at ${direction == 1 ? 100 : 0}',
      (tester) async {
        platform.state = platform.state.copyWith(volume: 50);
        interactions.pointerDown(
          const PointerDownEvent(pointer: 52, position: Offset(600, 200)),
          swipeEnabled: true,
          width: width,
          height: height,
        );
        interactions.pointerMove(
          PointerMoveEvent(
            pointer: 52,
            position: Offset(600, 200 - direction * 60),
          ),
        );
        interactions.pointerMove(
          PointerMoveEvent(
            pointer: 52,
            position: Offset(600, 200 - direction * 400),
          ),
        );
        interactions.pointerUp(const PointerUpEvent(pointer: 52));
        await tester.pump();
        expect(platform.state.volume, direction == 1 ? 100 : 0);
        expect(episodes, isEmpty);
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  testWidgets(
    'switching mode cancels an unfinished episode gesture and the next gesture uses normal levels',
    (tester) async {
      shortDramaMode = true;
      platform.state = platform.state.copyWith(volume: 50);
      interactions.pointerDown(
        const PointerDownEvent(pointer: 53, position: Offset(600, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 53, position: Offset(600, 100)),
      );
      interactions.cancel();
      shortDramaMode = false;
      interactions.pointerUp(const PointerUpEvent(pointer: 53));
      expect(episodes, isEmpty);
      interactions.pointerDown(
        const PointerDownEvent(pointer: 54, position: Offset(600, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 54, position: Offset(600, 140)),
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 54, position: Offset(600, 92)),
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 54));
      await tester.pump();
      expect(platform.state.volume, closeTo(70, 1e-9));
      expect(episodes, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('vertical episode gesture stays vertical after sideways drift', (
    tester,
  ) async {
    shortDramaMode = true;
    platform.state = platform.state.copyWith(
      position: const Duration(seconds: 60),
      duration: const Duration(minutes: 2),
    );
    interactions.pointerDown(
      const PointerDownEvent(pointer: 36, position: Offset(400, 200)),
      swipeEnabled: true,
      width: width,
      height: height,
    );
    interactions.pointerMove(
      const PointerMoveEvent(pointer: 36, position: Offset(400, 120)),
    );
    interactions.pointerMove(
      const PointerMoveEvent(pointer: 36, position: Offset(650, 120)),
    );
    interactions.pointerMove(
      const PointerMoveEvent(pointer: 36, position: Offset(420, 100)),
    );
    interactions.pointerUp(const PointerUpEvent(pointer: 36));
    await tester.pump();
    expect(platform.state.position, const Duration(seconds: 60));
    expect(episodes, [1]);
    expect(applied, isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('short paused video supports seeking within its duration', (
    tester,
  ) async {
    platform.state = platform.state.copyWith(
      playing: false,
      position: const Duration(seconds: 20),
      duration: const Duration(seconds: 40),
    );
    interactions.pointerDown(
      const PointerDownEvent(pointer: 37, position: Offset(400, 200)),
      swipeEnabled: true,
      width: width,
      height: height,
    );
    interactions.pointerMove(
      const PointerMoveEvent(pointer: 37, position: Offset(600, 200)),
    );
    interactions.pointerUp(const PointerUpEvent(pointer: 37));
    await tester.pump();
    expect(platform.state.position, const Duration(seconds: 30));
    expect(platform.state.playing, isFalse);
    expect(episodes, isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'horizontal gesture without duration does not seek or become an episode swipe',
    (tester) async {
      platform.state = platform.state.copyWith(
        position: const Duration(seconds: 20),
        duration: Duration.zero,
      );
      interactions.pointerDown(
        const PointerDownEvent(pointer: 38, position: Offset(400, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 38, position: Offset(600, 200)),
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 38, position: Offset(410, 100)),
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 38));
      await tester.pump();
      expect(platform.state.position, const Duration(seconds: 20));
      expect(episodes, isEmpty);
      expect(interactions.feedback, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  for (final direction in [-1, 1]) {
    testWidgets(
      'horizontal swipe $direction anchors to touch-down position and seeks only on release',
      (tester) async {
        platform.state = platform.state.copyWith(
          playing: true,
          position: const Duration(seconds: 60),
          duration: const Duration(minutes: 2),
        );
        interactions.pointerDown(
          const PointerDownEvent(pointer: 30, position: Offset(400, 200)),
          swipeEnabled: true,
          width: width,
          height: height,
        );
        interactions.pointerMove(
          PointerMoveEvent(
            pointer: 30,
            position: Offset(400 + direction * 160, 200),
          ),
        );
        expect(platform.state.position, const Duration(seconds: 60));
        platform.state = platform.state.copyWith(
          position: const Duration(seconds: 61),
        );
        interactions.pointerMove(
          PointerMoveEvent(
            pointer: 30,
            position: Offset(400 + direction * 160, 280),
          ),
        );
        interactions.pointerUp(const PointerUpEvent(pointer: 30));
        await tester.pump();
        expect(platform.state.position, Duration(seconds: 60 + direction * 18));
        expect(applied, isEmpty);
        expect(interactions.suppressTap, isTrue);
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  for (final position in [0, 120]) {
    testWidgets('horizontal swipe clamps to playback boundary $position', (
      tester,
    ) async {
      platform.state = platform.state.copyWith(
        position: Duration(seconds: position == 0 ? 5 : 115),
        duration: const Duration(minutes: 2),
      );
      interactions.pointerDown(
        const PointerDownEvent(pointer: 31, position: Offset(400, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        PointerMoveEvent(
          pointer: 31,
          position: Offset(position == 0 ? 0 : 800, 200),
        ),
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 31));
      await tester.pump();
      expect(platform.state.position, Duration(seconds: position));
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets(
    'second finger cancels a pending seek and a hold cannot turn into a seek',
    (tester) async {
      platform.state = platform.state.copyWith(
        playing: true,
        position: const Duration(seconds: 60),
        duration: const Duration(minutes: 2),
      );
      interactions.pointerDown(
        const PointerDownEvent(pointer: 32, position: Offset(400, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 32, position: Offset(600, 200)),
      );
      interactions.pointerDown(
        const PointerDownEvent(pointer: 33, position: Offset(500, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 32));
      interactions.pointerUp(const PointerUpEvent(pointer: 33));
      await tester.pump();
      expect(platform.state.position, const Duration(seconds: 60));
      interactions.pointerDown(
        const PointerDownEvent(pointer: 34, position: Offset(400, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, 2);
      interactions.pointerMove(
        const PointerMoveEvent(pointer: 34, position: Offset(600, 200)),
      );
      interactions.pointerUp(const PointerUpEvent(pointer: 34));
      await tester.pump();
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, 1);
      expect(platform.state.position, const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('pointer cancellation discards a horizontal preview', (
    tester,
  ) async {
    platform.state = platform.state.copyWith(
      position: const Duration(seconds: 60),
      duration: const Duration(minutes: 2),
    );
    interactions.pointerDown(
      const PointerDownEvent(pointer: 35, position: Offset(400, 200)),
      swipeEnabled: true,
      width: width,
      height: height,
    );
    interactions.pointerMove(
      const PointerMoveEvent(pointer: 35, position: Offset(600, 200)),
    );
    interactions.pointerCancel(const PointerCancelEvent(pointer: 35));
    await tester.pump();
    expect(platform.state.position, const Duration(seconds: 60));
    expect(interactions.feedback, isEmpty);
    expect(interactions.suppressTap, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  for (final selected in [1.0, 1.25, 2.0]) {
    testWidgets('touch hold doubles $selected and restores on release', (
      tester,
    ) async {
      speed = selected;
      platform.state = platform.state.copyWith(playing: true, rate: selected);
      interactions.pointerDown(
        const PointerDownEvent(pointer: 20, position: Offset(500, 200)),
        swipeEnabled: true,
        width: width,
        height: height,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, selected * 2);
      interactions.pointerUp(const PointerUpEvent(pointer: 20));
      await tester.pump();
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, selected);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('remote boost doubles $selected and restores', (tester) async {
      speed = selected;
      platform.state = platform.state.copyWith(playing: true, rate: selected);
      expect(interactions.beginBoost(), isTrue);
      await tester.pump();
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, selected * 2);
      interactions.endBoost();
      await tester.pump();
      await tester.runAsync(() => interactions.pendingRates);
      expect(platform.state.rate, selected);
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
