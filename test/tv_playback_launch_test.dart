import 'dart:async';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_launch_screen.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'remote_test_helpers.dart';

class DeferredLaunchRepository extends FixtureRepository {
  final pending = <Completer<DramaDetail>>[];
  @override
  Future<DramaDetail> detail(Drama drama) {
    detailCalls++;
    final request = Completer<DramaDetail>();
    pending.add(request);
    return request.future;
  }
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    DeferredLaunchRepository repository,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      televisionHost(
        child: HomeScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    focusRemote(tester, find.byKey(ValueKey(FixtureRepository.free.id)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV movie confirmation gives immediate cancellable feedback and ignores held confirm',
    (tester) async {
      final repository = DeferredLaunchRepository();
      await mount(tester, repository);
      final originalFocus = FocusManager.instance.primaryFocus;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.byType(PlaybackLaunchScreen), findsNothing);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.byType(PlaybackLaunchScreen), findsOneWidget);
      expect(repository.detailCalls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      repository.pending.single.complete(
        DramaDetail(FixtureRepository.free, [
          Episode({'id': '1'}, 1),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackLaunchScreen), findsNothing);
      await settle(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(originalFocus));
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );
  testWidgets('failed TV movie preparation offers focused remote retry', (
    tester,
  ) async {
    final repository = DeferredLaunchRepository();
    await mount(tester, repository);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    repository.pending.first.completeError(AppFailure('合成网络错误'));
    await settle(tester);
    expect(find.text('合成网络错误'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-launch-retry');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(repository.detailCalls, 2);
    expect(find.text('正在获取剧集信息…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    repository.pending.last.complete(DramaDetail(FixtureRepository.free, []));
    await settle(tester);
    expect(find.byType(PlaybackLaunchScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}
