import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_battery/main.dart';
import 'package:pulse_battery/battery_service.dart';
import 'package:pulse_battery/compact_panel.dart';
import 'package:pulse_battery/widget_theme.dart';

class PreviewService extends BatteryService {
  @override
  Future<void> start() async {
    registry.update([
      {
        'deviceId': 'mouse',
        'product': 'A7 V2 Pro',
        'manufacturer': 'MCHOSE',
        'kind': 'mouse',
        'batterySupported': true,
        'transport': '2.4 ГГц',
        'status': 'ok',
        'battery': 97,
        'charging': false,
      },
      {
        'deviceId': 'keyboard',
        'product': 'Galaxy70',
        'manufacturer': 'EPOMAKER',
        'kind': 'keyboard',
        'batterySupported': true,
        'transport': '2.4 ГГц',
        'status': 'ok',
        'battery': 95,
      },
    ]);
    for (final device in registry.devices) {
      registry.setSelected(device.id, true);
    }
    notifyListeners();
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  test('Disconnect and sleep retain the last reading but mark it stale', () {
    final d = DeviceState('mouse');
    d.update([
      {'status': 'ok', 'battery': 97},
    ]);
    d.update([
      {'status': 'asleep', 'battery': null},
    ]);
    expect(d.battery, 97);
    expect(d.fresh, false);
    expect(d.connected, true);
    d.update([]);
    expect(d.battery, 97);
    expect(d.connected, false);
    expect(d.status, 'disconnected');
  });
  test('Invalid percentage is never published, valid zero is supported', () {
    final d = DeviceState('mouse');
    d.update([
      {'status': 'invalid_response', 'battery': 101},
    ]);
    expect(d.battery, isNull);
    d.update([
      {'status': 'ok', 'battery': 0},
    ]);
    expect(d.battery, 0);
    expect(d.fresh, true);
  });
  testWidgets('Desktop layout, settings, and narrow layout do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1060, 790);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Segoe UI')
          ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
        await loader.load();
      }
    });
    await tester.pumpWidget(PulseApp(service: PreviewService()));
    await tester.pumpAndSettle();
    expect(find.text('97'), findsOneWidget);
    expect(find.text('95'), findsOneWidget);
    expect(find.text('Энергия вашего сетапа'), findsNothing);
    expect(find.text('Меньше забот о заряде'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dashboard.png'),
    );
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Интервал проверки'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Устройства'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(680, 580);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Theme loads, saves, and follows changes from another window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 282);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('pulse/desktop');
    var savedTheme = 2;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getSnapshot':
          return <String, dynamic>{};
        case 'getPinned':
          return false;
        case 'getWidgetTheme':
          return savedTheme;
        case 'setWidgetTheme':
          savedTheme = call.arguments as int;
          return null;
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const CompactApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Тема виджета'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WidgetThemePicker>(find.byType(WidgetThemePicker)).selected,
      2,
    );
    await tester.tap(find.byKey(const ValueKey('theme-1')));
    await tester.pumpAndSettle();
    expect(savedTheme, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const CompactApp(tray: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Тема виджета'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WidgetThemePicker>(find.byType(WidgetThemePicker)).selected,
      1,
    );
    tester.binding.channelBuffers.push(
      'pulse/desktop',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('widgetThemeChanged', 3),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<WidgetThemePicker>(find.byType(WidgetThemePicker)).selected,
      3,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Compact widget and tray share readings and mark stale data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 282);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mouse =
        DeviceState(
          'mouse',
          name: 'A7 V2 Pro',
          manufacturer: 'MCHOSE',
          kind: 'mouse',
        )..update([
          {'status': 'ok', 'battery': 97},
        ]);
    final keyboard =
        DeviceState(
          'keyboard',
          name: 'Galaxy70',
          manufacturer: 'EPOMAKER',
          kind: 'keyboard',
        )..update([
          {'status': 'ok', 'battery': 95},
        ]);
    final snapshot = {
      'devices': [mouse.toSnapshot(), keyboard.toSnapshot()],
      'busy': false,
      'updated': 'Проверено в 20:45',
    };
    await tester.pumpWidget(CompactApp(initialSnapshot: snapshot));
    await tester.pumpAndSettle();
    expect(find.text('97%'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/widget.png'),
    );
    await tester.tap(find.byTooltip('Тема виджета'));
    await tester.pumpAndSettle();
    expect(find.text('Лесной фонарь'), findsOneWidget);
    expect(find.text('Графит'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/theme_picker.png'),
    );
    await tester.tap(find.byKey(const ValueKey('theme-1')));
    await tester.pumpAndSettle();
    expect(find.text('97%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final palette in WidgetPalette.all) {
      await tester.pumpWidget(
        CompactApp(
          key: ValueKey('palette-${palette.id}'),
          initialTheme: palette.id,
          initialSnapshot: snapshot,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/theme_${palette.id}.png'),
      );
    }
    await tester.pumpWidget(
      CompactApp(
        key: const ValueKey('tray'),
        tray: true,
        initialSnapshot: snapshot,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Виджет на рабочем столе'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tray.png'),
    );
    keyboard.update([
      {'status': 'asleep', 'battery': null},
    ]);
    await tester.pumpWidget(
      CompactApp(
        key: const ValueKey('stale'),
        initialSnapshot: {
          ...snapshot,
          'devices': [mouse.toSnapshot(), keyboard.toSnapshot()],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('ранее'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
