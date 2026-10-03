import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_battery/battery_service.dart';

Map<String, dynamic> device(String id) => {
  'deviceId': id,
  'product': 'Device $id',
  'kind': 'mouse',
  'batterySupported': true,
  'status': 'ok',
  'battery': 10,
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pulse/desktop');
  late Directory temporary;
  late File settings;
  late List<MethodCall> calls;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('pulse-selection-');
    settings = File('${temporary.path}/settings.json');
    await settings.writeAsString(
      jsonEncode({'autoRefresh': false, 'interval': 120}),
    );
    calls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'getWidgetTheme' ? 0 : null;
    });
  });
  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
    await temporary.delete(recursive: true);
  });

  test(
    'Selection persists, restores offline cards, and removal stays removed on reconnect',
    () async {
      var rows = [device('a'), device('b')];
      var service = BatteryService(
        settingsFile: settings,
        probe: () async => rows,
      );
      await service.start();
      expect(service.discoveredDevices, hasLength(2));
      expect(service.devices, isEmpty);
      expect(calls.where((c) => c.method == 'notify'), isEmpty);
      await service.setDeviceSelected('a', true);
      expect(service.devices.single.id, 'a');
      await service.refresh();
      expect(calls.where((c) => c.method == 'notify'), hasLength(1));
      expect(
        calls.where((c) => c.method == 'notify').single.arguments,
        contains('Device a'),
      );
      final snapshot =
          calls.lastWhere((c) => c.method == 'publish').arguments as Map;
      expect((snapshot['devices'] as List).single['id'], 'a');
      service.dispose();

      rows = [];
      service = BatteryService(settingsFile: settings, probe: () async => rows);
      await service.start();
      expect(service.devices.single.name, 'Device a');
      expect(service.devices.single.connected, false);
      expect(service.devices.single.battery, isNull);
      expect(service.interval, 120);
      rows = [device('a'), device('b'), device('new')];
      await service.refresh();
      expect(service.devices.single.id, 'a');
      expect(service.devices.single.connected, true);
      await service.setDeviceSelected('a', false);
      expect(service.devices, isEmpty);
      expect(
        (calls.lastWhere((c) => c.method == 'publish').arguments
            as Map)['devices'],
        isEmpty,
      );
      await service.refresh();
      expect(service.devices, isEmpty);
      service.dispose();

      service = BatteryService(settingsFile: settings, probe: () async => rows);
      await service.start();
      expect(service.devices, isEmpty);
      expect(service.discoveredDevices, hasLength(3));
      service.dispose();
    },
  );

  test(
    'Rapid toggles are saved in order; only the final choice is restored',
    () async {
      final service = BatteryService(
        settingsFile: settings,
        probe: () async => [device('a'), device('b')],
      );
      await service.start();
      await Future.wait([
        service.setDeviceSelected('a', true),
        service.setDeviceSelected('b', true),
        service.setDeviceSelected('a', false),
      ]);
      final saved = jsonDecode(await settings.readAsString()) as Map;
      expect((saved['selectedDevices'] as List).single['id'], 'b');
      expect(saved['autoRefresh'], false);
      expect(saved['interval'], 120);
      service.dispose();
    },
  );
}
