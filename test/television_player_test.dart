import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/television_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'player_fixtures.dart';
import 'remote_test_helpers.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 15));
    }
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  Future<LocalStore> mount(
    WidgetTester tester,
    RouteRepository repository,
    ScriptedPlayer player, {
    int initialIndex = 0,
    Widget Function(Widget)? videoBuilder,
  }) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final detail = DramaDetail(
      FixtureRepository.free,
      List.generate(100, (i) => Episode({'id': '${i + 1}'}, i + 1)),
    );
    await tester.pumpWidget(
      televisionHost(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                child: const Text('打开测试视频'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerScreen(
                      detail: detail,
                      initialIndex: initialIndex,
                      initialPosition: 7,
                      repository: repository,
                      store: store,
                      playerFactory: () => Player(platformPlayer: player),
                      videoBuilder: videoBuilder ?? (controls) => controls,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开测试视频'));
    await settle(tester);
    await settle(tester);
    return store;
  }

  Future<void> leave(
    WidgetTester tester,
    RouteRepository repository,
    ScriptedPlayer player,
  ) async {
    if (find.byKey(const ValueKey('tv-menu-tab-0')).evaluate().isNotEmpty)
      await press(tester, LogicalKeyboardKey.escape);
    if (find.byType(TelevisionPlayerMenu).evaluate().isNotEmpty)
      await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(player.disposed, isTrue);
    expect(repository.active, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  for (final systemBack in [false, true]) {
    testWidgets(
      'single transport/menu panel closes before playback, systemBack=$systemBack',
      (tester) async {
        final repository = RouteRepository();
        final player = ScriptedPlayer();
        await mount(tester, repository, player);
        expect(find.byKey(const ValueKey('tv-play-pause')), findsNothing);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.byType(TelevisionPlayerMenu), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-progress')), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-play-pause')), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-menu-tab-0')), findsNothing);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(find.byKey(const ValueKey('tv-menu-tab-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-progress')), findsNothing);
        expect(find.byKey(const ValueKey('tv-play-pause')), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        await settle(tester);
        expect(find.byType(TelevisionPlayerMenu), findsOneWidget);
        if (systemBack) {
          await tester.binding.handlePopRoute();
          await settle(tester);
        } else {
          await press(tester, LogicalKeyboardKey.escape);
        }
        expect(find.byType(TelevisionPlayerMenu), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-menu-tab-0')), findsNothing);
        expect(find.byKey(const ValueKey('tv-progress')), findsOneWidget);
        expect(find.byKey(const ValueKey('tv-play-pause')), findsOneWidget);
        expect(find.byType(PlayerScreen), findsOneWidget);
        if (systemBack) {
          await tester.binding.handlePopRoute();
          await settle(tester);
        } else {
          await press(tester, LogicalKeyboardKey.escape);
        }
        expect(find.byType(TelevisionPlayerMenu), findsNothing);
        expect(find.byKey(const ValueKey('tv-progress')), findsNothing);
        expect(find.byKey(const ValueKey('tv-play-pause')), findsNothing);
        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(player.disposed, isFalse);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'tv-player-surface',
        );
        await leave(tester, repository, player);
      },
    );
  }

  testWidgets('transport actions and progress work inside unified panel', (
    tester,
  ) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await mount(tester, repository, player);
    await press(tester, LogicalKeyboardKey.select);
    expect(player.state.playing, isFalse);
    await press(tester, LogicalKeyboardKey.mediaPlayPause);
    expect(player.state.playing, isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(player.state.position, const Duration(seconds: 17));
    final hint = tester.widget<Text>(find.text('0:17 / 2:00'));
    expect(hint.style?.color, Colors.white);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-panel-play');
    await press(tester, LogicalKeyboardKey.select);
    expect(player.state.playing, isFalse);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-panel-progress');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(player.state.position, const Duration(seconds: 7));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-panel-play');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-menu-tab-0');
    await leave(tester, repository, player);
  });

  testWidgets('episode speed and quality selections return to bare playback', (
    tester,
  ) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await mount(tester, repository, player, initialIndex: 70);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-71');
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(repository.requestedEpisodes.last, 72);
    expect(find.byType(TelevisionPlayerMenu), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(player.state.rate, 1.25);
    await player.seek(const Duration(seconds: 28));
    await player.pause();
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowDown);
    focusRemote(tester, find.byKey(const ValueKey('tv-quality-1080')));
    await settle(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(repository.requestedQualities.last, 720);
    expect(player.state.position, const Duration(seconds: 28));
    expect(player.state.rate, 1.25);
    expect(player.state.playing, isFalse);
    await leave(tester, repository, player);
  });

  testWidgets('short up opens the only panel, hold up doubles and releases', (
    tester,
  ) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await mount(tester, repository, player);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester);
    expect(player.state.rate, 2);
    expect(find.text('2.0 倍速 · 松开恢复'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(player.state.rate, 1);
    expect(find.byType(TelevisionPlayerMenu), findsNothing);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(find.byType(TelevisionPlayerMenu), findsOneWidget);
    await leave(tester, repository, player);
  });

  testWidgets('settings persist through transport menu reopen', (tester) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    final store = await mount(tester, repository, player);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(store.playbackPreferences.autoAdvance, isFalse);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(store.playbackPreferences.preload, isFalse);
    expect(store.playbackPreferences.autoAdvance, isFalse);
    await leave(tester, repository, player);
  });

  testWidgets('video cannot take focus away from playback surface', (
    tester,
  ) async {
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    final videoFocus = FocusNode();
    addTearDown(videoFocus.dispose);
    await mount(
      tester,
      repository,
      player,
      videoBuilder: (controls) =>
          Focus(focusNode: videoFocus, autofocus: true, child: controls),
    );
    videoFocus.requestFocus();
    await settle(tester);
    expect(videoFocus.hasPrimaryFocus, isFalse);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byType(TelevisionPlayerMenu), findsOneWidget);
    await leave(tester, repository, player);
  });

  testWidgets('playback error retains retry focus', (tester) async {
    final repository = RouteRepository()..broken = true;
    final player = ScriptedPlayer();
    await mount(tester, repository, player);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
    }
    expect(find.text('重试播放'), findsOneWidget);
    repository.broken = false;
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('重试播放'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-player-surface');
    await leave(tester, repository, player);
  });

  testWidgets(
    'center playback button gives feedback without taking remote focus',
    (tester) async {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      final focus = FocusManager.instance.primaryFocus;
      await press(tester, LogicalKeyboardKey.select);
      expect(player.state.playing, isFalse);
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-center-playback')), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('tv-center-playback')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-center-playback')));
      await settle(tester);
      expect(player.state.playing, isTrue);
      expect(find.text('正在播放'), findsOneWidget);
      expect(find.byType(TelevisionPlayerMenu), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(find.byKey(const ValueKey('tv-center-playback')), findsNothing);
      await leave(tester, repository, player);
    },
  );
}
