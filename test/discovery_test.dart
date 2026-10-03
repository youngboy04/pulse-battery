import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_battery/battery_service.dart';
import 'package:pulse_battery/compact_panel.dart';
import 'package:pulse_battery/main.dart';

Map<String, dynamic> row(
  String id, {
  bool supported = false,
  int? battery,
  String kind = 'other',
}) => {
  'deviceId': id,
  'path': 'path-$id',
  'product': 'Device $id',
  'kind': kind,
  'batterySupported': supported,
  'status': battery == null ? 'unsupported' : 'ok',
  'battery': battery,
};

class StaticService extends BatteryService {
  @override
  Future<void> start() async {}

  @override
  Future<void> setDeviceSelected(String id, bool selected) async {
    registry.setSelected(id, selected);
    notifyListeners();
  }
}

void main() {
  test('Collections merge by container; identical models remain separate', () {
    final registry = DeviceRegistry();
    registry.update([
      row('A', supported: true, battery: 80, kind: 'mouse'),
      for (var i = 0; i < 6; i++) {...row('a'), 'path': 'collection-$i'},
      {...row('B'), 'product': 'Device A'},
    ]);
    expect(registry.devices, hasLength(2));
    expect(registry.devices.first.battery, 80);
    expect(registry.devices.first.kind, 'mouse');
    expect(registry.devices.last.battery, isNull);
    expect(registry.devices.last.label, 'Заряд недоступен');
  });

  test('Reconnect restores same card; disconnected reading is stale', () {
    final registry = DeviceRegistry()
      ..update([row('a', supported: true, battery: 0)]);
    final device = registry.devices.single;
    registry.update([row('new')]);
    expect(device.connected, false);
    expect(device.fresh, false);
    expect(device.battery, 0);
    registry.update([row('a', supported: true, battery: 75)]);
    expect(registry.devices.first, same(device));
    expect(device.fresh, true);
    expect(device.battery, 75);
    expect(registry.devices, hasLength(2));
  });

  test(
    'Invalid reading and unrelated collections never mask protocol state',
    () {
      final registry = DeviceRegistry()
        ..update([
          {...row('a', supported: true, battery: 101), 'status': 'ok'},
          row('a'),
        ]);
      expect(registry.devices.single.battery, isNull);
      expect(registry.devices.single.status, 'invalid_response');
      registry.update([
        {...row('a', supported: true), 'status': 'asleep'},
        row('a'),
      ]);
      expect(registry.devices.single.status, 'asleep');
      registry.update([
        {'path': 'fallback', 'status': 'unsupported'},
      ]);
      expect(registry.devices.first.id, 'fallback');
    },
  );

  testWidgets(
    'Hotplug bursts debounce, work with timer off, and publish dynamic snapshot',
    (tester) async {
      var calls = 0;
      Map? published;
      const channel = MethodChannel('pulse/desktop');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'publish') published = call.arguments as Map;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final service = BatteryService(
        probe: () async {
          calls++;
          return [row('new')];
        },
      )..autoRefresh = false;
      for (var i = 0; i < 5; i++) {
        service.devicesChanged();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls, 0);
      await tester.pump(const Duration(milliseconds: 750));
      expect(calls, 1);
      expect(published!['devices'], isEmpty);
      expect(service.discoveredDevices.single.name, 'Device new');
      service.devicesChanged();
      service.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
    },
  );

  testWidgets(
    'Changes during a read queue one followup; failure retains stale cards',
    (tester) async {
      const channel = MethodChannel('pulse/desktop');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final pending = Completer<List<Map<String, dynamic>>>();
      var calls = 0;
      final service = BatteryService(
        probe: () async {
          calls++;
          if (calls == 1) return pending.future;
          if (calls == 2) return [row('b', supported: true, battery: 50)];
          throw Exception('probe failed');
        },
      );
      final first = service.refresh();
      await service.refresh();
      await service.refresh();
      pending.complete([row('a')]);
      await first;
      await tester.pump();
      expect(calls, 2);
      expect(service.registry.devices, hasLength(2));
      expect(service.discoveredDevices.first.id, 'b');
      await service.refresh();
      expect(service.error, contains('probe failed'));
      expect(service.discoveredDevices.first.battery, 50);
      expect(service.discoveredDevices.first.fresh, false);
      service.dispose();
    },
  );

  testWidgets(
    'Discovery waits for selection; dialog updates live and compact list scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(1060, 790);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = StaticService();
      await tester.pumpWidget(PulseApp(service: service));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Устройства пока не добавлены'),
        findsOneWidget,
      );
      service.registry.update([for (var i = 0; i < 5; i++) row('$i')]);
      service.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Device 4'), findsNothing);
      await tester.tap(find.text('Добавить устройства'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        final tile = find.byKey(ValueKey('select-$i'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      // New arrivals appear in the open picker without being selected.
      service.registry.update([for (var i = 0; i < 6; i++) row('$i')]);
      service.notifyListeners();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(find.text('Device 5'), findsOneWidget);
      expect(service.registry.isSelected('5'), false);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(find.text('Device 5'), findsNothing);
      expect(find.text('Заряд недоступен'), findsNWidgets(5));
      final snapshots = service.devices.map((d) => d.toSnapshot()).toList();
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = const Size(360, 282);
      await tester.pumpWidget(
        CompactApp(initialSnapshot: {'devices': snapshots}),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Device 4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
