import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'remote_test_helpers.dart';

class PosterRepository extends FixtureRepository {
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage(
    List.generate(
      48,
      (i) => Drama(
        id: '$source:${3000 + i}',
        source: source,
        title: '合成剧集 ${i + 1}',
        episodes: 20,
        category: '遥控器测试',
      ),
    ),
    page: page,
    hasMore: false,
  );
  @override
  Future<DramaDetail> detail(Drama drama) async => DramaDetail(drama, [
    Episode({'id': '1', 'vip': true}, 1),
  ]);
}

void main() {
  testWidgets(
    'TV posters retain scroll and focus after confirmation and more menu',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: PosterRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      final top = tester.getRect(
        find.byKey(const ValueKey('tv-top-navigation')),
      );
      final secondNav = tester.getRect(find.byKey(const ValueKey('tv-nav-1')));
      focusRemote(tester, find.byKey(const ValueKey('tv-nav-0')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        secondNav.contains(FocusManager.instance.primaryFocus!.rect.center),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.rect.center.dy,
        greaterThan(top.bottom),
      );
      focusRemote(tester, find.byKey(const ValueKey('hongguo:3000')));
      await tester.pumpAndSettle();
      final firstPoster = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(firstPoster));
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final before = FocusManager.instance.primaryFocus;
      expect(before?.debugLabel, isNot('remote-hongguo:3000'));
      final grid = tester.widget<RemoteGrid>(find.byType(RemoteGrid).first);
      final offset = grid.controller!.offset;
      expect(offset, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('这是一集 VIP 内容'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(before));
      expect(grid.controller!.offset, closeTo(offset, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(before)));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(before));
      expect(grid.controller!.offset, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
