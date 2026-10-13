import 'dart:async';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:duanju_app/television_home.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'remote_test_helpers.dart';
import 'tv_playback_launch_test.dart' show DeferredLaunchRepository;

void main() {
  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.pump();
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> openSearch(
    WidgetTester tester, {
    Future<List<String>> Function(String)? suggestions,
    String initialValue = '',
    ValueChanged<String?>? onResult,
  }) async {
    await tester.pumpWidget(
      televisionHost(
        child: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => TelevisionSearchDialog(
                    initialValue: initialValue,
                    title: '搜索剧库',
                    suggestions: suggestions,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('打开搜索'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV search ignores stale suggestions and submits the entered keyword',
    (tester) async {
      size(tester, const Size(960, 540));
      final pending = <String, Completer<List<String>>>{};
      String? submitted;
      await openSearch(
        tester,
        suggestions: (query) =>
            (pending[query] = Completer<List<String>>()).future,
        onResult: (value) => submitted = value,
      );
      await tester.tap(find.byKey(const ValueKey('tv-key-A')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('tv-key-B')));
      await tester.pump(const Duration(milliseconds: 300));
      pending['AB']!.complete(['当前结果']);
      await tester.pumpAndSettle();
      pending['A']!.complete(['过期结果']);
      await tester.pumpAndSettle();
      expect(find.text('当前结果'), findsOneWidget);
      expect(find.text('过期结果'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tv-search-submit')));
      await tester.pumpAndSettle();
      expect(submitted, 'AB');
    },
  );

  for (final dimensions in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'TV search edits Chinese explicitly and bounds long results at $dimensions',
      (tester) async {
        size(tester, dimensions);
        String? submitted;
        await openSearch(
          tester,
          suggestions: (_) async => ['非常长的合成剧名用于覆盖电视搜索窄列长标题横向溢出的情况'],
          onResult: (value) => submitted = value,
        );
        expect(find.byType(EditableText), findsNothing);
        final input = find.byKey(const ValueKey('tv-search-input'));
        focusRemote(tester, input);
        await tester.pumpAndSettle();
        final before = FocusManager.instance.primaryFocus;
        await press(tester, LogicalKeyboardKey.select);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('tv-text-editor')),
          '中文剧名',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsNothing);
        expect(FocusManager.instance.primaryFocus, same(before));
        expect(find.text('中文剧名'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        focusRemote(tester, find.byKey(const ValueKey('suggest-0')));
        await press(tester, LogicalKeyboardKey.select);
        expect(submitted, '非常长的合成剧名用于覆盖电视搜索窄列长标题横向溢出的情况');
      },
    );
  }

  testWidgets(
    'TV held confirm opens more once without short activation; lost focus cancels it',
    (tester) async {
      var short = 0, long = 0;
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: Column(
              children: [
                RemoteTarget(
                  key: const ValueKey('held-target'),
                  autofocus: true,
                  onPressed: () => short++,
                  onLongPress: () => long++,
                  child: const Text('影片'),
                ),
                RemoteButton(label: '另一个入口', onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.select);
      expect(short, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(long, 1);
      expect(short, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(long, 1);
      expect(short, 1);
    },
  );

  testWidgets(
    'TV home excludes completed series, exposes updates and returns from discovery',
    (tester) async {
      size(tester, const Size(960, 540));
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const ongoing = Drama(
        id: 'hongguo:ongoing',
        source: 'hongguo',
        title: '待续播',
        episodes: 10,
      );
      const finished = Drama(
        id: 'hongguo:finished',
        source: 'hongguo',
        title: '已看完',
        episodes: 2,
      );
      await store.saveWatch(
        WatchEntry(
          drama: ongoing,
          episode: 2,
          position: 12,
          duration: 60,
          updatedAt: DateTime.utc(2026, 10, 11),
        ),
      );
      await store.saveWatch(
        WatchEntry(
          drama: finished,
          episode: 2,
          position: 60,
          duration: 60,
          updatedAt: DateTime.utc(2026, 10, 11),
        ),
      );
      await store.toggleFavorite(ongoing);
      await store.refreshDramas([
        const Drama(
          id: 'hongguo:ongoing',
          source: 'hongguo',
          title: '待续播',
          episodes: 12,
        ),
      ]);
      await tester.pumpWidget(
        DuanjuApp(
          repository: FixtureRepository(),
          store: store,
          television: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelevisionHome), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tv-home-continue-hongguo:ongoing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tv-home-continue-hongguo:finished')),
        findsNothing,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('追剧更新'), findsOneWidget);
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(TelevisionHome), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TelevisionHome), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-home');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('TV detail focuses playback when delayed episodes become ready', (
    tester,
  ) async {
    size(tester, const Size(960, 540));
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repository = DeferredLaunchRepository();
    await tester.pumpWidget(
      televisionHost(
        child: DetailScreen(
          drama: FixtureRepository.free,
          repository: repository,
          store: store,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('start-play')))
          .onPressed,
      isNull,
    );
    repository.pending.single.complete(
      DramaDetail(
        FixtureRepository.free,
        List.generate(
          80,
          (index) => Episode({'id': '${index + 1}'}, index + 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byKey(const ValueKey('start-play')))
          .contains(FocusManager.instance.primaryFocus!.rect.center),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
