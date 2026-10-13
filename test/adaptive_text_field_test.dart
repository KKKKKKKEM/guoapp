import 'package:duanju_app/episode_browser.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/adaptive_text_field.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_test_helpers.dart';

void main() {
  testWidgets(
    'TV arrows cross an input without showing IME; confirm edits and back cancels',
    (tester) async {
      final controller = TextEditingController();
      final before = FocusNode();
      final after = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: Column(
              children: [
                RemoteButton(
                  label: '上方',
                  autofocus: true,
                  focusNode: before,
                  onPressed: () {},
                ),
                AdaptiveTextField(
                  key: const ValueKey('field'),
                  controller: controller,
                  decoration: const InputDecoration(hintText: '搜索观看记录'),
                ),
                RemoteButton(label: '下方', focusNode: after, onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final entry = FocusManager.instance.primaryFocus;
      expect(entry, isNot(same(before)));
      expect(entry, isNot(same(after)));
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(EditableText), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(after));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(entry));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('tv-text-editor')),
        '未提交的词',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(find.byType(EditableText), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(entry));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(after));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV editor commits once and returns focus; clear commits an empty search',
    (tester) async {
      final controller = TextEditingController(text: '旧词');
      final changes = <String>[];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: AdaptiveTextField(
              controller: controller,
              autofocus: true,
              onChanged: changes.add,
              decoration: const InputDecoration(labelText: '搜索'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tv-text-editor')),
        '新词',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.text, '新词');
      expect(changes, ['新词']);
      expect(FocusManager.instance.primaryFocus, same(entry));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(changes, ['新词', '']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV secret preview stays masked and editor supports explicit reveal',
    (tester) async {
      final controller = TextEditingController(text: 'secret-value');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: AdaptiveTextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('secret-value'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tv-text-editor')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('显示内容'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tv-text-editor')))
            .obscureText,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('secret-value'), findsNothing);
      expect(controller.text, 'secret-value');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('phone input preserves direct typing and onChanged behavior', (
    tester,
  ) async {
    final controller = TextEditingController();
    final changes = <String>[];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveTextField(
            key: const ValueKey('phone'),
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('phone')), '手机输入');
    expect(controller.text, '手机输入');
    expect(changes, ['手机输入']);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'TV episode jump input cancels one layer and submits a valid episode',
    (tester) async {
      var selected = -1;
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: EpisodeRangeBar(
              episodes: List.generate(20, (i) => Episode({'id': '$i'}, i + 1)),
              page: 0,
              onLocate: (index) => selected = index,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('跳转集数'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(selected, -1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tv-text-editor')),
        '12',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(selected, 11);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
