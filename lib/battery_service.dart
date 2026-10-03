import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_registry.dart';
export 'device_registry.dart';

class BatteryService extends ChangeNotifier {
  BatteryService({this.probe, this.settingsFile});
  final File? settingsFile;
  final Future<List<Map<String, dynamic>>> Function()? probe;
  final registry = DeviceRegistry();
  List<DeviceState> get devices => registry.selectedDevices;
  List<DeviceState> get discoveredDevices => registry.selectableDevices;
  Future<void> _pendingSave = Future.value();
  Timer? _discoveryTimer;
  bool _refreshAgain = false;
  Process? _process;
  List<Map<String, dynamic>> diagnostics = [];
  bool busy = false,
      autoRefresh = true,
      notifications = true,
      _disposed = false;
  int interval = 60;
  int widgetTheme = 0;
  String? error;
  DateTime? updated;
  Timer? _timer;
  final Set<String> _notified = {};
  static const desktop = MethodChannel('pulse/desktop');
  String get updatedLabel => updated == null
      ? 'Ожидание данных'
      : 'Проверено в ${updated!.hour.toString().padLeft(2, '0')}:${updated!.minute.toString().padLeft(2, '0')}';
  File get _settings =>
      settingsFile ??
      File(
        '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}\\Pulse\\settings.json',
      );
  Future<void> start() async {
    desktop.setMethodCallHandler((call) async {
      if (call.method == 'refresh') await refresh();
      if (call.method == 'devicesChanged') devicesChanged();
      if (call.method == 'widgetThemeChanged' && !_disposed) {
        widgetTheme = call.arguments as int;
        notifyListeners();
      }
    });
    try {
      widgetTheme = await desktop.invokeMethod<int>('getWidgetTheme') ?? 0;
    } on MissingPluginException {
      // Tests without a native window.
    }
    try {
      if (await _settings.exists()) {
        final data = jsonDecode(await _settings.readAsString()) as Map;
        autoRefresh = data['autoRefresh'] != false;
        notifications = data['notifications'] != false;
        registry.restoreSelection(data['selectedDevices']);
        if ([30, 60, 120, 300].contains(data['interval'])) {
          interval = data['interval'];
        }
      }
    } catch (_) {
      /* Corrupt preferences revert to defaults. */
    }
    if (_disposed) return;
    _schedule();
    await refresh();
  }

  void _schedule() {
    _timer?.cancel();
    if (autoRefresh) {
      _timer = Timer.periodic(Duration(seconds: interval), (_) => refresh());
    }
  }

  Future<void> _save() {
    final contents = jsonEncode({
      'autoRefresh': autoRefresh,
      'interval': interval,
      'notifications': notifications,
      'selectedDevices': registry.savedSelection,
    });
    _pendingSave = _pendingSave.then((_) => _writeSettings(contents));
    return _pendingSave;
  }

  Future<void> _writeSettings(String contents) async {
    try {
      await _settings.parent.create(recursive: true);
      await _settings.writeAsString(contents, flush: true);
    } catch (_) {
      error = 'Не удалось сохранить настройки.';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setDeviceSelected(String id, bool selected) async {
    if (_disposed) return;
    registry.setSelected(id, selected);
    if (!selected) _notified.remove(id);
    notifyListeners();
    final saving = _save();
    await _publish();
    await saving;
  }

  void setInterval(int value) {
    interval = value;
    _schedule();
    notifyListeners();
    unawaited(_save());
  }

  void setAutoRefresh(bool value) {
    autoRefresh = value;
    _schedule();
    notifyListeners();
    unawaited(_save());
  }

  void setNotifications(bool value) {
    notifications = value;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> setWidgetTheme(int value) async {
    if (value < 0 || value > 3) return;
    try {
      await desktop.invokeMethod<void>('setWidgetTheme', value);
      widgetTheme = value;
      if (!_disposed) notifyListeners();
    } on MissingPluginException {
      widgetTheme = value;
      if (!_disposed) notifyListeners();
    }
  }

  /// Collapse the burst of notifications emitted by a composite USB device.
  void devicesChanged() {
    if (_disposed) return;
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(const Duration(milliseconds: 750), refresh);
  }

  Future<List<Map<String, dynamic>>> _readDevices() async {
    if (probe != null) return probe!();
    final adjacent = File(
      '${File(Platform.resolvedExecutable).parent.path}/pulse_hid.exe',
    );
    final local = File('build/windows/x64/native/Release/pulse_hid.exe');
    final exe = await adjacent.exists() ? adjacent : local;
    if (!await exe.exists()) {
      throw const FileSystemException(
        'Не найден pulse_hid.exe рядом с приложением',
      );
    }
    final process = await Process.start(exe.absolute.path, []);
    _process = process;
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          process.kill();
          throw TimeoutException('Устройства не ответили вовремя');
        },
      );
      final data = await output;
      final errorText = await errors;
      if (code != 0) throw Exception(errorText);
      return (jsonDecode(data) as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
    } finally {
      _process = null;
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (busy) {
      _refreshAgain = true;
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    unawaited(_publish());
    try {
      final rows = await _readDevices();
      if (_disposed) return;
      diagnostics = rows;
      registry.update(rows);
      updated = DateTime.now();
      for (final device in devices) {
        if (!device.fresh) continue;
        if (device.battery! > 25) _notified.remove(device.id);
        if (notifications &&
            device.battery! <= 20 &&
            !device.charging &&
            _notified.add(device.id)) {
          try {
            await desktop.invokeMethod(
              'notify',
              '${device.name}: осталось ${device.battery}%',
            );
          } on MissingPluginException {
            // Tests without a Windows host.
          } on PlatformException {
            _notified.remove(device.id);
          }
        }
      }
    } catch (e) {
      error =
          'Не удалось обновить устройства. ${e.toString().replaceFirst('Exception: ', '')}';
      registry.markStale();
    } finally {
      busy = false;
      if (!_disposed) {
        notifyListeners();
        await _publish();
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<void> _publish() async {
    try {
      await desktop.invokeMethod('publish', {
        'devices': devices.map((d) => d.toSnapshot()).toList(),
        'busy': busy,
        'updated': updatedLabel,
      });
    } on MissingPluginException {
      // Tests and platforms without the Windows host.
    } on PlatformException {
      // The window can be closing while a read finishes.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _discoveryTimer?.cancel();
    _process?.kill();
    super.dispose();
  }
}
