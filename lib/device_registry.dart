class DeviceState {
  DeviceState(
    this.id, {
    this.name = 'HID-устройство',
    this.manufacturer = '',
    this.kind = 'other',
    this.transport = 'HID',
    this.batterySupported = false,
  });
  final String id;
  String name, manufacturer, kind, transport;
  bool batterySupported;
  bool connected = false, fresh = false, charging = false;
  int? battery;
  DateTime? lastReading;
  String status = 'searching';
  String get label => switch (status) {
    'ok' =>
      charging
          ? 'Заряжается'
          : battery! <= 20
          ? 'Пора подзарядить'
          : 'Подключено',
    'searching' => 'Ищем устройство…',
    'disconnected' => 'Устройство отключено',
    'unsupported' => 'Заряд недоступен',
    'access_denied' => 'Устройство занято или недоступно',
    'asleep' => 'Устройство спит или вне связи',
    _ => 'Нет свежего ответа',
  };
  String get detail {
    if (fresh) return 'Заряд получен напрямую от устройства';
    if (lastReading != null) {
      return 'Последний заряд: ${lastReading!.hour.toString().padLeft(2, '0')}:${lastReading!.minute.toString().padLeft(2, '0')}. Ожидаем новый ответ.';
    }
    if (!connected) return 'Карточка обновится при повторном подключении.';
    if (!batterySupported) {
      return 'Устройство обнаружено. Чтение заряда этой модели пока не поддерживается.';
    }
    return 'Разбудите устройство и нажмите «Обновить»';
  }

  Map<String, dynamic> toSnapshot() => {
    'id': id,
    'name': name,
    'manufacturer': manufacturer,
    'kind': kind,
    'transport': transport,
    'batterySupported': batterySupported,
    'battery': battery,
    'fresh': fresh,
    'connected': connected,
    'charging': charging && fresh,
    'status': label,
  };
  void update(List<Map<String, dynamic>> rows) {
    connected = rows.isNotEmpty;
    fresh = false;
    charging = false;
    if (!connected) {
      status = 'disconnected';
      return;
    }
    final valid = rows.where(
      (r) =>
          r['status'] == 'ok' &&
          r['battery'] is int &&
          r['battery'] >= 0 &&
          r['battery'] <= 100,
    );
    if (valid.isNotEmpty) {
      final r = valid.first;
      battery = r['battery'];
      charging = r['charging'] == true;
      status = 'ok';
      fresh = true;
      lastReading = DateTime.now();
    } else {
      status = rows.any((r) => r['status'] == 'asleep')
          ? 'asleep'
          : rows.first['status'] as String? ?? 'no_response';
      if (status == 'ok') status = 'invalid_response';
    }
  }
}

/// One state per physical Windows device container, not per HID collection.
class DeviceRegistry {
  final Map<String, DeviceState> _known = {};
  final Set<String> _selected = {};
  bool isSelected(String id) => _selected.contains(id);
  List<DeviceState> get selectedDevices =>
      devices.where((d) => isSelected(d.id)).toList();
  List<DeviceState> get selectableDevices =>
      devices.where((d) => d.connected || isSelected(d.id)).toList();

  void setSelected(String id, bool selected) {
    if (!_known.containsKey(id)) return;
    if (selected) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
  }

  List<Map<String, dynamic>> get savedSelection => selectedDevices
      .map(
        (d) => {
          'id': d.id,
          'name': d.name,
          'manufacturer': d.manufacturer,
          'kind': d.kind,
          'transport': d.transport,
          'batterySupported': d.batterySupported,
        },
      )
      .toList();

  void restoreSelection(dynamic saved) {
    if (saved is! List) return;
    for (final item in saved) {
      if (item is! Map ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty) {
        continue;
      }
      final id = (item['id'] as String).toLowerCase();
      String field(String key, String fallback) =>
          item[key] is String ? item[key] as String : fallback;
      _known.putIfAbsent(
        id,
        () => DeviceState(
          id,
          name: field('name', 'HID-устройство'),
          manufacturer: field('manufacturer', ''),
          kind: field('kind', 'other'),
          transport: field('transport', 'HID'),
          batterySupported: item['batterySupported'] == true,
        )..update([]),
      );
      _selected.add(id);
    }
  }

  List<DeviceState> get devices {
    final result = _known.values.toList();
    result.sort((a, b) {
      if (a.connected != b.connected) return a.connected ? -1 : 1;
      if (a.batterySupported != b.batterySupported) {
        return a.batterySupported ? -1 : 1;
      }
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name == 0 ? a.id.compareTo(b.id) : name;
    });
    return result;
  }

  void update(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final id = (row['deviceId'] ?? row['path']) as String?;
      if (id == null || id.isEmpty) continue;
      groups.putIfAbsent(id.toLowerCase(), () => []).add(row);
    }
    for (final entry in groups.entries) {
      final interfaces = entry.value;
      final supported = interfaces
          .where((r) => r['batterySupported'] == true)
          .toList();
      final candidates = supported.isNotEmpty ? supported : interfaces;
      final ranked = candidates.toList();
      const priorities = {
        'gamepad': 0,
        'touch': 1,
        'mouse': 2,
        'keyboard': 3,
        'other': 4,
      };
      ranked.sort(
        (a, b) =>
            (priorities[a['kind']] ?? 4).compareTo(priorities[b['kind']] ?? 4),
      );
      final row = ranked.first;
      final device = _known.putIfAbsent(
        entry.key,
        () => DeviceState(entry.key),
      );
      device.name = (row['product'] as String?)?.trim() ?? '';
      if (device.name.isEmpty) {
        device.name = 'HID ${row['vid'] ?? '?'}:${row['pid'] ?? '?'}';
      }
      device.manufacturer = (row['manufacturer'] as String?)?.trim() ?? '';
      device.kind = row['kind'] as String? ?? 'other';
      device.transport = row['transport'] as String? ?? 'HID';
      device.batterySupported = supported.isNotEmpty;
      // Unrelated media/key collections cannot override the battery protocol's status.
      device.update(candidates);
    }
    for (final device in _known.values) {
      if (!groups.containsKey(device.id)) device.update([]);
    }
  }

  void markStale() {
    for (final device in _known.values) {
      device.fresh = false;
      device.charging = false;
      if (device.connected && device.batterySupported) {
        device.status = 'no_response';
      }
    }
  }
}
