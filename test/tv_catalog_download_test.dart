import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:duanju_app/television_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'downloads_test.dart' show DownloadRepository;
import 'tv_poster_navigation_test.dart' show PosterRepository;
import 'remote_test_helpers.dart';

void main() {
  Future<LocalStore> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.pump();
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV catalog error controls can return upward to filters and navigation',
    (tester) async {
      final store = await setup(tester);
      final repository = FixtureRepository()..fail = true;
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await press(tester, LogicalKeyboardKey.select);
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      final category = find.byKey(const ValueKey('category-'));
      expect(
        tester
            .getRect(category)
            .contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
      expect(find.byType(TelevisionHome), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'TV catalog up path reaches filters and main navigation without leaving discovery',
    (tester) async {
      final store = await setup(tester);
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: PosterRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final category = find.byKey(const ValueKey('category-'));
      expect(
        tester
            .getRect(category)
            .contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-hongguo:3000',
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        tester
            .getRect(category)
            .contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
      expect(find.byType(TelevisionHome), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'TV catalog back restores its navigation and preserves the scrolled card',
    (tester) async {
      final store = await setup(tester);
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: PosterRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await press(tester, LogicalKeyboardKey.select);
      focusRemote(tester, find.byKey(const ValueKey('hongguo:3000')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final original = FocusManager.instance.primaryFocus;
      final grid = tester.widget<RemoteGrid>(find.byType(RemoteGrid).first);
      final offset = grid.controller!.offset;
      await systemBack(tester);
      expect(find.byType(TelevisionHome), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-0');
      expect(grid.controller!.offset, closeTo(offset, 1));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus, same(original));
      await systemBack(tester);
      await systemBack(tester);
      expect(find.byType(TelevisionHome), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'TV downloads return from episodes to collection before moving to main navigation',
    (tester) async {
      final store = await setup(tester);
      final repository = DownloadRepository()..jobs = [];
      repository.jobs = [
        repository.job(1, 'completed'),
        repository.job(2, 'paused'),
        repository.job(3, 'failed'),
      ];
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-3')));
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'downloads-search-entry',
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(
        find.byKey(const ValueKey('tv-download-back-collections')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('download-task-1')), findsOneWidget);
      await systemBack(tester);
      expect(
        find.byKey(const ValueKey('tv-download-back-collections')),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey('tv-download-collection-${FixtureRepository.free.id}'),
        ),
        findsOneWidget,
      );
      await systemBack(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-3');
      expect(find.byType(DownloadsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('TV failed download can retry through focused episode controls', (
    tester,
  ) async {
    final store = await setup(tester);
    final repository = DownloadRepository();
    repository.jobs = [
      repository.job(1, 'completed'),
      repository.job(2, 'paused'),
      repository.job(3, 'failed'),
    ];
    await tester.pumpWidget(
      televisionHost(
        child: DownloadsScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    focusRemote(
      tester,
      find.byKey(const ValueKey('tv-download-filter-failed')),
    );
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('download-task-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('download-task-1')), findsNothing);
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.select);
    expect(repository.jobs.singleWhere((job) => job.id == '3').state, 'queued');
    expect(repository.commands, contains('resume:3'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('TV download deletion confirmation preserves files on cancel', (
    tester,
  ) async {
    final store = await setup(tester);
    final repository = DownloadRepository()..jobs = [];
    repository.jobs = [repository.job(1, 'completed')];
    await tester.pumpWidget(
      televisionHost(
        child: DownloadsScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    final collection = find.byKey(
      ValueKey('tv-download-collection-${FixtureRepository.free.id}'),
    );
    focusRemote(tester, collection);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    focusRemote(
      tester,
      find.byKey(const ValueKey('tv-download-action-remove')),
    );
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.select);
    expect(repository.jobs.single.id, '1');
    expect(repository.commands, isNot(contains('remove:1')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('TV selected downloads reach batch controls without a pointer', (
    tester,
  ) async {
    final store = await setup(tester);
    final repository = DownloadRepository();
    repository.jobs = [
      repository.job(1, 'paused'),
      repository.job(2, 'paused'),
      repository.job(3, 'paused'),
    ];
    await tester.pumpWidget(
      televisionHost(
        child: DownloadsScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    focusRemote(
      tester,
      find.byKey(
        ValueKey('tv-download-collection-${FixtureRepository.free.id}'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    focusRemote(
      tester,
      find.byKey(const ValueKey('tv-download-action-select')),
    );
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-download-batch');
    await press(tester, LogicalKeyboardKey.select);
    focusRemote(
      tester,
      find.byKey(const ValueKey('tv-download-action-resume')),
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(repository.jobs.map((job) => job.state), everyElement('queued'));
    focusRemote(
      tester,
      find.byKey(const ValueKey('tv-download-filter-paused')),
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(
      find.byKey(
        ValueKey('tv-download-collection-${FixtureRepository.free.id}'),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
