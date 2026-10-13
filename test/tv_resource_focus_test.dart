import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/resource_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';
import 'remote_test_helpers.dart';

void main() {
  testWidgets(
    'TV request interval allows vertical exit and explicit selection',
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
          child: ResourceSettingsScreen(
            repository: FixtureRepository(),
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final interval = find.byKey(const ValueKey('tv-request-interval'));
      await tester.ensureVisible(interval);
      await tester.pumpAndSettle();
      focusRemote(tester, interval);
      await tester.pumpAndSettle();
      final node = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(node)));
      expect(find.text('选择间隔：250 毫秒'), findsOneWidget);
      focusRemote(tester, interval);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-interval-250',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('选择间隔：300 毫秒'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(node));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
