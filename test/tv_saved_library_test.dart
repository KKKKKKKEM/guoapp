import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/follow_state.dart';
import 'package:duanju_app/saved_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'remote_test_helpers.dart';

void main() {
  for (final history in [true, false]) {
    for (final populated in [true, false]) {
      testWidgets(
        'TV ${history ? 'history' : 'favorites'} search is navigable, populated=$populated',
        (tester) async {
          tester.view.physicalSize = const Size(960, 540);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          final store = LocalStore(await SharedPreferences.getInstance());
          addTearDown(store.dispose);
          if (populated) {
            await store.saveWatch(
              WatchEntry(
                drama: FixtureRepository.free,
                episode: 1,
                position: 12,
                duration: 60,
                updatedAt: DateTime.utc(2026, 10, 11),
              ),
            );
            if (!history) await store.toggleFavorite(FixtureRepository.free);
          }
          await tester.pumpWidget(
            televisionHost(
              child: HomeScreen(repository: FixtureRepository(), store: store),
            ),
          );
          await tester.pumpAndSettle();
          final nav = find.byKey(ValueKey('tv-nav-${history ? 2 : 1}'));
          focusRemote(tester, nav);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          final entry = FocusManager.instance.primaryFocus;
          final search = find.byKey(
            ValueKey(history ? 'history-search' : 'favorites-search'),
          );
          expect(tester.getRect(search).contains(entry!.rect.center), isTrue);
          expect(tester.testTextInput.isVisible, isFalse);
          expect(find.byType(EditableText), findsNothing);
          if (populated) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
            expect(FocusManager.instance.primaryFocus, isNot(same(entry)));
            expect(tester.testTextInput.isVisible, isFalse);
            focusRemote(tester, search);
            await tester.pumpAndSettle();
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus!.rect.overlaps(
              tester.getRect(nav),
            ),
            isTrue,
          );
          focusRemote(tester, search);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('tv-text-editor')),
            '不存在的记录',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(find.byType(EditableText), findsNothing);
          expect(FocusManager.instance.primaryFocus, same(entry));
          if (populated) expect(find.text('没有匹配的记录'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
          expect(
            FocusManager.instance.primaryFocus!.rect.overlaps(
              tester.getRect(nav),
            ),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets(
    'TV following updates filter hands focus between sidebar and cards',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const updated = Drama(
        id: 'hongguo:updated',
        source: 'hongguo',
        title: '有更新的合成剧',
        episodes: 3,
      );
      const planned = Drama(
        id: 'hongguo:planned',
        source: 'hongguo',
        title: '想看的合成剧',
        episodes: 4,
      );
      await store.setFollowStatus(updated, FollowStatus.watching);
      await store.setFollowStatus(planned, FollowStatus.planned);
      await store.refreshDrama(
        const Drama(
          id: 'hongguo:updated',
          source: 'hongguo',
          title: '有更新的合成剧',
          episodes: 5,
        ),
      );
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: SavedLibrary(
              repository: FixtureRepository(),
              store: store,
              history: false,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('follow-filter-updates'));
      focusRemote(tester, filter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('saved-hongguo:updated')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('saved-hongguo:planned')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('saved-hongguo:updated')))
            .contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(filter)
            .contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'TV history distinguishes an ended episode from a finished series',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const ongoing = Drama(
        id: 'hongguo:ongoing',
        source: 'hongguo',
        title: '未看完的合成剧',
        episodes: 5,
      );
      const next = Drama(
        id: 'hongguo:next',
        source: 'hongguo',
        title: '还有下一集的合成剧',
        episodes: 5,
      );
      const finished = Drama(
        id: 'hongguo:finished',
        source: 'hongguo',
        title: '已经看完的合成剧',
        episodes: 2,
      );
      for (final entry in [
        (ongoing, 1, 12.0),
        (next, 1, 60.0),
        (finished, 2, 60.0),
      ]) {
        await store.saveWatch(
          WatchEntry(
            drama: entry.$1,
            episode: entry.$2,
            position: entry.$3,
            duration: 60,
            updatedAt: DateTime.utc(2026, 10, 11),
          ),
        );
      }
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: SavedLibrary(
              repository: FixtureRepository(),
              store: store,
              history: true,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('history-filter-continue')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('saved-hongguo:ongoing')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('saved-hongguo:next')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('saved-hongguo:finished')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('history-filter-finished')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('saved-hongguo:ongoing')), findsNothing);
      expect(find.byKey(const ValueKey('saved-hongguo:next')), findsNothing);
      expect(
        find.byKey(const ValueKey('saved-hongguo:finished')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('tv-clear-history')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(store.history.map((entry) => entry.drama.id).toSet(), {
        ongoing.id,
        next.id,
        finished.id,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
