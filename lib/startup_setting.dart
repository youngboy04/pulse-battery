import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const desktop = MethodChannel('pulse/desktop');

class StartupSetting extends StatefulWidget {
  const StartupSetting({super.key});
  @override
  State<StartupSetting> createState() => _StartupSettingState();
}

class _StartupSettingState extends State<StartupSetting> {
  bool? enabled;
  String? error;
  @override
  void initState() {
    super.initState();
    read();
  }

  Future<void> read() async {
    try {
      final value = await desktop.invokeMethod<bool>('getStartup');
      if (mounted) setState(() => enabled = value ?? false);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Запускать вместе с Windows'),
    subtitle: Text(
      error ?? 'После входа в систему — в трее, без главного окна.',
    ),
    value: enabled ?? false,
    onChanged: enabled == null
        ? null
        : (value) async {
            try {
              await desktop.invokeMethod<void>('setStartup', value);
              await read();
            } catch (e) {
              if (mounted) {
                setState(() => error = 'Не удалось изменить автозапуск: $e');
              }
            }
          },
  );
}
