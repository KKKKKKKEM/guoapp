import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'app_build.dart';

const appVersion = '0.2.87';

abstract final class TelevisionStyle {
  static const body = 20.0;
  static const secondary = 17.0;
  static const title = 28.0;
  static const target = 56.0;
  static const horizontalInset = 32.0;
  static const verticalInset = 20.0;
  static const safeInsets = EdgeInsets.symmetric(
    horizontal: horizontalInset,
    vertical: verticalInset,
  );
}

class TelevisionPageBody extends StatefulWidget {
  const TelevisionPageBody({
    super.key,
    required this.child,
    this.initialFocus = true,
  });
  final Widget child;
  final bool initialFocus;
  @override
  State<TelevisionPageBody> createState() => _TelevisionPageBodyState();
}

class _TelevisionPageBodyState extends State<TelevisionPageBody> {
  final _scope = FocusScopeNode(debugLabel: 'tv-page-body');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.initialFocus &&
          AppLayout.isTelevision(context) &&
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          FocusManager.instance.primaryFocus is FocusScopeNode &&
          _scope.traversalDescendants.any(
            (node) => node.canRequestFocus && !node.skipTraversal,
          )) {
        _scope.requestFocus();
        _scope.nextFocus();
      }
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLayout.isTelevision(context)
      ? SafeArea(
          top: false,
          minimum: const EdgeInsets.only(
            left: TelevisionStyle.horizontalInset,
            right: TelevisionStyle.horizontalInset,
            bottom: TelevisionStyle.verticalInset,
          ),
          child: FocusScope(node: _scope, child: widget.child),
        )
      : widget.child;
}

ThemeData televisionTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused)
        ? BorderSide(color: colors.primary, width: 3)
        : null,
  );
  final focusBackground = WidgetStateProperty.resolveWith<Color?>(
    (states) =>
        states.contains(WidgetState.focused) ? colors.primaryContainer : null,
  );
  final text = theme.textTheme;
  final button = ButtonStyle(
    side: focusSide,
    minimumSize: const WidgetStatePropertyAll(
      Size(TelevisionStyle.target, TelevisionStyle.target),
    ),
    textStyle: WidgetStatePropertyAll(
      text.labelLarge?.copyWith(fontSize: TelevisionStyle.body),
    ),
  );
  return theme.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontSize: TelevisionStyle.title),
      titleMedium: text.titleMedium?.copyWith(fontSize: 22),
      titleSmall: text.titleSmall?.copyWith(fontSize: TelevisionStyle.body),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: TelevisionStyle.body),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: TelevisionStyle.body),
      bodySmall: text.bodySmall?.copyWith(fontSize: TelevisionStyle.secondary),
      labelLarge: text.labelLarge?.copyWith(fontSize: TelevisionStyle.body),
      labelMedium: text.labelMedium?.copyWith(
        fontSize: TelevisionStyle.secondary,
      ),
      labelSmall: text.labelSmall?.copyWith(fontSize: 16),
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      toolbarHeight: 72,
      titleSpacing: 24,
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      minTileHeight: 80,
      minVerticalPadding: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: text.bodyLarge?.copyWith(
        color: colors.onSurface,
        fontSize: TelevisionStyle.body,
      ),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontSize: TelevisionStyle.secondary,
      ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: text.labelLarge?.copyWith(
        color: colors.onSurface,
        fontSize: TelevisionStyle.secondary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? colors.primary
              : colors.outlineVariant,
          width: states.contains(WidgetState.focused) ? 3 : 1,
        ),
      ),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: text.titleLarge?.copyWith(
        color: colors.onSurface,
        fontSize: TelevisionStyle.title,
      ),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: colors.onSurface,
        fontSize: TelevisionStyle.body,
      ),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: text.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
        fontSize: TelevisionStyle.secondary,
      ),
    ),
    focusColor: colors.primaryContainer,
    iconButtonTheme: IconButtonThemeData(
      style: button.copyWith(backgroundColor: focusBackground),
    ),
    filledButtonTheme: FilledButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    textButtonTheme: TextButtonThemeData(
      style: button.copyWith(backgroundColor: focusBackground),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colors.primary, width: 3),
      ),
    ),
  );
}

class AppDevice {
  const AppDevice({this.television = false, this.version = appVersion});
  final bool television;
  final String version;
  static const channel = MethodChannel('duanju/device');

  static Future<AppDevice> detect({
    AppDevice fallback = const AppDevice(),
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const AppDevice();
    }
    try {
      final data = await channel
          .invokeMapMethod<String, dynamic>('deviceInfo')
          .timeout(const Duration(seconds: 2));
      final television = data?['television'];
      if (television is! bool) return fallback;
      final version = data?['version'];
      return AppDevice(
        television: television,
        version: version is String && version.isNotEmpty
            ? version
            : fallback.version,
      );
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    } on TimeoutException {
      return fallback;
    }
  }

  static Future<double> getBrightness() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 0.5;
    try {
      final value = await channel.invokeMethod<double>('getBrightness');
      return (value ?? 0.5).clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setBrightness(double brightness) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod('setBrightness', {
        'brightness': brightness.clamp(0.01, 1.0),
      });
    } catch (_) {}
  }

  static Future<void> resetBrightness() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod('resetBrightness');
    } catch (_) {}
  }
}

class AppLayout extends InheritedWidget {
  const AppLayout({
    super.key,
    required this.television,
    this.version = appVersion,
    required super.child,
  });
  final bool television;
  final String version;

  static bool isTelevision(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLayout>()?.television ??
      false;
  static String versionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLayout>()?.version ??
      appVersion;

  @override
  bool updateShouldNotify(AppLayout oldWidget) =>
      television != oldWidget.television || version != oldWidget.version;
}
